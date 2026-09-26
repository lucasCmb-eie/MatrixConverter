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


class TestPR(unittest.TestCase):

    def _pr(self, f_o=50.0, kp=m.KP_DEF, kr=m.KR_DEF):
        return m.PR2Int(k_i=m.k_q124(f_o),
                        b_i=Q8_24.de_float(kr * m.TS, redondear=True),
                        kp_i=Q8_24.de_float(kp, redondear=True))

    def test_determinante_de_la_transicion_es_uno(self):
        # La propiedad que mantiene los polos sobre el circulo unidad para
        # cualquier k, incluso mal cuantizado (spec 5.1). 800 Hz esta cerca
        # del maximo de 813,8 que admite Q1.24.
        for f in (10.0, 50.0, 400.0, 800.0):
            k = Q1_24.a_float(m.k_q124(f))
            (a, b), (c, d) = m.matriz_transicion(k)
            self.assertAlmostEqual(a * d - b * c, 1.0, places=12)

    def test_kr_sale_de_la_impedancia_no_de_la_inductancia(self):
        # El polo resonante de lazo cerrado se corre delta = Kr/(2*|R+jw_o*L|),
        # asi que Kr = 2*|Z(w_o)|/tau, en ohm/s. La formula del spec 5.5 decia
        # 2*L/tau, que tiene unidades de ohm y da 1,2 en vez de 395,6.
        z = abs(complex(m.R, 2 * math.pi * 50.0 * m.L))
        self.assertAlmostEqual(z, 3.9563, places=4)
        self.assertAlmostEqual(m.KR_DEF, 2.0 * z / 20e-3, places=3)
        self.assertEqual(Q8_24.de_float(m.KR_DEF * m.TS, redondear=True), 1359371)

    def test_sigue_la_referencia_en_amplitud_y_fase(self):
        # Criterio 1 del spec 7.4, en la version que es alcanzable: el lazo
        # tiene 1 Ts de retardo de transporte por construccion (spec 4), que
        # a 50 Hz son 3,686 grados. Lo exigible es amplitud < 1 % y fase POR
        # ENCIMA de ese retardo conocido < 1 grado.
        pr = self._pr()
        planta = m.PlantaRL_Ts()
        w = 2 * math.pi * 50.0
        amp = 0.5
        n_total, n_medir = 6000, 2000
        cos_a = sen_a = 0.0
        for n in range(n_total):
            ref = amp * math.sin(w * n * m.TS)
            e = Q8_24.de_float(ref - planta.i)
            u = pr.paso(e, sat=False)
            planta.paso(Q8_24.a_float(u))
            if n >= n_total - n_medir:            # ya en regimen
                th = w * n * m.TS
                cos_a += planta.i * math.cos(th)
                sen_a += planta.i * math.sin(th)
        cos_a *= 2.0 / n_medir
        sen_a *= 2.0 / n_medir

        amplitud = math.hypot(cos_a, sen_a)
        fase = math.degrees(math.atan2(cos_a, sen_a))
        retardo_1ts = math.degrees(w * m.TS)

        self.assertAlmostEqual(retardo_1ts, 3.686, places=3)
        self.assertLess(abs(amplitud - amp) / amp, 0.01, "amplitud")
        self.assertLess(abs(fase - retardo_1ts), 1.0, "fase mas alla del 1 Ts")

    def test_el_resonante_ideal_no_amortigua(self):
        # Review Focus 1: el resonante ideal no tiene amortiguamiento, asi
        # que cualquier basura inicial se mantiene para siempre. El reset del
        # RTL tiene que dejar x1/x2 exactamente en cero por eso.
        pr = self._pr()
        pr.x1 = Q8_40.de_float(0.01)
        pr.x2 = 0
        for _ in range(20000):                    # 4 s: mucho mas que cualquier tau
            pr.paso(0, sat=False)
        self.assertGreater(abs(Q8_40.a_float(pr.x1)) + abs(Q8_40.a_float(pr.x2)),
                           1e-4,
                           "el resonante ideal NO debe amortiguar; si amortigua, "
                           "det(A) != 1 y la discretizacion esta mal")

    def test_freeze_detiene_la_acumulacion_pero_no_la_rotacion(self):
        # spec 5.4: sat congela la entrada, no el estado.
        pr = self._pr()
        pr.x1 = Q8_40.de_float(0.5)
        pr.x2 = Q8_40.de_float(0.5)
        antes = (pr.x1, pr.x2)
        pr.paso(Q8_24.de_float(1.0), sat=True)
        self.assertNotEqual((pr.x1, pr.x2), antes, "x2 tiene que seguir rotando")

        # Con la entrada congelada el estado solo rota, y lo que la rotacion
        # conserva NO es el modulo euclideo: la matriz del magic circle no es
        # ortogonal (A^T A tiene 1+k^2 en la diagonal). El invariante es
        # x1^2 + x2^2 - k*x1*x2, y ese si se conserva exacto.
        k = Q1_24.a_float(m.k_q124(50.0))

        def invariante(x1, x2):
            a, b = Q8_40.a_float(x1), Q8_40.a_float(x2)
            return a * a + b * b - k * a * b

        self.assertAlmostEqual(invariante(*antes),
                               invariante(pr.x1, pr.x2), places=9)

    def test_error_maximo_no_desborda_los_estados(self):
        # Review Focus 5: e en el extremo de Q8.24 durante muchos Ts.
        pr = self._pr()
        e_max = Q8_24.hi
        for _ in range(500):
            pr.paso(e_max, sat=False)
            self.assertGreaterEqual(pr.x1, Q8_40.lo)
            self.assertLessEqual(pr.x1, Q8_40.hi)
            self.assertGreaterEqual(pr.x2, Q8_40.lo)
            self.assertLessEqual(pr.x2, Q8_40.hi)


if __name__ == "__main__":
    unittest.main()
