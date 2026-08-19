#!/usr/bin/env python
"""
Analiza la ESTRUCTURA TEMPORAL del patron de conmutacion, no su espectro.

Complementa a AnalizarBandas.py: aquel mide el contenido espectral de la tension de
salida, este mira como reparte el tiempo la maquina de PWM de Modulador.vhd. Se hace
por run-length encoding de la palabra de 9 bits de w_direcciones_log.csv, que trae una
fila por flanco de reloj.

Lo que contesta:

  1. Zona muerta de 8 LSB. El proceso de PWM saltea el vector si
     dela_sel(9 downto 3) = "0000000", o sea dela < 8. Se ve como un piso duro en el
     histograma de largos de slot: la duracion aplicada es dela - 1, asi que el run mas
     corto posible es 7 clks y no puede haber nada por debajo. Si la meseta que llega
     hasta ese piso es plana, hay truncamiento y por lo tanto vectores descartados; su
     densidad permite estimar cuantos se pierden y cuanto tiempo se llevan.

  2. Si esa perdida alcanza para explicar el 5.o/7.o armonico. La cota es directa: el
     tiempo perdido, como fraccion del tiempo activo, acota el aporte a las bandas de
     250 y 350 Hz aun suponiendo que caiga entero y coherente en una sola de ellas.

  3. Donde caen los slots cortos. Si el mecanismo fuera el de los cruces de sector,
     tendrian que agruparse 6 veces por periodo de SALIDA. Se cuentan contra las dos
     referencias, salida y entrada, en 12 celdas de fase (media celda = medio sector).

  4. Los dos sobrecostos fijos por Ts: el off-by-one (aplicado = dela - 1) y el hueco de
     arranque de 12 clks (6 con calculo_end alto + 6 de busqueda). El segundo se verifica
     mirando si los runs de 12 clks caen siempre en el mismo offset modulo 2048.

Resultado del 18/08/2026 (q = 180/256, 60 Hz in / 50 Hz out): la zona muerta es real
pero cuesta 0,073 % del tiempo activo, entre 5 y 8 veces menos de lo necesario, y los
slots cortos no se agrupan contra el angulo de salida. Queda descartada como causa del
5.o/7.o. El off-by-one cuesta 7 veces mas (0,494 % del fundamental) pero es un error de
ganancia constante, no una fuente de armonicos.

Uso:  python AnalizarPatronPWM.py [archivo_direcciones]
"""
import collections
import math
import os
import sys

F_CLK    = 10e6         # una fila por flanco de reloj
N_ESTADO = 2048         # ciclos por Ts (contador 'estado' de 11 bits)
N_FILAS  = 2_000_000    # 0,2 s exactos; el CSV trae 2_000_010 filas
F_IN, F_OUT = 60.0, 50.0

DELA_MIN = 8            # umbral de la zona muerta: dela_sel(9 downto 3) = "0000000"
N_CELDAS = 12           # celdas de fase por periodo; media celda = medio sector

# Los tres vectores nulos: las tres salidas a la misma entrada.
NULOS = {'100100100', '010010010', '001001001'}

# Las rutas por defecto cuelgan del propio script, no del directorio de trabajo:
# el debugger de VS Code arranca en la raiz del workspace y '../matlab' no resolvia.
AQUI = os.path.dirname(os.path.abspath(__file__))
POR_DEFECTO = os.path.join(AQUI, '..', 'matlab', 'w_direcciones_log.csv')


def leer_slots(ruta):
    """Run-length encoding de la palabra de 9 bits. Devuelve [(inicio, largo, palabra)]."""
    slots = []
    with open(ruta) as f:
        f.readline()                      # encabezado
        prev, ini, n = None, 0, 0
        for linea in f:
            if n >= N_FILAS:
                break
            w = linea.rstrip()[-9:]       # los 9 bits bajos de la palabra de 18
            if w != prev:
                if prev is not None:
                    slots.append((ini, n - ini, prev))
                prev, ini = w, n
            n += 1
        if prev is not None:
            slots.append((ini, n - ini, prev))
    return slots, n


