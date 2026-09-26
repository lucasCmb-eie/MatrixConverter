"""Suite de verificacion del modelo de oro del lazo de corriente PR."""

import unittest

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


if __name__ == "__main__":
    unittest.main()
