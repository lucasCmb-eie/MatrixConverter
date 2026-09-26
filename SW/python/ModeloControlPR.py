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
# tau_res = L/R = 10 ms: el resonante converge tan rapido como la dinamica
# propia de la carga, no mas. El spec 5.5 decia 20 ms, pero con ese valor el
# criterio 2 del spec 7.4 (2 % en 60 ms) es inalcanzable: 60 ms son 3*tau y
# dejan ~5 %. Medido, acelerar el resonante no cuesta estabilidad -- el
# sobrepico se queda en 0,3 % para tau entre 6 y 20 ms -- asi que se corrige
# la sintonia en vez de aflojar el criterio.
TAU_RES = L / R                                           # 10 ms
KR_DEF = 2.0 * abs(complex(R, 2.0 * math.pi * 50.0 * L)) / TAU_RES   # 791,26


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

    Los tres productos se suman con los 48 bits fraccionarios completos y la
    reduccion a Q8.24 ocurre UNA sola vez al final: mult_a0/a1/b1 son
    sfixed(..downto -48) y el unico resize a Q8.24 esta en I_n.

    Ojo con el estilo de esa reduccion. RL_fase pasa `fixed_wrap,
    fixed_truncate` explicitos en los tres productos y en sum_inputs, pero el
    resize final (lineas 101 y 106) va SIN estilos, y los defaults de
    ieee.fixed_pkg son fixed_saturate y fixed_round. O sea: redondea al mas
    cercano y satura, no trunca y envuelve. Es justo el unico punto del filtro
    donde eso importa.

    Aun redondeando, el medio LSB que se pierde en b1*I[n-1] queda amplificado
    por 1/(1-b1) ~ 1e5, porque b1 = 0,99999: queda un error de ganancia DC
    sistematico de -0,36 %. Truncando seria el doble.
    """

    def __init__(self, r=R, l=L, t=T_CLK):
        self.a0, self.a1, self.b1 = coef_rl_q824(r, l, t)
        self.u_z1 = 0
        self.i_z1 = 0

    def paso(self, u):
        suma = self.a0 * u + self.a1 * self.u_z1 + self.b1 * self.i_z1
        # fixed_round: al mas cercano. fixed_saturate: clampea, no envuelve.
        i = Q8_24.saturar((suma + (1 << 23)) >> 24)
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


class Lazo(object):
    """Lazo cerrado completo, a Ts, con la planta ZOH en los dos ejes.

    El orden es el mismo que el de ControlLazo.vhd: la senal `sat` que ven
    los PR es la del Ts ANTERIOR, porque en el RTL sale registrada.
    """

    def __init__(self, f_o, amp, kp, kr, v_i):
        self.ref = RefGen(paso_nco(f_o), Q8_24.de_float(amp))
        k_i = k_q124(f_o)
        b_i = Q8_24.de_float(kr * TS, redondear=True)
        kp_i = Q8_24.de_float(kp, redondear=True)
        self.pr_a = PR2Int(k_i, b_i, kp_i)
        self.pr_b = PR2Int(k_i, b_i, kp_i)
        self.planta_a = PlantaRL_Ts()
        self.planta_b = PlantaRL_Ts()
        self.inv_vi = Q8_24.de_float(1.0 / v_i, redondear=True)
        self.q_max = Q1_24.de_float(math.sqrt(3.0) / 2.0, redondear=True)
        self.v_i = v_i
        self.freeze_activo = True
        self.sat_z1 = False

    def amp_nueva(self, amp):
        self.ref.amp = Q8_24.de_float(amp)

    def correr(self, n_ts):
        log = []
        for _ in range(n_ts):
            ref_a, ref_b = self.ref.paso()
            e_a = Q8_24.envolver(ref_a - Q8_24.de_float(self.planta_a.i))
            e_b = Q8_24.envolver(ref_b - Q8_24.de_float(self.planta_b.i))

            congelar = self.sat_z1 and self.freeze_activo
            v_a = self.pr_a.paso(e_a, congelar)
            v_b = self.pr_b.paso(e_b, congelar)

            mag, ang = cordic_vec(v_a, v_b)
            q, sat = normalizar(mag, self.inv_vi, self.q_max)
            self.sat_z1 = sat

            # El modulador reconstruye v_o = q*V_i*e^(j*al_o).
            q_pu = q / float(1 << Q_BITS)
            theta = 2.0 * math.pi * ang / 2048.0
            self.planta_a.paso(q_pu * self.v_i * math.cos(theta))
            self.planta_b.paso(q_pu * self.v_i * math.sin(theta))

            log.append({"ref_a": Q8_24.a_float(ref_a),
                        "ref_b": Q8_24.a_float(ref_b),
                        "i_a": self.planta_a.i,
                        "i_b": self.planta_b.i,
                        "v_a": Q8_24.a_float(v_a),
                        "v_b": Q8_24.a_float(v_b),
                        "q": q, "al_o": ang, "sat": sat})
        return log


# --- generacion del paquete de vectores para los TB ----------------------
N_VECTORES = 512


def _hex_vhdl(v, bits):
    """Literal hexadecimal VHDL de `bits` bits en complemento a dos.

    Se usa en vez de to_signed() porque el `integer` de VHDL-93 es de 32 bits
    y los estados x1/x2 son de 48: to_signed(3.5e12, 48) no compila.
    """
    assert bits % 4 == 0, "un literal hex necesita un ancho multiplo de 4"
    return 'x"%0*X"' % (bits // 4, v & ((1 << bits) - 1))


def _vectores_pr():
    """Estimulo y respuesta esperada de un eje del PR, a 50 Hz."""
    pr = PR2Int(k_q124(50.0),
                Q8_24.de_float(KR_DEF * TS, redondear=True),
                Q8_24.de_float(KP_DEF, redondear=True))
    filas = []
    for n in range(N_VECTORES):
        # Fundamental + una septima, para que el resonante tenga algo que
        # rechazar ademas de algo que seguir.
        e = Q8_24.de_float(0.3 * math.sin(2 * math.pi * 50.0 * n * TS)
                           + 0.05 * math.sin(2 * math.pi * 350.0 * n * TS))
        sat = 200 <= n < 260          # tramo forzado, para ejercitar el freeze
        u = pr.paso(e, sat)
        filas.append((e, 1 if sat else 0, u, pr.x1, pr.x2))
    return filas


def _emitir_paquete(ruta):
    filas = _vectores_pr()
    k = k_q124(50.0)
    b = Q8_24.de_float(KR_DEF * TS, redondear=True)
    kp = Q8_24.de_float(KP_DEF, redondear=True)

    with open(ruta, "w") as f:
        f.write("-- GENERADO POR SW/python/ModeloControlPR.py -- NO EDITAR A MANO\n")
        f.write("-- Regenerar con: python SW/python/ModeloControlPR.py vectores\n")
        f.write("--\n")
        f.write("-- Estimulo y respuesta esperada de un eje de PR_2int, sacados del\n")
        f.write("-- modelo de oro. El TB los replay ciclo a ciclo y compara bit a bit.\n")
        f.write("library ieee;\n")
        f.write("use ieee.std_logic_1164.all;\n")
        f.write("use ieee.numeric_std.all;\n\n")
        f.write("package vectores_pr_pkg is\n\n")
        f.write("    constant N_VEC : integer := %d;\n\n" % len(filas))
        f.write("    constant K_PR  : signed(24 downto 0) := to_signed(%d, 25);\n" % k)
        f.write("    constant B_PR  : signed(31 downto 0) := to_signed(%d, 32);\n" % b)
        f.write("    constant KP_PR : signed(31 downto 0) := to_signed(%d, 32);\n\n" % kp)

        for nombre, idx, ancho in (("E", 0, 32), ("U", 2, 32),
                                   ("X1", 3, 48), ("X2", 4, 48)):
            tipo = "t_vec%d" % ancho
            if nombre in ("E", "X1"):
                f.write("    type %s is array (0 to N_VEC-1) of signed(%d downto 0);\n"
                        % (tipo, ancho - 1))
            f.write("    constant VEC_%s : %s := (\n" % (nombre, tipo))
            f.write(",\n".join("        " + _hex_vhdl(fila[idx], ancho)
                               for fila in filas))
            f.write("\n    );\n\n")

        f.write("    type t_sat is array (0 to N_VEC-1) of std_logic;\n")
        f.write("    constant VEC_SAT : t_sat := (\n")
        f.write(",\n".join("        '%d'" % fila[1] for fila in filas))
        f.write("\n    );\n\n")
        f.write("end package vectores_pr_pkg;\n")


def main():
    import sys
    cmd = sys.argv[1] if len(sys.argv) > 1 else "params"
    if cmd == "params":
        a0, a1, b1 = coef_rl_q824(R, L, T_CLK)
        z = abs(complex(R, 2.0 * math.pi * 50.0 * L))
        print("R = %.4f ohm   L = %.6f H   tau = L/R = %.3f ms" % (R, L, 1e3 * L / R))
        print("|Z(2pi*50)| = %.4f ohm   i_max = q_max/|Z| = %.4f pu"
              % (z, (math.sqrt(3.0) / 2.0) / z))
        print("Ts = %.4f us   N_CLK_TS = %d" % (1e6 * TS, N_CLK_TS))
        print("")
        print("create_bd.tcl: Coef_a0 = Coef_a1 = %d   Coef_b1 = %d" % (a0, b1))
        print("k(50 Hz)   Q1.24 = %d = 0x%X" % (k_q124(50.0), k_q124(50.0)))
        print("paso_nco(50 Hz)  = %d = 0x%X" % (paso_nco(50.0), paso_nco(50.0)))
        print("Kp = %.4f    Q8.24 = %d" % (KP_DEF, Q8_24.de_float(KP_DEF, redondear=True)))
        print("Kr = %.4f   b = Kr*Ts  Q8.24 = %d"
              % (KR_DEF, Q8_24.de_float(KR_DEF * TS, redondear=True)))
        print("1/K_cordic Q8.24 = %d  (K = %.8f)" % (INV_K_Q824, K_CORDIC))
        print("q_max = sqrt(3)/2  Q8.24 = %d"
              % Q8_24.de_float(math.sqrt(3.0) / 2.0, redondear=True))
    elif cmd == "vectores":
        ruta = "../../HW/src/tb/vectores_pr_pkg.vhd"
        _emitir_paquete(ruta)
        print("escrito %s (%d vectores)" % (ruta, N_VECTORES))
    else:
        raise SystemExit("uso: ModeloControlPR.py [params|vectores]")


if __name__ == "__main__":
    main()