def main():
    ruta = sys.argv[1] if len(sys.argv) > 1 else POR_DEFECTO
    if not os.path.isfile(ruta):
        sys.exit('No se encuentra %s' % ruta)

    print('Leyendo %s ...' % ruta)
    slots, n_filas = leer_slots(ruta)
    n_ts = n_filas / N_ESTADO

    act = [s for s in slots if s[2] not in NULOS]
    nul = [s for s in slots if s[2] in NULOS]
    t_act = sum(s[1] for s in act)
    frac_act = t_act / n_filas

    print('  %d filas = %.4f s = %.1f Ts' % (n_filas, n_filas / F_CLK, n_ts))

    # --- 1. Piso del histograma: la zona muerta ---------------------------
    h_act = collections.Counter(s[1] for s in act)
    print('\n--- Histograma de largos de slot ACTIVO (clks) ---')
    print('    la duracion aplicada es dela - 1, asi que el piso teorico es %d' % (DELA_MIN - 1))
    print('    %6s %8s' % ('clks', 'slots'))
    for L in range(DELA_MIN - 2, DELA_MIN + 13):
        print('    %6d %8d%s' % (L, h_act[L], '   <- piso' if L == DELA_MIN - 1 else ''))
    print('    minimo observado: %d clks' % min(h_act))

    # --- 2. Cuanto cuesta -------------------------------------------------
    # La meseta junto al piso da la densidad de slots por clk-bin. Los descartados son
    # los que hubieran caido en dela = 1..DELA_MIN-1, y su tiempo es la suma de esos dela.
    ventana = range(DELA_MIN - 1, DELA_MIN + 4)
    cortos = sum(h_act[L] for L in ventana)
    dens = cortos / len(ventana)
    n_desc = dens * (DELA_MIN - 1)
    t_perd = dens * sum(range(1, DELA_MIN))

    print('\n--- Costo de la zona muerta ---')
    print('  densidad junto al piso : %.1f slots por clk-bin' % dens)
    print('  slots descartados      : %.0f  = %.2f por Ts' % (n_desc, n_desc / n_ts))
    print('  tiempo perdido         : %.0f clks = %.4f %% del total = %.3f %% del activo'
          % (t_perd, 100 * t_perd / n_filas, 100 * t_perd / t_act))
    cota = 100 * t_perd / t_act
    print('\n  COTA para las bandas de %g y %g Hz, suponiendo que toda la perdida caiga'
          % (5 * F_OUT, 7 * F_OUT))
    print('  coherente en una sola banda: <= %.3f %% del fundamental' % cota)
    print('  (hasta ~%.2f %% si los vectores descartados fueran los de mayor magnitud)' % (2 * cota))

    # --- 3. Donde caen los slots cortos -----------------------------------
    # Si fueran los cruces de sector, tendrian que agruparse 6 veces por periodo, o sea
    # alternando celda por medio sobre 12 celdas, sea cual sea el offset de fase.
    fase = {F_OUT: [0] * N_CELDAS, F_IN: [0] * N_CELDAS}
    for ini, L, w in act:
        if DELA_MIN - 1 <= L <= DELA_MIN + 3:
            t = ini / F_CLK
            for f0 in fase:
                fase[f0][int((f0 * t % 1.0) * N_CELDAS)] += 1

    print('\n--- Slots activos cortos (%d..%d clks) por celda de fase ---'
          % (DELA_MIN - 1, DELA_MIN + 3))
    print('    un agrupamiento en los cruces de sector se veria como celda por medio')
    print('    %6s %10s %10s' % ('celda', 'vs f_out', 'vs f_in'))
    for c in range(N_CELDAS):
        print('    %6d %10d %10d' % (c, fase[F_OUT][c], fase[F_IN][c]))
    print('    total: %d slots cortos de %d activos' % (cortos, len(act)))

    # --- 4. Sobrecostos fijos por Ts --------------------------------------
    print('\n--- Sobrecostos fijos por Ts (%d clks) ---' % N_ESTADO)
    print('  slots activos : %5d = %.2f por Ts  (patron nominal: 8)' % (len(act), len(act) / n_ts))
    print('  slots nulos   : %5d = %.2f por Ts  (patron nominal: 3: N/2, N, N/2)'
          % (len(nul), len(nul) / n_ts))
    print('  fraccion activa: %.4f   fraccion nula: %.4f' % (frac_act, 1 - frac_act))
    off = len(act) / n_ts
    print('\n  off-by-one (aplicado = dela - 1), solo sobre vectores activos:')
    print('    %.2f clks/Ts = %.3f %% de Ts -> %.3f %% de caida del fundamental'
          % (off, 100 * off / N_ESTADO, 100 * off / N_ESTADO / frac_act))

    # El hueco de arranque: 6 clks de calculo_end alto + 6 de busqueda. Si es estructural
    # cae siempre en la misma fase del Ts.
    hueco = [s for s in nul if s[1] == 12]
    if hueco:
        offs = collections.Counter(s[0] % N_ESTADO for s in hueco)
        top, cuenta = offs.most_common(1)[0]
        print('\n  hueco de arranque de Ts (calculo_end + busqueda):')
        print('    %d runs nulos de 12 clks, %d de ellos (%.1f %%) en el offset %d modulo %d'
              % (len(hueco), cuenta, 100 * cuenta / len(hueco), top, N_ESTADO))
        print('    %d offsets distintos -> %s'
              % (len(offs), 'estructural' if len(offs) <= 2 else 'NO es un hueco fijo'))

    # --- 5. Rizado de la fraccion nula ------------------------------------
    # Ojo: la SVM ideal YA tiene rizado a 6*f por la variacion de cos(al_ot)*cos(be_it)
    # dentro del sector (+-5,7 %). Esto no sirve para detectar la zona muerta; se informa
    # porque las componentes a f_in y 2*f_in, que el modelo ideal no admite, si son anomalas.
    n_bloque = 2000                                  # 5000 bloques/s exactos -> bines de 5 Hz
    es_nulo = bytearray(n_filas)
    for ini, L, w in slots:
        if w in NULOS:
            for k in range(ini, min(ini + L, n_filas)):
                es_nulo[k] = 1
    serie = [sum(es_nulo[b:b + n_bloque]) / n_bloque
             for b in range(0, n_filas - n_bloque + 1, n_bloque)]
    fs_b = F_CLK / n_bloque
    media = sum(serie) / len(serie)

    def dft(x, f):
        n = len(x)
        m = sum(x) / n
        re = sum((v - m) * math.cos(-2 * math.pi * f * k / fs_b) for k, v in enumerate(x))
        im = sum((v - m) * math.sin(-2 * math.pi * f * k / fs_b) for k, v in enumerate(x))
        return 2 * math.hypot(re, im) / n

    print('\n--- Rizado de la fraccion nula (ventana %.2f s, bines de %.1f Hz) ---'
          % (len(serie) * n_bloque / F_CLK, fs_b / len(serie)))
    print('    OJO: la SVM ideal ya trae +-5,7 % a 6*f por el producto de cosenos dentro')
    print('    del sector. Lo anomalo son las componentes a f_in y 2*f_in, que el modelo')
    print('    ideal no admite (solo permite multiplos de 6*f).')
    print('    %8s %11s %11s   %s' % ('f [Hz]', 'amplitud', '% de media', 'que es'))
    for f0, que in [(6 * F_OUT, '6*f_out (cruces de sector de salida)'),
                    (6 * F_OUT + 5, '  control (multiplo impar de 5)'),
                    (6 * F_IN, '6*f_in  (cruces de sector de entrada)'),
                    (6 * F_IN - 5, '  control (multiplo impar de 5)'),
                    (F_OUT, 'f_out'),
                    (F_OUT - 5, '  control'),
                    (F_IN, 'f_in    <- ANOMALO'),
                    (F_IN + 5, '  control'),
                    (2 * F_IN, '2*f_in  <- ANOMALO'),
                    (2 * F_IN - 5, '  control')]:
        A = dft(serie, f0)
        print('    %8.1f %11.6f %10.2f    %s' % (f0, A, 100 * A / media, que))


if __name__ == '__main__':
    main()
