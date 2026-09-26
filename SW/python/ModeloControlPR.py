"""Modelo de oro del lazo de corriente PR del conversor matricial.

Replica bit a bit la aritmetica del RTL para poder (a) cerrar la sintonia
antes de escribir VHDL y (b) servir de oraculo contra el que se comparan los
bloques del RTL.

Referencia: docs/superpowers/specs/2026-09-17-control-corriente-salida-design.md
"""

import math

from fixedpoint import Q

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
