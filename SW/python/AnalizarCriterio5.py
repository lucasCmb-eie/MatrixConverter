#!/usr/bin/env python3
"""Criterio 5 del spec: conversion de frecuencia, 60 Hz in / 55 Hz out.

    python SW/python/AnalizarCriterio5.py captura.csv

    | 5 | Conversion de frecuencia, 60 in / 55 out | fundamental de i_o en
    |   |                                          | 55 Hz; nada en 60 Hz
    |   |                                          | sobre el piso

POR QUE 60/55 Y NO 60/50

Con 60 y 50 todo producto m*f_in + n*f_o es multiplo de 10 Hz, asi que cada bin
recibe INFINITOS productos y no se puede atribuir una banda a una causa. Con 55
la grilla pasa a 5 Hz y cada banda queda identificada. Esta en el spec 7.4 y en
[[project-degeneracion-60-50hz]].

COMO SE MIDE EL PISO

No alcanza con mirar el valor absoluto de una banda: hay que compararla contra
el ruido que tiene AL LADO. El piso no es plano, sube hacia la frecuencia de
conmutacion, asi que un promedio global enga~aria.

Los bines de CONTROL son multiplos IMPARES de 5 Hz. Como f_in y f_o son
multiplos de 5, todo producto m*f_in + n*f_o cae en un multiplo PAR de 5: un
impar no puede contener se~al real por construccion. Lo que aparezca ahi es puro
piso de medicion, y hay uno al lado de cada banda de interes.

EL ESPECTRO SE EVALUA EN FRECUENCIAS EXACTAS, no en bines

fs = 10e6/2048 = 4882,8125 Hz no es conmensurable con 5 Hz, asi que ninguna
frecuencia de interes cae exactamente en un bin de la FFT. En vez de redondear
al bin mas cercano -- que mete error de scalloping de hasta 1,5 dB -- se evalua
la DFT en la frecuencia exacta, con ventana de Hann. Cuesta un bucle por
frecuencia y son dos docenas de frecuencias: nada.

Salida: codigo 0 si el criterio pasa, 1 si no.
"""

import cmath
import math
import sys

FS = 10.0e6 / 2048.0        # una muestra por Ts
Q24 = float(1 << 24)
F_IN, F_OUT = 60.0, 55.0

# Las dos familias apuntan a causas distintas.
#   acople: errores en el reparto entre configuraciones del modulador
#   armonicos: los 6 cruces de sector por periodo salen como 5.o (secuencia
#              negativa) y 7.o (positiva) en el marco estacionario
ACOPLE = [
    ("f_in - f_o", abs(F_IN - F_OUT)),
    ("f_in",       F_IN),
    ("f_in + f_o", F_IN + F_OUT),
    ("2f_in - f_o", 2 * F_IN - F_OUT),
    ("2f_in + f_o", 2 * F_IN + F_OUT),
]
ARMONICOS = [("%d f_o" % n, n * F_OUT) for n in (3, 5, 7, 9)]

# Multiplos IMPARES de 5 Hz: no pueden contener se~al real. Hay uno cerca de
# cada banda de interes, porque el piso sube con la frecuencia.
CONTROL = [25.0, 45.0, 85.0, 125.0, 185.0, 245.0, 345.0, 455.0, 555.0]

# El criterio: una banda esta "sobre el piso" si supera a su vecino de control
# por este factor. 2x es ~6 dB, que es lo minimo para afirmar que algo asoma.
FACTOR_PISO = 2.0


def a_signed32(u):
    return u - (1 << 32) if u & (1 << 31) else u


def leer(ruta):
    """Devuelve (lista de i_alfa, lista de i_beta) en pu."""
    al, be = [], []
    cab = None
    with open(ruta) as fh:
        for linea in fh:
            linea = linea.strip()
            if not linea or linea.startswith("#"):
                continue
            partes = linea.split(",")
            if partes[0] == "n":
                cab = partes
                continue
            if cab is None:
                continue          # banner de PuTTY y demas
            if len(partes) != 3:
                continue          # linea cortada por la UART
            try:
                al.append(a_signed32(int(partes[1], 16)) / Q24)
                be.append(a_signed32(int(partes[2], 16)) / Q24)
            except ValueError:
                continue
    return al, be


