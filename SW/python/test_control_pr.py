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

    def test_el_modelo_de_10mhz_tiene_el_sesgo_de_redondeo_de_rl_fase(self):
        # El resize final de RL_fase (lineas 101 y 106) va SIN estilos, asi
        # que usa los defaults de ieee.fixed_pkg: fixed_round y
        # fixed_saturate, no truncate/wrap como los otros tres resize del
        # archivo. Aun redondeando, el medio LSB que se pierde en b1*I[n-1]
        # queda amplificado por 1/(1-b1) ~ 1e5 (b1 = 0,99999) y deja un error
        # de ganancia DC sistematico y NEGATIVO de 0,357 %. Truncando seria
        # el doble, 0,714 %: ese valor es el que tendria si alguien le pusiera
        # `fixed_truncate` explicito al resize final.
        #
        # No es un defecto del modelo, es una propiedad del RTL. El PR lo
        # absorbe porque tiene ganancia enorme en w_o, pero conviene tenerlo
        # anotado: la planta que ve el control no es la analitica.
        p = m.PlantaRL_Clk()
        u = Q8_24.de_float(1.0)
        for _ in range(500 * m.N_CLK_TS):
            i_q = p.paso(u)
        i_clk = Q8_24.a_float(i_q)
        ideal = 1.0 / m.R
        error = (ideal - i_clk) / ideal
        self.assertLess(i_clk, ideal, "el sesgo es negativo")
        self.assertGreater(error, 0.003, "medido 0,357 %; si bajo, cambio el RTL")
        self.assertLess(error, 0.005, "medido 0,357 %; si subio a ~0,71 %, "
                                      "alguien le puso fixed_truncate al resize")


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
        self.assertAlmostEqual(m.KR_DEF, 2.0 * z / m.TAU_RES, places=3)
        # tau_res = L/R = 10 ms, la constante de tiempo propia de la carga.
        self.assertAlmostEqual(m.TAU_RES, 10e-3, places=6)
        self.assertEqual(Q8_24.de_float(m.KR_DEF * m.TS, redondear=True), 2718742)

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

    def _estado_ideal(self, e, n, f_o=50.0):
        """La misma recurrencia que PR2Int pero SIN envolver, para poder ver
        si el estado real se salio de Q8.40. Asertar sobre pr.x1 directamente
        no sirve: `paso` aplica envolver() y los limites se cumplen siempre."""
        k = m.k_q124(f_o)
        b = Q8_24.de_float(m.KR_DEF * m.TS, redondear=True)
        x1 = x2 = 0
        pico = 0
        for _ in range(n):
            x1 = x1 - ((k * x2) >> 24) + ((b * e) >> 8)
            x2 = x2 + ((k * x1) >> 24)
            pico = max(pico, abs(x1), abs(x2))
        return x1, x2, pico

    def test_headroom_de_los_estados_en_el_rango_de_operacion(self):
        # Review Focus 5 y 2, medidos de verdad. El error fisicamente
        # alcanzable es |ref|max + |i|max ~ 0,26 pu; probamos hasta 1,0, que
        # es casi 4x eso. El pico del estado crece 5,04 por pu de error.
        for e_pu in (0.1, 0.25, 0.5, 1.0):
            e = Q8_24.de_float(e_pu)
            x1_id, x2_id, pico = self._estado_ideal(e, 2000)
            self.assertLess(Q8_40.a_float(pico), 0.5 * Q8_40.a_float(Q8_40.hi),
                            "sin 2x de margen en Q8.40 para |e| = %.2f" % e_pu)
            # Y el modelo real tiene que coincidir con el ideal: si difiere,
            # es que envolvio.
            pr = self._pr()
            for _ in range(2000):
                pr.paso(e, sat=False)
            self.assertEqual((pr.x1, pr.x2), (x1_id, x2_id),
                             "el estado envolvio con |e| = %.2f pu" % e_pu)

    def test_el_estado_envuelve_fuera_del_rango_fisico(self):
        # El limite conocido, fijado a proposito: con e en el extremo de
        # Q8.24 (128 pu, unas 500 veces lo fisicamente alcanzable) el estado
        # SI se sale de Q8.40 y envuelve en silencio. Se acepta porque ese
        # error no puede existir; el test esta para que si alguien achica el
        # ancho del estado o sube Kr, el margen real quede a la vista.
        _, _, pico = self._estado_ideal(Q8_24.hi, 500)
        self.assertGreater(Q8_40.a_float(pico), Q8_40.a_float(Q8_40.hi))


class TestRefGen(unittest.TestCase):

    def test_amplitud_y_cuadratura(self):
        ref = m.RefGen(m.paso_nco(50.0), Q8_24.de_float(0.5))
        pico_a = 0.0
        muestras = []
        for _ in range(int(round(1.0 / 50.0 / m.TS))):    # un periodo
            a, b = ref.paso()
            muestras.append((Q8_24.a_float(a), Q8_24.a_float(b)))
            pico_a = max(pico_a, abs(Q8_24.a_float(a)))
        self.assertAlmostEqual(pico_a, 0.5, places=2)
        # alfa y beta en cuadratura: alfa^2 + beta^2 constante.
        radios = [math.hypot(a, b) for a, b in muestras]
        self.assertAlmostEqual(max(radios), min(radios), places=2)


