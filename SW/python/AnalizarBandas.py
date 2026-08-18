#!/usr/bin/env python
"""
Analiza los CSV que escribe tb_SVM_Wrapper.vhd.

  - Espectro de la tension de salida en las frecuencias de interes, quitando el
    modo comun (la carga es estrella de neutro flotante y no lo ve).
  - Estructura del patron de conmutacion: reparto activo/nulo, slots por Ts,
    saturaciones.

Se mide sobre la TENSION, no sobre la corriente: el modelo RL offline arranca de
cero y su transitorio de tau = 10 ms deja una falda de baja frecuencia que cae
justo sobre el bin de 10 Hz.

Uso:  python AnalizarBandas.py [directorio_csv]
"""
import math
import os
import statistics
import sys

F_CLK   = 10e6          # una fila por flanco de reloj
N_ESTADO = 2048         # ciclos por Ts (contador 'estado' de 11 bits)
F_IN, F_OUT = 60.0, 50.0

# Dos familias distintas, que apuntan a causas distintas:
#   - acople con la entrada: sale de errores en el reparto entre configuraciones
#   - armonicos de la salida: 6 perturbaciones por periodo (cruces de sector) aparecen
#     como 5.o (secuencia negativa) y 7.o (positiva) en el marco estacionario
ACOPLE   = [abs(F_IN - F_OUT), F_IN, F_IN + F_OUT,
            2 * F_IN - F_OUT, 2 * F_IN + F_OUT]
ARMONICOS = [3 * F_OUT, 5 * F_OUT, 7 * F_OUT, 9 * F_OUT]

# Control: todo producto m*f_in + n*f_out es multiplo de 10 Hz (f_in y f_out lo son).
# Con ventana de 0,2 s los bines son de 5 Hz, asi que un multiplo IMPAR de 5 cae justo
# en un bin y no puede contener senal real por construccion: lo que aparezca ahi es
# puro piso de medicion (fuga de la conmutacion, incommensurable con la ventana).
# El piso NO es plano en frecuencia, sube hacia f_sw, por eso hay uno al lado de cada
# banda de interes: comparar cada banda contra su vecino, no contra el promedio.
CONTROL = [45.0, 105.0, 165.0, 245.0, 345.0, 455.0]

FRECS = [F_OUT] + ACOPLE + ARMONICOS + CONTROL

NULOS = {'100100100', '010010010', '001001001'}

# Las rutas por defecto cuelgan del propio script, no del directorio de trabajo:
# el debugger de VS Code arranca en la raiz del workspace y '../matlab' no resolvia.
AQUI = os.path.dirname(os.path.abspath(__file__))


def espectro(ruta):
    """DFT puntual en FRECS sobre la tension sin modo comun."""
    acc = {f: [0.0, 0.0] for f in FRECS}
    suma = 0.0
    n = 0
    with open(ruta) as fh:
        fh.readline()
        for linea in fh:
            p = linea.split(',')
            if len(p) < 4:
                continue
            u, v, w = float(p[1]), float(p[2]), float(p[3])
            ul = u - (u + v + w) / 3.0
            suma += ul
            t = n / F_CLK
            for f in FRECS:
                a = 2 * math.pi * f * t
                A = acc[f]
                A[0] += ul * math.cos(a)
                A[1] += ul * math.sin(a)
            n += 1
    amp = {f: 2 * math.hypot(*acc[f]) / n for f in FRECS}
    return amp, suma / n, n


def patron(ruta):
    """Duracion de cada slot aplicado, separando activos de nulos."""
    prev, cur, runs = None, 0, []
    with open(ruta) as fh:
        fh.readline()
        for linea in fh:
            w = linea.strip()[-9:]
            if w == prev:
                cur += 1
            else:
                if prev is not None:
                    runs.append((prev, cur))
                prev, cur = w, 1
    runs.append((prev, cur))
    n = sum(c for _, c in runs)
    act = [c for w, c in runs if w not in NULOS]
    nul = [c for w, c in runs if w in NULOS]
    return runs, act, nul, n


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(AQUI, '..', 'matlab')
    f_ten = os.path.join(base, 'Clk10M_60i_50o_Simetrico.csv')
    f_dir = os.path.join(base, 'w_direcciones_log.csv')

    if not os.path.isfile(f_ten):
        print('No encuentro', os.path.abspath(f_ten))
        sys.exit('Uso: python AnalizarBandas.py [directorio_csv]')

    amp, dc, n = espectro(f_ten)
    fund = amp[F_OUT]
    print('=== Tension de salida (sin modo comun) ===')
    print('  ventana      : %.4f s  (%d muestras)' % (n / F_CLK, n))
    print('  DC           : %+.6f' % dc)
    print('  %7.1f Hz  : %.5f   %6.2f %%   <- fundamental' % (F_OUT, fund, 100.0))

    def bloque(titulo, lista):
        print('  --- %s ---' % titulo)
        for f in sorted(lista):
            print('  %7.1f Hz  : %.5f   %6.2f %%' % (f, amp[f], 100 * amp[f] / fund))
        rss = math.sqrt(sum(amp[f] ** 2 for f in lista))
        print('  %7s      : %.5f   %6.2f %%   (RSS)' % ('', rss, 100 * rss / fund))
        return rss

    r1 = bloque('acople con la entrada', ACOPLE)
    r2 = bloque('armonicos de la salida', ARMONICOS)
    r3 = bloque('CONTROL (piso de medicion)', CONTROL)
    piso = r3 / math.sqrt(len(CONTROL))
    print('  piso por banda: %.5f   %6.2f %%   <- comparar cada banda contra esto'
          % (piso, 100 * piso / fund))
    total = math.sqrt(r1 ** 2 + r2 ** 2)
    print('  residuo TOTAL: %.5f   %6.2f %% de la fundamental' % (total, 100 * total / fund))
    print('  NOTA: el RSS incluye mas bandas que antes; comparar banda por banda,')
    print('        no el total, contra corridas hechas con la version anterior.')

    if os.path.isfile(f_dir):
        runs, act, nul, n2 = patron(f_dir)
        vent = n2 / N_ESTADO
        print()
        print('=== Patron de conmutacion ===')
        print('  slots por Ts : %.2f   (11 posibles)' % (len(runs) / vent))
        print('  nulos por Ts : %.2f   (3 esperados)' % (len(nul) / vent))
        print('  tiempo activo: %.1f %%   -> sum|delta| = %.3f' % (100 * sum(act) / n2, sum(act) / n2))
        print('  tiempo nulo  : %.1f %%' % (100 * sum(nul) / n2))
        print('  activos      : min %d  mediana %d  max %d' % (min(act), statistics.median(act), max(act)))
        print('  saturados    : %d slots >= 1000 clks' % len([c for c in act if c >= 1000]))


if __name__ == '__main__':
    main()