def dft_en(x, f, fs):
    """|X(f)| con ventana de Blackman-Harris, evaluada en la frecuencia EXACTA f.

    POR QUE BLACKMAN-HARRIS Y NO HANN. El fundamental mide 0,06 pu y las bandas
    de interes andan por 1e-5: cinco ordenes abajo. Con Hann (primer lobulo
    lateral a -31 dB) la FALDA DE FUGA del fundamental domina todo lo que este
    cerca, y 60 Hz esta a 5 Hz de 55.

    Medido sobre la captura del 03/10/2026, Hann contra BH4:

        60 Hz   3,02e-05 -> 2,27e-06   cae 13x   era fuga
        50 Hz   2,97e-05 -> 8,89e-07   cae 33x   era fuga
       165 Hz   1,25e-05 -> 1,21e-05   0,97x     se~al real
       275 Hz   2,09e-05 -> 2,08e-05   1,00x     se~al real

    Con Hann este script reportaba "hay se~al en f_in, 18,6x el piso" y era un
    artefacto de su propia ventana. Los -92 dB de BH4 lo resuelven.

    El costo es un lobulo principal mas ancho: 8 bines contra 4. Con N = 8192
    son 4,77 Hz, y 60 Hz esta a 5,0 Hz del fundamental -- justo afuera. Si se
    necesitara mas margen, el camino es mas muestras, no otra ventana.

    Devuelve amplitud de pico equivalente: se normaliza por la suma de la
    ventana para que un seno de amplitud A de como resultado A.
    """
    n = len(x)
    acc = 0j
    g = 0.0
    for k in range(n):
        t = 2.0 * math.pi * k / (n - 1)
        w = (0.35875 - 0.48829 * math.cos(t)
             + 0.14128 * math.cos(2.0 * t) - 0.01168 * math.cos(3.0 * t))
        g += w
        acc += x[k] * w * cmath.exp(-2j * math.pi * f * k / fs)
    return 2.0 * abs(acc) / g


def piso_vecino(espectro_control, f):
    """El bin de control mas cercano a f, que es con lo que hay que comparar."""
    return min(espectro_control.items(), key=lambda kv: abs(kv[0] - f))


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    al, be = leer(sys.argv[1])
    if len(al) < 1024:
        raise SystemExit(
            "Solo %d muestras. El criterio necesita 8192 para separar 55 de "
            "60 Hz (lobulo de Hann 2,38 Hz contra 5 Hz de separacion). "
            "Capturaste el volcado completo, hasta el '# fin'?" % len(al))

    n = len(al)
    print("muestras: %d   ventana: %.3f s   fs: %.4f Hz" % (n, n / FS, FS))
    print("resolucion: %.4f Hz   lobulo de Hann: %.2f Hz" % (FS / n, 4.0 * FS / n))
    print()

    # El fasor complejo alfa+j*beta: en el marco estacionario la secuencia
    # positiva aparece en +f y la negativa en -f, asi que el espectro complejo
    # las separa. Para este criterio alcanza con el modulo sobre alfa.
    x = al

    ctrl = {}
    for f in CONTROL:
        ctrl[f] = dft_en(x, f, FS)
    piso_tipico = sorted(ctrl.values())[len(ctrl) // 2]

    print("=== piso de medicion (multiplos impares de 5 Hz) ===")
    for f in sorted(ctrl):
        print("  %7.1f Hz   %.3e pu" % (f, ctrl[f]))
    print("  mediana: %.3e pu" % piso_tipico)
    print()

    fund = dft_en(x, F_OUT, FS)
    print("=== fundamental ===")
    print("  %7.1f Hz   %.4f pu   <- f_o" % (F_OUT, fund))
    print()

    fallas = []
    print("=== bandas (comparadas contra su vecino de control) ===")
    print("  %-12s %8s   %10s  %10s  %7s" % ("banda", "f [Hz]", "amplitud", "piso vec.", "ratio"))
    for nombre, f in ACOPLE + ARMONICOS:
        a = dft_en(x, f, FS)
        fv, pv = piso_vecino(ctrl, f)
        ratio = a / pv if pv > 0 else float("inf")
        marca = ""
        if nombre == "f_in":
            # EL criterio: no tiene que haber nada en 60 Hz sobre el piso
            if ratio > FACTOR_PISO:
                marca = "  <-- FALLA: hay se~al en f_in"
                fallas.append("f_in sobre el piso (%.1fx)" % ratio)
            else:
                marca = "  <-- OK: en el piso"
        print("  %-12s %8.1f   %.3e  %.3e  %6.2fx%s"
              % (nombre, f, a, pv, ratio, marca))
    print()

    # El fundamental tiene que estar MUY por encima del piso, o no hay se~al
    rf, pf = piso_vecino(ctrl, F_OUT)
    if fund / pf < 20.0:
        fallas.append("el fundamental no asoma del piso (%.1fx)" % (fund / pf))
        print("FALLA: el fundamental en %.0f Hz esta a %.1fx del piso."
              % (F_OUT, fund / pf))
        print("  O el lazo no esta siguiendo, o la captura no es de este modo.")

    print()
    if fallas:
        print("CRITERIO 5: NO PASA")
        for f in fallas:
            print("  - %s" % f)
        return 1
    print("CRITERIO 5: PASA")
    print("  El fundamental sale en %.0f Hz a %.4f pu, y %.0f Hz esta en el piso."
          % (F_OUT, fund, F_IN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
