"""Modelo de oro del lazo de corriente PR del conversor matricial.

Replica bit a bit la aritmetica del RTL para poder (a) cerrar la sintonia
antes de escribir VHDL y (b) servir de oraculo contra el que se comparan los
bloques del RTL.

Referencia: docs/superpowers/specs/2026-09-17-control-corriente-salida-design.md
"""

import math

from fixedpoint import Q, mul_trunc

# --- formatos (spec 5.3) --------------------------------------------------
Q8_24 = Q(8, 24)
Q8_40 = Q(8, 40)
Q1_24 = Q(1, 24)

# --- parametros del sistema, fuente unica de verdad ----------------------
F_CLK = 10e6                 # FCLK_CLK0 del PS7
T_CLK = 1.0 / F_CLK          # 100 ns
N_CLK_TS = 2048              # ciclos de la ventana `estado` del modulador
TS = N_CLK_TS * T_CLK        # 204,8 us

# Carga RL por fase. Coincide con SW/matlab/LecturaDatosVivado.m.
# OJO: create_bd.tcl tenia a0=a1=6989, que implica R=12 mOhm y L=120 uH --
# misma tau (por eso b1 no cambia) pero 100x la ganancia. Se corrige a 70.
R = 1.2                      # ohm
L = 12e-3                    # H

# --- sintonia por defecto ------------------------------------------------
# Kp = w_c*L - R con f_c = 150 Hz. El ancho de banda lo limita Ts: 150 Hz
# contra 50 Hz de fundamental son tres octavas escasas (spec 5.5).
F_C = 150.0
KP_DEF = 2.0 * math.pi * F_C * L - R                      # 10,1097

# Kr fija la velocidad con que se anula el error en w_o. El polo resonante
# de lazo cerrado se corre delta = Kr/(2*|R + j*w_o*L|), asi que para una
# constante de tiempo tau:
#
#     Kr = 2*|Z(w_o)| / tau            [ohm/s]
#
# NO `2*L/tau`, que es lo que decia el spec 5.5: eso tiene unidades de ohm,
# no de ohm/s, y da 1,2 en vez de 395,6 -- un factor 330 que deja al
# resonante sin efecto util (error de regimen 27 % en vez de 0,13 %).
TAU_RES = 20e-3                                           # un periodo de 50 Hz
KR_DEF = 2.0 * abs(complex(R, 2.0 * math.pi * 50.0 * L)) / TAU_RES   # 395,63


def coef_rl(r, l, t):
    """Coeficientes bilineales de 1/(R+sL) muestreado a t.

    Devuelve (a0, a1, b1) tal que I[n] = a0*U[n] + a1*U[n-1] + b1*I[n-1],
    que es exactamente la forma que implementa HW/src/hdl/RL_fase.vhd.
    """
    d = 2.0 * l + r * t
    return t / d, t / d, (2.0 * l - r * t) / d


def coef_rl_q824(r, l, t):
    """Los mismos coeficientes cuantizados a Q8.24, como los toma RL_fase."""
    a0, a1, b1 = coef_rl(r, l, t)
    return (Q8_24.de_float(a0, redondear=True),
            Q8_24.de_float(a1, redondear=True),
            Q8_24.de_float(b1, redondear=True))


def paso_nco(f):
    """Paso de fase de 32 bits para una frecuencia f, como i_frec de AC_Source."""
    return int(round(f * 2.0**32 / F_CLK))


def k_resonante(f_o):
    """Coeficiente k del resonador, con pre-warping: k = 2*sin(w_o*Ts/2).

    Asi la frecuencia que realiza el resonador, (2/Ts)*asin(k/2), es
    exactamente w_o (spec 5.1).
    """
    return 2.0 * math.sin(math.pi * f_o * TS)


