#!/usr/bin/env python3
"""El estado guardado del resonante, afecta al transitorio?

    python SW/python/AnalizarEstadoGuardado.py transitorios/

LA PREGUNTA

El criterio 6 dejo esto abierto: el resonante no decae -- det(A) = 1 exacto, o
sea oscilador sin perdidas -- asi que cuando llega una referencia arranca con la
energia que agarro en el arranque. Importa?

EL DISE~O, Y POR QUE NO HACE FALTA UN GRUPO DE CONTROL

Comparar contra "resonante en cero" obligaria a resetear el lazo, y eso resetea
tambien AC_Source, el CORDIC y la Clark: el punto de partida cambiaria en mas
cosas que la que se quiere aislar.

No hace falta. La amplitud guardada YA VARIA sola entre corridas, porque la fija
el transitorio de arranque: medido factor 2,08 entre dos corridas consecutivas
del mismo binario. Esa variacion es la variable independiente, gratis y sin
tocar nada.

    si el estado guardado afecta el transitorio -> el sobrepico correlaciona
    si no lo afecta -> el sobrepico sale reproducible aunque x1 varie al doble

Se corre el modo 7 varias veces y se correlacionan los pares.

QUE SE MIDE EN CADA CORRIDA

  energia previa: el pico a pico de x1 en las N_PRE muestras anteriores al
                  escalon, desenvuelto. Es la "condicion inicial".
  sobrepico:      el maximo de |i| despues del escalon contra el valor de
                  regimen, en por ciento.

Salida: el coeficiente de correlacion y el veredicto.
"""

import math
import os
import statistics
import sys

Q24 = float(1 << 24)


def a_signed32(u):
    return u - (1 << 32) if u & (1 << 31) else u


def leer(ruta):
    """Devuelve (x1 crudo, i_alfa pu, ref_alfa pu, q) y la muestra del escalon."""
    x1, ia, ref, q = [], [], [], []
    n_esc = None
    cab = None
    with open(ruta) as fh:
        for linea in fh:
            linea = linea.strip()
            if linea.startswith("# escalon"):
                # "# escalon de amp_ref 0 -> 0,06 pu en la muestra 512"
                n_esc = int(linea.split()[-1])
                continue
            if not linea or linea.startswith("#"):
                continue
            partes = linea.split(",")
            if partes[0] == "n":
                cab = partes
                continue
            if cab is None or len(partes) != 5:
                continue
            try:
                x1.append(int(partes[1], 16))
                ia.append(a_signed32(int(partes[2], 16)) / Q24)
                ref.append(a_signed32(int(partes[3], 16)) / Q24)
                q.append(int(partes[4], 16) & 0x1FF)
            except ValueError:
                continue
    return x1, ia, ref, q, n_esc


def desenvolver(v):
    if not v:
        return []
    out = [float(v[0])]
    off = 0
    for k in range(1, len(v)):
        d = v[k] - v[k - 1]
        if d > (1 << 31):
            off -= (1 << 32)
        elif d < -(1 << 31):
            off += (1 << 32)
        out.append(float(v[k] + off))
    return out


