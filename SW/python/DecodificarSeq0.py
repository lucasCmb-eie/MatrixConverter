#!/usr/bin/env python3
"""Decodifica la captura de SW/ps/valida_seq0.c y valida el signo de seq0.

    python SW/python/DecodificarSeq0.py captura.csv

QUE DECIDE

Modulador.vhd tenia el signo de seq0 complementado y sintetizaba el vector en
al_o + 180 grados. Este script toma las fotos que el PS volco por UART y decide
si el arreglo quedo bien, sobre hardware.

EL METODO, Y POR QUE NO ES UNA COMPARACION DIRECTA

Cada captura toma UN vector instantaneo, no el promedio. La SSVM aplica varios
vectores activos por Ts cuyo promedio es al_o, y o_trg_calculo cae siempre en el
mismo punto de la ventana de PWM, asi que el angulo de una sola foto NO tiene
por que coincidir con al_o.

El discriminador es la MEDIA CIRCULAR de (angulo aplicado - al_o) sobre un
periodo de salida: los vectores activos estan repartidos alrededor de al_o, asi
que su media circular se alinea con al_o. Si el signo esta bien la media apunta
cerca de 0 grados; si volviera el bug, cerca de 180.

Se informan las dos cosas: el angulo de la media y su CONCENTRACION (el modulo,
entre 0 y 1). Una concentracion baja significa que los vectores no se agrupan y
que el veredicto no vale, que es justo lo que hay que ver antes de creerle.

Salida: codigo 0 si el signo esta bien, 1 si esta invertido o si los datos no
alcanzan para decidir.
"""

import cmath
import math
import sys

Q24 = float(1 << 24)
PASOS = 2048           # al_o: 0..2047 = 0..2*pi


def a_signed32(u):
    """Los Q8.24 del CSV vienen como la palabra cruda de 32 bits."""
    return u - (1 << 32) if u & (1 << 31) else u


def leer(ruta):
    """Devuelve la lista de fotos, cada una como lista de 20 enteros sin signo."""
    fotos = []
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
                # Sin encabezado no se puede confiar en el orden de columnas.
                raise SystemExit(
                    "El CSV no tiene la linea de encabezado 'n,d0,d1,...'. "
                    "Capturaste la UART desde el arranque del programa?")
            if len(partes) != 21:
                continue           # linea cortada por la UART
            try:
                fotos.append([int(x, 16) for x in partes[1:]])
            except ValueError:
                continue           # basura de la UART
    return fotos


def desarmar_matriz(palabra):
    """Palabra de 9 bits -> [fila_U, fila_V, fila_W], cada fila [eU, eV, eW].

    Formato de matrixConmut.vhd:72-74:
        i_M(8..6) = fila de salida U sobre las entradas [U V W]
        i_M(5..3) = fila de salida V
        i_M(2..0) = fila de salida W
    """
    m = []
    for fila in range(3):
        base = 8 - 3 * fila
        m.append([(palabra >> (base - k)) & 1 for k in range(3)])
    return m


def clarke(a, b, c):
    """abc -> alpha/beta, amplitud invariante (el 2/3 del datapath)."""
    al = (2.0 / 3.0) * (a - 0.5 * b - 0.5 * c)
    be = (2.0 / 3.0) * (math.sqrt(3.0) / 2.0) * (b - c)
    return al, be


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    fotos = leer(sys.argv[1])
    if not fotos:
        raise SystemExit("No hay ninguna foto valida en el CSV.")
    print("fotos leidas: %d" % len(fotos))

    # --- integridad de la captura -----------------------------------------
    # En un conversor matricial cada salida se conecta a UNA entrada: una fila
    # con dos bits es un cortocircuito entre fases de entrada, y con cero es una
    # salida abierta. Si esto falla, el problema no es el signo de seq0.
    malas = 0
    sats = 0
    for f in fotos:
        m = desarmar_matriz(f[12] & 0x1FF)
        if any(sum(fila) != 1 for fila in m):
            malas += 1
        if (f[18] >> 20) & 1:
            sats += 1
    print("filas no one-hot: %d de %d" % (malas, len(fotos)))
    if sats:
        print("ATENCION: %d fotos con sat=1; q esta clampeado en q_max y los "
              "vectores no son los que el lazo pidio." % sats)
    if malas > len(fotos) // 10:
        print("\nVEREDICTO: NO SE PUEDE DECIDIR.")
        print("  Mas del 10 %% de las fotos tienen filas que no son one-hot.")
        print("  Eso no es un problema de signo: o la captura esta corrupta, o")
        print("  la palabra de conmutacion esta mal formada. Revisar primero.")
        return 1

    # --- el discriminador -------------------------------------------------
    suma = 0j
    usadas = 0
    for f in fotos:
        m = desarmar_matriz(f[12] & 0x1FF)
        if any(sum(fila) != 1 for fila in m):
            continue
        vi = [a_signed32(f[k]) / Q24 for k in (0, 1, 2)]
        # salida = matriz * entrada
        vo = [sum(m[s][e] * vi[e] for e in range(3)) for s in range(3)]
        al, be = clarke(*vo)
        if abs(al) < 1e-9 and abs(be) < 1e-9:
            continue                     # vector nulo: no dice nada del angulo
        ang = math.atan2(be, al)
        al_o = ((f[18] >> 9) & 0x7FF) * 2.0 * math.pi / PASOS
        suma += cmath.exp(1j * (ang - al_o))
        usadas += 1

    if usadas < 20:
        print("\nVEREDICTO: NO SE PUEDE DECIDIR.")
        print("  Solo %d fotos con un vector activo. Hace falta amp_ref mas" % usadas)
        print("  grande, o mas capturas.")
        return 1

    media = suma / usadas
    desfase = math.degrees(cmath.phase(media))
    conc = abs(media)
    print("\nvectores activos usados: %d" % usadas)
    print("media circular de (angulo aplicado - al_o):")
    print("    desfase       = %+.2f grados" % desfase)
    print("    concentracion = %.3f   (0 = nada agrupado, 1 = todos iguales)"
          % conc)

    if conc < 0.3:
        print("\nVEREDICTO: NO SE PUEDE DECIDIR.")
        print("  La concentracion de %.3f es demasiado baja: los vectores no se" % conc)
        print("  agrupan alrededor de ninguna direccion, asi que la media no")
        print("  significa nada. Revisar que el lazo este en regimen y que")
        print("  amp_ref sea suficiente.")
        return 1

    dist_0 = abs(((desfase + 180.0) % 360.0) - 180.0)
    dist_180 = abs(((desfase) % 360.0) - 180.0)
    print()
    if dist_0 < dist_180:
        print("VEREDICTO: el signo de seq0 esta BIEN.")
        print("  El vector aplicado se sintetiza en al_o (%+.2f grados de" % desfase)
        print("  desfase, contra los 180 que daria el bug).")
        return 0
    print("VEREDICTO: el signo de seq0 esta INVERTIDO.")
    print("  El vector se sintetiza en al_o + 180 (%+.2f grados medidos)." % desfase)
    print("  El arreglo de Modulador.vhd no quedo aplicado en este bitstream.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