def k_q124(f_o):
    """k cuantizado a Q1.24. Falla explicitamente si no entra en el formato."""
    k = k_resonante(f_o)
    if not 0.0 <= k < 1.0:
        raise ValueError(
            "k = %.6f fuera de Q1.24 para f_o = %.1f Hz; el maximo es "
            "%.1f Hz" % (k, f_o, 1.0 / (6.0 * TS)))
    return Q1_24.de_float(k, redondear=True)


class PlantaRL_Ts(object):
    """Planta RL discretizada exacta (ZOH) al periodo de control Ts.

    Es la que se usa para sintonizar: un paso por Ts en vez de 2048.
    """

    def __init__(self, r=R, l=L, ts=TS):
        self.polo = math.exp(-r * ts / l)
        self.gan = (1.0 - self.polo) / r
        self.i = 0.0

    def paso(self, v):
        self.i = self.polo * self.i + self.gan * v
        return self.i


class PlantaRL_Clk(object):
    """Replica bit a bit de RL_fase.vhd: IIR bilineal en Q8.24 a 10 MHz.

    RL_fase no tiene enable, asi que avanza en cada flanco del reloj.

    Los tres productos se suman con los 48 bits fraccionarios completos y se
    trunca UNA sola vez al final, que es lo que hace el RTL: mult_a0/a1/b1
    son sfixed(..downto -48) y el unico resize a Q8.24 esta en I_n.

    Ese unico truncamiento igual cuesta caro: como b1 = 0,99999, el medio LSB
    que se pierde en b1*I[n-1] queda amplificado por 1/(1-b1) ~ 1e5 y deja un
    error de ganancia DC sistematico de -0,71 %.
    """

    def __init__(self, r=R, l=L, t=T_CLK):
        self.a0, self.a1, self.b1 = coef_rl_q824(r, l, t)
        self.u_z1 = 0
        self.i_z1 = 0

    def paso(self, u):
        suma = self.a0 * u + self.a1 * self.u_z1 + self.b1 * self.i_z1
        i = Q8_24.envolver(suma >> 24)
        self.u_z1 = u
        self.i_z1 = i
        return i


def matriz_transicion(k):
    """Matriz de transicion del resonador discretizado forward-backward.

    x1[n] = x1[n-1] - k*x2[n-1] + b*e[n]
    x2[n] = x2[n-1] + k*x1[n]

    Sustituyendo x1[n] en la segunda: A = [[1, -k], [k, 1-k^2]], cuyo
    determinante es 1-k^2+k^2 = 1 para cualquier k. Por eso los polos quedan
    sobre el circulo unidad aunque k este mal cuantizado (spec 5.1).

    Ojo: det(A) = 1 NO significa que A sea ortogonal. Lo que la rotacion
    conserva es la forma cuadratica x1^2 + x2^2 - k*x1*x2, no el modulo
    euclideo.
    """
    return ((1.0, -k), (k, 1.0 - k * k))


class PR2Int(object):
    """Un eje del controlador PR: proporcional + resonador de dos integradores.

    Todos los estados y coeficientes son enteros en sus formatos Q; la
    aritmetica es identica a la que hace PR_2int.vhd.
    """

    def __init__(self, k_i, b_i, kp_i):
        self.k = k_i         # Q1.24
        self.b = b_i         # Q8.24, vale Kr*Ts
        self.kp = kp_i       # Q8.24
        self.x1 = 0          # Q8.40
        self.x2 = 0          # Q8.40

    def reset(self):
        self.x1 = 0
        self.x2 = 0

    def paso(self, e, sat):
        """Un periodo de control. `e` en Q8.24, devuelve `u` en Q8.24."""
        # k (Q1.24) * x2 (Q8.40) -> Q8.40
        k_x2 = mul_trunc(self.k, self.x2, 24, 40, 40)
        # b (Q8.24) * e (Q8.24) -> Q8.40. Congelado si el modulo saturo.
        b_e = 0 if sat else mul_trunc(self.b, e, 24, 24, 40)

        self.x1 = Q8_40.envolver(self.x1 - k_x2 + b_e)
        # El segundo integrador usa el x1 YA actualizado (backward).
        self.x2 = Q8_40.envolver(self.x2 + mul_trunc(self.k, self.x1, 24, 40, 40))

        kp_e = mul_trunc(self.kp, e, 24, 24, 24)
        return Q8_24.envolver(kp_e + (self.x1 >> 16))   # x1 Q8.40 -> Q8.24


