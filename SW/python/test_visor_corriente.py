#!/usr/bin/env python3
"""Tests del visor de corriente.

    python SW/python/test_visor_corriente.py

Prueban todo lo que no necesita la placa: el formato de trama y el parser (que
tiene que resincronizarse si el script se engancha a mitad de una trama), los
comandos, las metricas, la placa simulada y la figura en modo --png.

Lo que NO prueban: visor_corriente.c. Su aritmetica de set points se replica
aca (espejo_*) y el propio PS la autoverifica al arrancar contra los valores
ya validados en la placa; el resto se ve recien con la placa.
"""

import math
import os
import struct
import tempfile
import unittest

import visor_trama as VT

Q24 = 1 << 24


def q824(x):
    return int(round(x * Q24))


def trama_senoidal(contador=7, amp=0.06, f=50.0, fase=0.0, **extra):
    """Una trama con la corriente igual a la referencia, senoidal pura."""
    w = 2 * math.pi * f / (10e6 / 2048)
    ia, ib = [], []
    for n in range(VT.N_MUESTRAS):
        ia.append(q824(amp * math.cos(w * n + fase)))
        ib.append(q824(amp * math.sin(w * n + fase)))
    campos = dict(contador=contador, amp_ref=q824(amp), f_mhz=int(round(f * 1000)),
                  flags=0, muestra_escalon=0, amp_ref_prev=q824(amp),
                  f_mhz_prev=int(round(f * 1000)), clamp=0,
                  i_alfa=ia, i_beta=ib, ref_alfa=list(ia), ref_beta=list(ib))
    campos.update(extra)
    return VT.Trama(**campos)


class TestFormato(unittest.TestCase):

    def test_tamano(self):
        self.assertEqual(len(VT.codificar(trama_senoidal())), VT.BYTES_TRAMA)
        self.assertEqual(VT.BYTES_TRAMA, 8236)

    def test_sincronismo_little_endian(self):
        self.assertEqual(VT.codificar(trama_senoidal())[:4], bytes([0xA5, 0x5A, 0x5A, 0xA5]))

    def test_ida_y_vuelta(self):
        t = trama_senoidal(amp=0.08, f=40.0)
        tramas, texto = VT.Parser().alimentar(VT.codificar(t))
        self.assertEqual(tramas, [t])
        self.assertEqual(texto, [])

    def test_valores_negativos_conservan_el_signo(self):
        t = trama_senoidal()
        self.assertTrue(min(t.i_alfa) < 0)
        (r,), _ = VT.Parser().alimentar(VT.codificar(t))
        self.assertEqual(r.i_alfa, t.i_alfa)


class TestParser(unittest.TestCase):

    def test_checksum_malo_se_descarta(self):
        b = bytearray(VT.codificar(trama_senoidal()))
        b[100] ^= 0x01
        tramas, _ = VT.Parser().alimentar(bytes(b))
        self.assertEqual(tramas, [])

    def test_basura_antes_del_sincronismo(self):
        t = trama_senoidal()
        tramas, _ = VT.Parser().alimentar(b"\x00\x13basura\xA5\x5A" + VT.codificar(t))
        self.assertEqual(tramas, [t])

    def test_engancharse_a_mitad_de_trama(self):
        t1, t2 = trama_senoidal(contador=1), trama_senoidal(contador=2)
        flujo = VT.codificar(t1)[3000:] + VT.codificar(t2)
        tramas, _ = VT.Parser().alimentar(flujo)
        self.assertEqual([x.contador for x in tramas], [2])

    def test_trama_cortada_en_pedazos(self):
        t = trama_senoidal()
        b = VT.codificar(t)
        p = VT.Parser()
        juntas = []
        for i in range(0, len(b), 333):
            tr, _ = p.alimentar(b[i:i + 333])
            juntas += tr
        self.assertEqual(juntas, [t])

    def test_n_invalido_resincroniza(self):
        b = bytearray(VT.codificar(trama_senoidal(contador=1)))
        struct.pack_into("<I", b, 4 * 9, 999)
        t2 = trama_senoidal(contador=2)
        tramas, _ = VT.Parser().alimentar(bytes(b) + VT.codificar(t2))
        self.assertEqual([x.contador for x in tramas], [2])

    def test_dos_tramas_pegadas(self):
        b = VT.codificar(trama_senoidal(contador=1)) + VT.codificar(trama_senoidal(contador=2))
        tramas, _ = VT.Parser().alimentar(b)
        self.assertEqual([x.contador for x in tramas], [1, 2])

    def test_lineas_de_texto_del_ps(self):
        p = VT.Parser()
        tramas, texto = p.alimentar(b"# ---- visor ----\r\n# ERROR: x\r\nruido\n"
                                    + VT.codificar(trama_senoidal()))
        self.assertEqual(len(tramas), 1)
        self.assertEqual(texto, ["# ---- visor ----", "# ERROR: x"])

    def test_texto_partido_entre_lecturas(self):
        p = VT.Parser()
        _, t1 = p.alimentar(b"# hol")
        _, t2 = p.alimentar(b"a\r\n")
        self.assertEqual(t1 + t2, ["# hola"])