class TestCordic(unittest.TestCase):

    def test_modulo_y_angulo(self):
        for x, y, mag, ang_deg in ((1.0, 0.0, 1.0, 0.0),
                                   (0.0, 2.0, 2.0, 90.0),
                                   (-1.0, -1.0, math.sqrt(2.0), 225.0)):
            mg, an = m.cordic_vec(Q8_24.de_float(x), Q8_24.de_float(y))
            self.assertAlmostEqual(Q8_24.a_float(mg), mag, places=3)
            self.assertAlmostEqual(an * 360.0 / 2048.0, ang_deg, places=0)

    def test_entrada_cero(self):
        # Review Focus 4: (0,0) da modulo 0; el angulo es irrelevante pero
        # tiene que ser un valor definido, no una excepcion.
        mg, an = m.cordic_vec(0, 0)
        self.assertEqual(mg, 0)
        self.assertIsInstance(an, int)
        self.assertTrue(0 <= an < 2048)

    def test_normalizar_satura_y_avisa(self):
        inv_vi = Q8_24.de_float(1.0)
        q_max = Q1_24.de_float(0.866)
        q, sat = m.normalizar(Q8_24.de_float(0.5), inv_vi, q_max)
        self.assertFalse(sat)
        self.assertAlmostEqual(q / 512.0, 0.5, places=2)
        q, sat = m.normalizar(Q8_24.de_float(1.5), inv_vi, q_max)
        self.assertTrue(sat)
        self.assertAlmostEqual(q / 512.0, 0.866, places=2)

    def test_normalizar_entrada_cero_da_q_cero(self):
        q, sat = m.normalizar(0, Q8_24.de_float(1.0), Q1_24.de_float(0.866))
        self.assertEqual(q, 0)
        self.assertFalse(sat)


class TestLazo(unittest.TestCase):

    # Con V_i = 1 p.u. y |Z(w_o)| = 3,956 ohm, la corriente maxima que el
    # conversor puede entregar es q_max/|Z| = 0,866/3,956 = 0,219 p.u.
    # Todas las amplitudes de prueba tienen que quedar por debajo.
    I_MAX = 0.219

    def _lazo(self, amp=0.10, f_o=50.0):
        return m.Lazo(f_o=f_o, amp=amp, kp=m.KP_DEF, kr=m.KR_DEF, v_i=1.0)

    def test_regimen_sigue_la_referencia(self):
        # Criterio 1 del spec 7.4, en amplitud del fundamental.
        log = self._lazo().correr(3000)
        cola = log[2000:]
        pico_ref = max(abs(r["ref_a"]) for r in cola)
        pico_med = max(abs(r["i_a"]) for r in cola)
        self.assertLess(abs(pico_med - pico_ref) / pico_ref, 0.01)

    def test_escalon_de_amplitud_se_establece(self):
        # Criterio 2: sobrepico < 20 %, establecimiento al 2 % en < 60 ms.
        lazo = self._lazo(amp=0.05)
        lazo.correr(1500)
        lazo.amp_nueva(0.15)
        log = lazo.correr(int(round(60e-3 / m.TS)))
        pico = max(abs(r["i_a"]) for r in log)
        self.assertLess(pico / 0.15, 1.20, "sobrepico")
        cola = log[-100:]
        pico_final = max(abs(r["i_a"]) for r in cola)
        self.assertLess(abs(pico_final - 0.15) / 0.15, 0.02, "establecimiento")

    def test_sobrecomando_satura_y_avisa(self):
        lazo = self._lazo(amp=3.0)
        log = lazo.correr(600)
        self.assertTrue(any(r["sat"] for r in log))

    def test_el_freeze_reduce_el_sobrepico_al_desaturar(self):
        # Criterio 4 del spec 7.4, en version diferencial: el anti-windup
        # tiene que HACER algo, no solo estar presente.
        def prueba(freeze):
            lazo = self._lazo(amp=0.10)
            lazo.freeze_activo = freeze
            lazo.correr(600)
            lazo.amp_nueva(3.0)              # por encima de q_max
            lazo.correr(300)
            lazo.amp_nueva(0.10)
            log = lazo.correr(600)
            # Los estados no tienen que haber envuelto: si envuelven, la
            # comparacion mide basura y no windup.
            sin_wrap = all(abs(x) < Q8_40.hi * 0.9
                           for x in (lazo.pr_a.x1, lazo.pr_a.x2))
            return max(abs(r["i_a"]) for r in log), sin_wrap

        pico_freeze, ok_freeze = prueba(True)
        pico_libre, ok_libre = prueba(False)
        self.assertTrue(ok_freeze, "con freeze los estados envolvieron")
        self.assertTrue(ok_libre, "sin freeze los estados envolvieron")
        self.assertLess(pico_freeze, pico_libre,
                        "el freeze no esta reduciendo el windup")


if __name__ == "__main__":
    unittest.main()
