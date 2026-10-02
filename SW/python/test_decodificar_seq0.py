#!/usr/bin/env python3
"""Tests de DecodificarSeq0.py.

    python SW/python/test_decodificar_seq0.py

Este script es el que va a decidir si se destraba el merge del arreglo de seq0,
asi que no puede ir sin verificar. Los tests generan capturas SINTETICAS que
pasan por el mismo camino que las reales -- palabra de 9 bits, Q8.24 crudo,
Clark, atan2, media circular -- y comprueban que el veredicto sea el correcto en
los dos sentidos.

Lo que NO prueban: que el encoding de la palabra coincida con el RTL. Eso se
leyo de matrixConmut.vhd:72-74 y se replica en desarmar_matriz(); si el RTL
cambiara, estos tests seguirian pasando contra la convencion vieja.
"""

import math
import os
import subprocess
import sys
import tempfile
import unittest

import DecodificarSeq0 as D

Q24 = 1 << 24
PASOS = 2048
AQUI = os.path.dirname(os.path.abspath(__file__))


def q824(x):
    """float -> la palabra cruda de 32 bits, como la vuelca el PS."""
    v = int(round(x * Q24))
    return v & 0xFFFFFFFF


def estados_validos():
    """Las 27 palabras one-hot por fila."""
    out = []
    for su in range(3):
        for sv in range(3):
            for sw in range(3):
                pal = ((1 << (2 - su)) << 6) | ((1 << (2 - sv)) << 3) | (1 << (2 - sw))
                out.append((pal, (su, sv, sw)))
    return out


ESTADOS = estados_validos()


def angulo_de(pal, vi):
    m = D.desarmar_matriz(pal)
    vo = [sum(m[s][e] * vi[e] for e in range(3)) for s in range(3)]
    al, be = D.clarke(*vo)
    if abs(al) < 1e-12 and abs(be) < 1e-12:
        return None
    return math.atan2(be, al)


def generar(ruta, invertido, n=200, amp_in=0.5178):
    """Escribe un CSV sintetico con n fotos.

    Para cada foto elige el estado de conmutacion cuyo vector de salida cae mas
    cerca del objetivo (al_o, o al_o+180 si invertido). Eso imita lo que hace el
    modulador: aplicar vectores activos agrupados alrededor del comandado.
    """
    lineas = ["# sintetico", "n," + ",".join("d%d" % i for i in range(20))]
    for k in range(n):
        th_in = 2.0 * math.pi * k / 97.0          # angulo de entrada
        vi = [amp_in * math.cos(th_in - 2.0 * math.pi * j / 3.0) for j in range(3)]
        al_o_pasos = int(round(PASOS * (k / 98.0))) % PASOS
        al_o = al_o_pasos * 2.0 * math.pi / PASOS
        obj = al_o + (math.pi if invertido else 0.0)

        mejor, mejor_d = None, 9e9
        for pal, _ in ESTADOS:
            a = angulo_de(pal, vi)
            if a is None:
                continue
            d = abs(((a - obj + math.pi) % (2.0 * math.pi)) - math.pi)
            if d < mejor_d:
                mejor, mejor_d = pal, d
        if mejor is None:
            continue

        f = [0] * 20
        f[0], f[1], f[2] = (q824(v) for v in vi)
        f[12] = mejor
        f[18] = (al_o_pasos & 0x7FF) << 9        # q=0, sat=0; solo importa al_o
        lineas.append("%d," % k + ",".join("%x" % x for x in f))
    lineas.append("# fin")
    with open(ruta, "w") as fh:
        fh.write("\n".join(lineas) + "\n")