class TestComandos(unittest.TestCase):

    def test_parsear_micro(self):
        self.assertEqual(VT.parsear_micro("0.08"), 80000)
        self.assertEqual(VT.parsear_micro("40"), 40000000)
        self.assertEqual(VT.parsear_micro("  12.5 \r"), 12500000)
        self.assertEqual(VT.parsear_micro("0.000001"), 1)
        for malo in ["", ".", "1.", "-1", "1e3", "1234", "0.1234567", "1,5", "abc"]:
            self.assertIsNone(VT.parsear_micro(malo), malo)

    def test_interpretar_comando(self):
        self.assertEqual(VT.interpretar_comando("A 0.080000"), ("A", 80000))
        self.assertEqual(VT.interpretar_comando("F 40.000000\r"), ("F", 40000000))
        self.assertEqual(VT.interpretar_comando("A 0.11"), ("A", 110000))
        self.assertEqual(VT.interpretar_comando("F 5"), ("F", 5000000))
        for malo in ["A 0.110001", "F 4.999", "F 100.5", "X 1", "A0.1", "A", ""]:
            self.assertIsNone(VT.interpretar_comando(malo), malo)

    def test_comandos_de_la_pc(self):
        self.assertEqual(VT.comando_amp(0.08), b"A 0.080000\n")
        self.assertEqual(VT.comando_frec(40), b"F 40.000000\n")
        for malo in [-0.01, 0.12, float("nan")]:
            with self.assertRaises(ValueError):
                VT.comando_amp(malo)
        for malo in [4.9, 101, float("nan")]:
            with self.assertRaises(ValueError):
                VT.comando_frec(malo)

    def test_lo_que_manda_la_pc_lo_acepta_la_placa(self):
        for x in [0.0, 0.06, 0.11]:
            self.assertIsNotNone(VT.interpretar_comando(VT.comando_amp(x).decode().strip()))
        for f in [5, 50, 100]:
            self.assertIsNotNone(VT.interpretar_comando(VT.comando_frec(f).decode().strip()))

    def test_coma_decimal(self):
        self.assertEqual(VT.numero_de_texto("0,08"), 0.08)
        self.assertEqual(VT.numero_de_texto(" 40 "), 40.0)
        with self.assertRaises(ValueError):
            VT.numero_de_texto("cuarenta")


import numpy as np
import visor_metricas as VM