# --- CORDIC en modo vectoring --------------------------------------------
ITER_CORDIC = 20

K_CORDIC = 1.0
for _i in range(ITER_CORDIC):
    K_CORDIC *= math.sqrt(1.0 + 2.0 ** (-2 * _i))

INV_K_Q824 = Q8_24.de_float(1.0 / K_CORDIC, redondear=True)


def cordic_vec(x, y, iteraciones=ITER_CORDIC):
    """CORDIC vectoring en Q8.24: devuelve (modulo Q8.24, angulo 11 bits).

    El angulo usa la misma codificacion BAM de 11 bits que CORDIC_atan2.vhd
    y red_sector.vhd: 2048 pasos para una vuelta completa.
    """
    if x == 0 and y == 0:
        return 0, 0

    # Pre-rotacion al semiplano x >= 0, como hace el RTL.
    if x < 0:
        x, y = -x, -y
        z = 1024                      # media vuelta en 11 bits
    else:
        z = 0

    for i in range(iteraciones):
        dx = x >> i
        dy = y >> i
        paso = int(round(math.atan(2.0 ** (-i)) * 2048.0 / (2.0 * math.pi)))
        if y < 0:
            x, y, z = x - dy, y + dx, z - paso
        else:
            x, y, z = x + dy, y - dx, z + paso

    mag = mul_trunc(x, INV_K_Q824, 24, 24, 24)
    return mag, z % 2048


# --- generador de referencia ---------------------------------------------
class RefGen(object):
    """NCO que emite la referencia directamente en alfa/beta.

    El acumulador de fase es de 32 bits y avanza `paso_fase` por periodo de
    control, igual que el i_frec de AC_Source pero muestreado a Ts.

    Ojo: este modelo usa math.cos/sin, mientras que RefGen.vhd usa la LUT de
    seno del repo. No son bit a bit iguales, y no hace falta que lo sean: el
    paquete de vectores solo lleva los del PR, y tb_RefGen verifica
    propiedades (amplitud, cuadratura), no igualdad contra este modelo.
    """

    def __init__(self, paso_fase, amp_i):
        self.paso_fase = paso_fase * N_CLK_TS     # avance por Ts, no por clk
        self.amp = amp_i                          # Q8.24
        self.fase = 0

    def paso(self):
        theta = 2.0 * math.pi * (self.fase / 2.0**32)
        a = mul_trunc(self.amp, Q8_24.de_float(math.cos(theta)), 24, 24, 24)
        b = mul_trunc(self.amp, Q8_24.de_float(math.sin(theta)), 24, 24, 24)
        self.fase = (self.fase + self.paso_fase) % (2**32)
        return a, b


# --- normalizacion y saturacion ------------------------------------------
Q_BITS = 9                                # ancho de i_q_i


def normalizar(mag, inv_vi, q_max):
    """De |v*| en Q8.24 a la palabra q de 9 bits que toma el modulador.

    q_max viene en Q1.24 y mag*inv_vi queda en Q8.24: los dos tienen 24 bits
    fraccionarios, asi que se comparan directo. La palabra de salida es q
    escalado por 512, que es la codificacion de i_q_i.
    """
    q_pu = mul_trunc(mag, inv_vi, 24, 24, 24)     # Q8.24
    sat = q_pu > q_max
    if sat:
        q_pu = q_max
    palabra = (q_pu * (1 << Q_BITS)) >> 24
    return max(0, min((1 << Q_BITS) - 1, palabra)), sat