def medir(ruta):
    """(energia previa en LSB, sobrepico en %, regimen en pu) de una corrida."""
    x1c, ia, ref, q, n_esc = leer(ruta)
    if n_esc is None:
        raise SystemExit("%s no dice donde cayo el escalon (falta '# escalon')"
                         % os.path.basename(ruta))
    if len(ia) < n_esc + 200:
        raise SystemExit("%s tiene %d muestras y el escalon esta en %d: la "
                         "captura quedo corta" % (os.path.basename(ruta), len(ia), n_esc))

    x1 = desenvolver(x1c)
    prev = x1[:n_esc]
    energia = max(prev) - min(prev)

    # El regimen se mide en el ultimo cuarto, bien lejos del transitorio.
    post = ia[n_esc:]
    m = len(post)
    cola = post[3 * m // 4:]
    regimen = (max(cola) - min(cola)) / 2.0

    # El sobrepico: el mayor |i| del transitorio contra la amplitud de regimen.
    pico = max(abs(v) for v in post[:m // 2])
    sobre = 100.0 * (pico - regimen) / regimen if regimen > 0 else float("nan")
    return energia, sobre, regimen


def correlacion(xs, ys):
    n = len(xs)
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if sx == 0 or sy == 0:
        return 0.0
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    d = sys.argv[1]
    rutas = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".csv"))
    if len(rutas) < 3:
        raise SystemExit("Hacen falta al menos 3 corridas para correlacionar, "
                         "hay %d en %s" % (len(rutas), d))

    print("=== por corrida ===")
    print("  %-14s %14s %11s %13s"
          % ("archivo", "energia previa", "sobrepico", "regimen"))
    es, ss = [], []
    for r in rutas:
        e, s, g = medir(r)
        es.append(e)
        ss.append(s)
        print("  %-14s %14.3e %9.2f %% %10.5f pu"
              % (os.path.basename(r), e, s, g))
    print()

    rel_e = (max(es) - min(es)) / statistics.fmean(es)
    rel_s = (max(ss) - min(ss)) / abs(statistics.fmean(ss)) if statistics.fmean(ss) else 0
    rho = correlacion(es, ss)

    print("=== dispersion ===")
    print("  energia previa: %.3e .. %.3e   rango = %.0f %% de la media"
          % (min(es), max(es), 100.0 * rel_e))
    print("  sobrepico:      %.2f .. %.2f %%   rango = %.0f %% de la media"
          % (min(ss), max(ss), 100.0 * rel_s))
    print()
    # Cuantas condiciones DISTINTAS hay de verdad. Si el arranque resulta casi
    # determinista, varias corridas repiten el mismo valor y la correlacion se
    # calcula sobre muchos menos puntos de los que parece.
    distintas = len(set(round(e, -7) for e in es))
    print("=== correlacion ===")
    print("  coeficiente de Pearson: %+.3f  sobre %d corridas"
          % (rho, len(es)))
    print("  condiciones iniciales DISTINTAS: %d" % distintas)
    if distintas < 4:
        print("  OJO: con %d condiciones distintas la correlacion es debil como" % distintas)
        print("  evidencia. Lo que sostiene el veredicto es el TAMA~O del efecto,")
        print("  no su significancia estadistica.")
    print()

    # El veredicto. Con pocas corridas, |rho| alto puede salir por azar, asi que
    # se exige ADEMAS que el sobrepico se mueva de verdad: una correlacion
    # fuerte sobre un sobrepico que no varia no significa nada.
    if abs(rho) > 0.7 and rel_s > 0.15:
        print("VEREDICTO: el estado guardado SI afecta el transitorio.")
        print("  El sobrepico sigue a la energia previa (rho = %+.3f) y varia" % rho)
        print("  %.0f %% entre corridas. Corresponde decidir si se amortigua el" % (100*rel_s))
        print("  resonante o si se resetea x1/x2 cuando amp_ref va a cero.")
        return 1

    print("VEREDICTO: el estado guardado NO afecta el transitorio de forma medible.")
    print("  La energia previa varia %.0f %% entre corridas y el sobrepico se"
          % (100.0 * rel_e))
    print("  queda en %.2f +/- %.2f %%. La correlacion es %+.3f."
          % (statistics.fmean(ss), statistics.pstdev(ss), rho))
    print()
    print("  Sentido fisico: el escalon a 0,06 pu inyecta mucha mas energia que")
    print("  la que el resonante tenia guardada, asi que la condicion inicial")
    print("  queda enterrada en el transitorio.")
    print()
    print("  Lo que de verdad cierra el caso es el TAMA~O: el criterio 2 pide")
    print("  sobrepico < 20 %% y todas las corridas dan %.2f +/- %.2f %%. Aunque"
          % (statistics.fmean(ss), statistics.pstdev(ss)))
    print("  el estado guardado tuviera algun efecto, es %.0fx mas chico que el"
          % (20.0 / max(max(ss) - min(ss), 1e-9)))
    print("  margen que hay contra el limite.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