class TestMetricas(unittest.TestCase):

    def test_clarke_inversa_da_tres_fases_a_120(self):
        n = np.arange(512)
        w = 2 * np.pi * 50 / VM.FS
        u, v, w_ = VM.clarke_inversa(0.06 * np.cos(w * n), 0.06 * np.sin(w * n))
        for fase, desfase in [(u, 0), (v, -2 * np.pi / 3), (w_, 2 * np.pi / 3)]:
            np.testing.assert_allclose(fase, 0.06 * np.cos(w * n + desfase), atol=1e-12)

    def test_senoidal_pura(self):
        m = VM.metricas(trama_senoidal(amp=0.06, f=50.0))
        self.assertTrue(m.valida)
        self.assertAlmostEqual(m.amp, 0.06, delta=1e-6)
        self.assertAlmostEqual(m.freq, 50.0, delta=0.01)
        self.assertAlmostEqual(m.err_pct, 0.0, delta=0.01)

    def test_frecuencia_sin_ciclos_enteros(self):
        m = VM.metricas(trama_senoidal(amp=0.05, f=37.3, fase=1.0))
        self.assertAlmostEqual(m.freq, 37.3, delta=0.01)

    def test_error_relativo(self):
        t = trama_senoidal(amp=0.066)
        t.amp_ref = q824(0.06)
        self.assertAlmostEqual(VM.metricas(t).err_pct, 10.0, delta=0.01)

    def test_escalon_mide_solo_despues_del_establecimiento(self):
        # antes del escalon 0,03 pu; despues 0,09. Si mirara toda la trama
        # daria un promedio de las dos.
        t = trama_senoidal(amp=0.09, flags=VT.FL_ESCALON, muestra_escalon=64,
                           amp_ref_prev=q824(0.03))
        for n in range(64):
            t.i_alfa[n] //= 3
            t.i_beta[n] //= 3
        m = VM.metricas(t)
        self.assertTrue(m.valida)
        self.assertAlmostEqual(m.amp, 0.09, delta=1e-6)

    def test_escalon_a_5hz_no_alcanza_un_ciclo(self):
        t = trama_senoidal(amp=0.06, f=5.0, flags=VT.FL_ESCALON, muestra_escalon=64)
        self.assertFalse(VM.metricas(t).valida)

    def test_5hz_sin_escalon_mide_igual(self):
        # 105 ms son medio ciclo a 5 Hz, pero la pendiente de fase no necesita
        # ciclos enteros: solo una ventana sin escalon.
        t = trama_senoidal(amp=0.06, f=5.0)
        # la regla de "un ciclo" aplica solo con escalon; sin escalon se mide
        m = VM.metricas(t)
        self.assertAlmostEqual(m.freq, 5.0, delta=0.01)

    def test_referencia_nula(self):
        t = trama_senoidal(amp=0.0)
        m = VM.metricas(t)
        self.assertTrue(math.isnan(m.freq))
        self.assertIsNone(m.err_pct)
        texto, alarma = VM.texto_titulo(t, m, 0)
        self.assertIn("ref 0", texto)
        self.assertNotIn("nan", texto.lower())
        self.assertFalse(alarma)

    def test_titulo_alarma(self):
        t = trama_senoidal(clamp=0x4)
        self.assertTrue(VM.texto_titulo(t, VM.metricas(t), 0)[1])
        t = trama_senoidal(flags=VT.FL_RECHAZO)
        texto, alarma = VM.texto_titulo(t, VM.metricas(t), 0)
        self.assertTrue(alarma)
        self.assertIn("rechaz", texto)

    def test_tramas_perdidas(self):
        self.assertEqual(VM.tramas_perdidas(None, 5), 0)
        self.assertEqual(VM.tramas_perdidas(5, 6), 0)
        self.assertEqual(VM.tramas_perdidas(5, 8), 2)
        # placa reseteada: el contador vuelve a empezar, no son 2^32 perdidas
        self.assertEqual(VM.tramas_perdidas(500, 0), 0)


class TestEspejoSetPoints(unittest.TestCase):
    """La aritmetica de visor_corriente.c, replicada operacion por operacion."""

    def test_valores_validados_en_la_placa(self):
        self.assertEqual(VM.espejo_amp_q824(60000), 1006633)     # V_AMP_06
        self.assertEqual(VM.espejo_paso_ref(50000), 43980800)
        self.assertEqual(VM.espejo_k(50000), 1079257)
        self.assertEqual(VM.espejo_paso_ref(55000), 48377856)
        self.assertEqual(VM.espejo_k(55000), 1187140)

    def test_taylor_igual_a_sin_en_todo_el_rango(self):
        ts = 2048 / 10e6
        for f_mhz in range(5000, 100001, 7):
            exacto = math.floor(2 * math.sin(math.pi * f_mhz / 1000 * ts) * Q24 + 0.5)
            self.assertEqual(VM.espejo_k(f_mhz), exacto, f_mhz)

if __name__ == "__main__":
    unittest.main()
