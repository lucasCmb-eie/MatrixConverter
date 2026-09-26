"""Suite de verificacion del modelo de oro del lazo de corriente PR."""

import math
import unittest

import ModeloControlPR as m
from fixedpoint import Q, mul_trunc

Q8_24 = Q(8, 24)
Q8_40 = Q(8, 40)
Q1_24 = Q(1, 24)


class TestPuntoFijo(unittest.TestCase):

    def test_trunca_hacia_menos_infinito(self):
        # -1/3 en Q8.24 = -5592405.33 -> truncado hacia -inf = -5592406.
        # Asi trunca fixed_truncate y asi trunca el shift aritmetico de numeric_std.
        self.assertEqual(Q8_24.de_float(-1.0 / 3.0), -5592406)
        self.assertEqual(Q8_24.de_float(1.0 / 3.0), 5592405)

    def test_redondeo_para_constantes(self):
        # Los coeficientes que calcula el PS se redondean al mas cercano.
        self.assertEqual(Q8_24.de_float(-1.0 / 3.0, redondear=True), -5592405)

    def test_rangos(self):
        self.assertEqual(Q8_24.bits, 32)
        self.assertEqual(Q8_24.hi, 2**31 - 1)
        self.assertEqual(Q8_24.lo, -(2**31))
        self.assertEqual(Q8_40.bits, 48)
        self.assertEqual(Q1_24.bits, 25)

    def test_envolver_complemento_a_dos(self):
        self.assertEqual(Q8_24.envolver(2**31), -(2**31))
        self.assertEqual(Q8_24.envolver(-(2**31) - 1), 2**31 - 1)
        self.assertEqual(Q8_24.envolver(5), 5)

    def test_saturar(self):
        self.assertEqual(Q8_24.saturar(2**40), 2**31 - 1)
        self.assertEqual(Q8_24.saturar(-(2**40)), -(2**31))

    def test_mul_trunc_reescala(self):
        # k (Q1.24) * x2 (Q8.40) = Q9.64, reescalado a Q8.40 -> shift de 24.
        k = Q1_24.de_float(0.0643287205, redondear=True)
        x2 = Q8_40.de_float(2.0)
        self.assertEqual(mul_trunc(k, x2, 24, 40, 40), (k * x2) >> 24)

    def test_mul_trunc_negativo_trunca_hacia_menos_infinito(self):
        self.assertEqual(mul_trunc(-1, 1, 0, 0, -4), -1)


class TestParametros(unittest.TestCase):

    def test_ts_y_ciclos(self):
        self.assertAlmostEqual(m.TS, 204.8e-6, places=12)
        self.assertEqual(m.N_CLK_TS, 2048)

    def test_paso_nco_50hz_coincide_con_el_default_del_bd(self):
        # C_DOUT_DEFAULT_2 del block design es 0x53E3.
        self.assertEqual(m.paso_nco(50.0), 0x53E3)

    def test_k_50hz_coincide_con_el_default_del_spec(self):
        self.assertEqual(m.k_q124(50.0), 0x1077D9)
        self.assertEqual(m.k_q124(50.0), 1079257)

    def test_prewarping_da_la_frecuencia_exacta(self):
        # La frecuencia que realiza el resonador es (2/Ts)*asin(k/2).
        # Con k = 2*sin(w*Ts/2) tiene que volver exactamente a w.
        for f in (10.0, 50.0, 60.0, 400.0):
            k = m.k_resonante(f)
            w_realizada = (2.0 / m.TS) * math.asin(k / 2.0)
            self.assertAlmostEqual(w_realizada, 2 * math.pi * f, places=6)

    def test_k_fuera_de_rango_es_error_explicito(self):
        # Review Focus 3: k = 2*sin(pi*f*Ts) llega a 1 en f = 1/(6*Ts).
        f_max = 1.0 / (6.0 * m.TS)
        self.assertAlmostEqual(f_max, 813.802, places=2)
        with self.assertRaises(ValueError):
            m.k_q124(f_max + 1.0)

    def test_coef_rl_del_bd_estan_mal_por_100x(self):
        # Lo que create_bd.tcl deberia tener para R=1,2 y L=12 mH a 10 MHz.
        # Lo que tenia era a0=a1=6989, que implica R=12 mOhm y L=120 uH.
        a0, a1, b1 = m.coef_rl_q824(m.R, m.L, m.T_CLK)
        self.assertEqual(a0, 70)
        self.assertEqual(a1, 70)
        self.assertEqual(b1, 16777048)


class TestPlanta(unittest.TestCase):

    def test_ganancia_dc_analitica(self):
        a0, a1, b1 = m.coef_rl(m.R, m.L, m.T_CLK)
        self.assertAlmostEqual((a0 + a1) / (1.0 - b1), 1.0 / m.R, places=4)

    def test_modelo_a_ts_alcanza_la_ganancia_dc(self):
        # 500 Ts = 102 ms = 10 tau, suficiente para que places=3 tenga sentido.
        p = m.PlantaRL_Ts()
        for _ in range(500):
            i = p.paso(1.0)
        self.assertAlmostEqual(i, 1.0 / m.R, places=3)

    def test_el_modelo_de_10mhz_tiene_el_sesgo_de_truncamiento_de_rl_fase(self):
        # RL_fase trunca el producto b1*I[n-1], y como b1 = 0,99999 ese error
        # de medio LSB queda amplificado por 1/(1-b1) ~ 1e5. Da un error de
        # ganancia DC sistematico y NEGATIVO de ~0,7 %, que no es un defecto
        # del modelo sino una propiedad del RTL tal como esta hoy.
        #
        # El PR lo absorbe, porque tiene ganancia enorme en w_o, pero hay que
        # tenerlo anotado: la planta que ve el control no es la analitica.
        p = m.PlantaRL_Clk()
        u = Q8_24.de_float(1.0)
        for _ in range(500 * m.N_CLK_TS):
            i_q = p.paso(u)
        i_clk = Q8_24.a_float(i_q)
        ideal = 1.0 / m.R
        error = (ideal - i_clk) / ideal
        self.assertLess(i_clk, ideal, "el sesgo de truncamiento es negativo")
        self.assertGreater(error, 0.005, "medido 0,71 %; si bajo, cambio el RTL")
        self.assertLess(error, 0.010, "medido 0,71 %; si subio, cambio el RTL")


if __name__ == "__main__":
    unittest.main()