def correr(ruta):
    """Corre el script como lo haria el usuario y devuelve (codigo, salida)."""
    p = subprocess.run([sys.executable,
                        os.path.join(AQUI, "DecodificarSeq0.py"), ruta],
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


class TestDesarmar(unittest.TestCase):
    def test_encoding_de_matrixconmut(self):
        """i_M(8..6) = fila U, (5..3) = fila V, (2..0) = fila W, sobre [U V W]."""
        # salida U <- entrada U, salida V <- entrada V, salida W <- entrada W
        # fila U = 100, fila V = 010, fila W = 001 -> 100 010 001
        self.assertEqual(D.desarmar_matriz(0b100010001),
                         [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        # las tres salidas a la entrada U: 100 100 100
        self.assertEqual(D.desarmar_matriz(0b100100100),
                         [[1, 0, 0], [1, 0, 0], [1, 0, 0]])
        # salida U <- W (bit 6), salida W <- U (bit 2)
        self.assertEqual(D.desarmar_matriz(0b001010100),
                         [[0, 0, 1], [0, 1, 0], [1, 0, 0]])

    def test_q824_negativo(self):
        self.assertEqual(D.a_signed32(q824(-0.5)), -(1 << 23))
        self.assertEqual(D.a_signed32(q824(0.5)), 1 << 23)

    def test_clarke_vector_nulo(self):
        """Las tres salidas a la misma entrada no dan vector: solo modo comun."""
        al, be = D.clarke(0.7, 0.7, 0.7)
        self.assertAlmostEqual(al, 0.0, places=12)
        self.assertAlmostEqual(be, 0.0, places=12)


class TestVeredicto(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def ruta(self, nombre):
        return os.path.join(self.dir, nombre)

    def test_signo_bien_da_cero(self):
        r = self.ruta("bien.csv")
        generar(r, invertido=False)
        cod, sal = correr(r)
        self.assertEqual(cod, 0, sal)
        self.assertIn("esta BIEN", sal)

    def test_signo_invertido_da_uno(self):
        """El test que de verdad importa: tiene que CAZAR el bug."""
        r = self.ruta("mal.csv")
        generar(r, invertido=True)
        cod, sal = correr(r)
        self.assertEqual(cod, 1, sal)
        self.assertIn("INVERTIDO", sal)

    def test_ruido_no_decide(self):
        """Sin agrupamiento, el veredicto tiene que ser 'no se puede decidir'.

        Se arma con palabras one-hot validas pero elegidas al azar, asi que los
        vectores apuntan a cualquier lado: la concentracion colapsa.
        """
        import random
        random.seed(7)
        lineas = ["n," + ",".join("d%d" % i for i in range(20))]
        for k in range(200):
            th = 2.0 * math.pi * k / 97.0
            vi = [0.5178 * math.cos(th - 2.0 * math.pi * j / 3.0) for j in range(3)]
            pal = random.choice(ESTADOS)[0]
            f = [0] * 20
            f[0], f[1], f[2] = (q824(v) for v in vi)
            f[12] = pal
            f[18] = (random.randrange(PASOS) & 0x7FF) << 9
            lineas.append("%d," % k + ",".join("%x" % x for x in f))
        r = self.ruta("ruido.csv")
        with open(r, "w") as fh:
            fh.write("\n".join(lineas) + "\n")
        cod, sal = correr(r)
        self.assertEqual(cod, 1, sal)
        self.assertIn("NO SE PUEDE DECIDIR", sal)

    def test_filas_no_one_hot_no_decide(self):
        """Dos bits en una fila es un cortocircuito: no es un tema de signo."""
        lineas = ["n," + ",".join("d%d" % i for i in range(20))]
        for k in range(100):
            f = [0] * 20
            f[0] = q824(0.5)
            f[12] = 0b110010001          # fila U con DOS bits
            f[18] = (k & 0x7FF) << 9
            lineas.append("%d," % k + ",".join("%x" % x for x in f))
        r = self.ruta("corto.csv")
        with open(r, "w") as fh:
            fh.write("\n".join(lineas) + "\n")
        cod, sal = correr(r)
        self.assertEqual(cod, 1, sal)
        self.assertIn("one-hot", sal)

    def test_sin_encabezado_aborta_claro(self):
        r = self.ruta("sin_cab.csv")
        with open(r, "w") as fh:
            fh.write("0,1,2,3\n")
        cod, sal = correr(r)
        self.assertNotEqual(cod, 0)
        self.assertIn("encabezado", sal)


if __name__ == "__main__":
    unittest.main(verbosity=2)
