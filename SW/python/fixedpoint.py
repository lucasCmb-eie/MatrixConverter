"""Aritmetica de punto fijo que replica exactamente la del RTL.

Convencion Q(m.n): m bits enteros incluyendo el signo, n bits fraccionarios.
El truncamiento es SIEMPRE hacia -infinito, que es lo que hacen tanto
`fixed_truncate` de ieee.fixed_pkg como el shift aritmetico a derecha de
ieee.numeric_std. Redondear al mas cercano solo se usa para constantes que
el PS calcula en punto flotante y escribe una vez.
"""

import math


class Q:
    """Un formato Q(int_bits.frac_bits) con signo."""

    def __init__(self, int_bits, frac_bits):
        self.i = int_bits
        self.f = frac_bits
        self.bits = int_bits + frac_bits
        self.lo = -(1 << (self.bits - 1))
        self.hi = (1 << (self.bits - 1)) - 1

    def de_float(self, x, redondear=False):
        """Cuantiza un float al entero que lo representa en este formato."""
        escala = 1 << self.f
        if redondear:
            v = int(math.floor(x * escala + 0.5))
        else:
            v = int(math.floor(x * escala))
        return self.envolver(v)

    def a_float(self, v):
        return v / float(1 << self.f)

    def envolver(self, v):
        """Wrap de complemento a dos al ancho del formato."""
        m = 1 << self.bits
        return ((v + (m >> 1)) % m) - (m >> 1)

    def saturar(self, v):
        return max(self.lo, min(self.hi, v))


def mul_trunc(a, b, frac_a, frac_b, frac_r):
    """Producto entero reescalado de Q(.frac_a)*Q(.frac_b) a Q(.frac_r).

    El shift a derecha de Python sobre enteros negativos ya trunca hacia
    -infinito, igual que shift_right sobre signed en numeric_std.
    """
    desplazamiento = frac_a + frac_b - frac_r
    if desplazamiento >= 0:
        return (a * b) >> desplazamiento
    return (a * b) << (-desplazamiento)
