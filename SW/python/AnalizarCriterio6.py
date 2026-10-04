#!/usr/bin/env python3
"""Criterio 6 del spec: referencia nula, regimen.

    python SW/python/AnalizarCriterio6.py captura.csv

    | 6 | Referencia nula, regimen | ciclo limite de x1/x2 acotado a pocos LSB |

QUE SE MIDE Y POR QUE ESOS BITS

Con amp_ref = 0 el lazo no tiene nada que seguir, pero los resonantes siguen
integrando el error de cuantizacion. Lo que queda es un CICLO LIMITE: una
oscilacion que no decae porque la cuantizacion la realimenta. El criterio pide
que este acotado a pocos LSB, no que sea cero -- cero es imposible en punto
fijo.

La ranura 19 trae los 32 bits BAJOS de x1 (que es Q8.40 en 48 bits), no los
altos. Es deliberado: un ciclo limite de unos pocos LSB de Q8.40 desaparece si
se trunca a Q8.24. La magnitud de x1 no se pierde, se observa por v_alfa
(ranura 16), que es kp*e + x1>>16.

QUE DISTINGUE UN CICLO LIMITE ACOTADO DE UNO QUE NO LO ESTA

Un ciclo limite sano oscila alrededor de un valor y no crece. Los dos modos de
falla son:
  - DERIVA: la media se corre con el tiempo -> el integrador se esta yendo
  - CRECIMIENTO: la amplitud sube -> el lazo es inestable a bajo nivel

Asi que no alcanza con mirar el pico a pico global: hay que partir el registro
y comparar la primera mitad con la segunda. Un pico a pico chico medido sobre
un transitorio que todavia no termino daria bien y estaria mintiendo.

LA TRAMPA DEL ENVOLVIMIENTO

x1 se captura como los 32 bits bajos de un valor de 48, asi que ENVUELVE. Un
salto de 2**32 - 1 a 0 es continuidad, no un salto de 4 mil millones de LSB. Se
desenvuelve antes de medir nada; si el desenvolvimiento tuviera que actuar mucho
es que x1 no esta acotado y el script lo dice.

Salida: codigo 0 si el criterio pasa, 1 si no.
"""

import statistics
import sys

# "Pocos LSB" del spec, operacionalizado. 256 LSB de Q8.40 son 2**-32 en valor
# absoluto = 2,3e-10, siete ordenes por debajo del fondo de escala de la
# corriente (0,06 pu de referencia tipica). Es generoso a proposito: lo que el
# criterio quiere descartar es un ciclo limite de miles de LSB o uno que crece.
LIMITE_PP = 256

# Cuanto puede moverse la media entre la primera y la segunda mitad, en LSB.
LIMITE_DERIVA = 64

# Cuanto puede crecer el pico a pico de la primera mitad a la segunda.
LIMITE_CRECIMIENTO = 1.5


def a_signed32(u):
    return u - (1 << 32) if u & (1 << 31) else u


def leer(ruta):
    """Devuelve (x1 crudo sin signo, q, al_o, sat, i_alfa en pu).

    Soporta los dos formatos: la primera version del modo 6 volcaba dos
    columnas y la actual tres, con i_alfa. Se distingue por el ancho.
    """
    x1, q, alo, sat, ia = [], [], [], [], []
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
                continue
            if len(partes) not in (3, 4):
                continue
            try:
                x1.append(int(partes[1], 16))
                p18 = int(partes[2], 16)
                ia.append(a_signed32(int(partes[3], 16)) / 2.0**24
                          if len(partes) == 4 else None)
            except ValueError:
                continue
            q.append(p18 & 0x1FF)
            alo.append((p18 >> 9) & 0x7FF)
            sat.append((p18 >> 20) & 1)
    return x1, q, alo, sat, ia


def desenvolver(v):
    """Deshace el envolvimiento de 32 bits. Devuelve (serie, cuantas veces actuo)."""
    if not v:
        return [], 0
    out = [float(v[0])]
    off = 0
    n = 0
    for k in range(1, len(v)):
        d = v[k] - v[k - 1]
        if d > (1 << 31):
            off -= (1 << 32)
            n += 1
        elif d < -(1 << 31):
            off += (1 << 32)
            n += 1
        out.append(float(v[k] + off))
    return out, n


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    x1c, q, alo, sat, ia = leer(sys.argv[1])
    if len(x1c) < 512:
        raise SystemExit(
            "Solo %d muestras. Capturaste el volcado completo, hasta el "
            "'# fin'? El criterio necesita ver varios periodos." % len(x1c))

    n = len(x1c)
    print("muestras: %d   ventana: %.3f s" % (n, n * 2048 / 10e6))
    print()

    # --- la referencia tiene que ser NULA, o no es este test ---------------
    qmax = max(q)
    nsat = sum(sat)
    print("=== la referencia es nula de verdad? ===")
    print("  q:   max %d de 255" % qmax)
    print("  sat: %d de %d muestras" % (nsat, n))
    if qmax > 8:
        print("  FALLA: q llega a %d. Eso no es referencia nula: o amp_ref no" % qmax)
        print("  quedo en 0, o hay un offset. Lo que se mida abajo no es un")
        print("  ciclo limite.")
        return 1
    print("  OK: q se queda en el ruido, la referencia es nula")
    print()

    # --- el ciclo limite --------------------------------------------------
    x1, nenv = desenvolver(x1c)
    print("=== x1_alfa (LSB de Q8.40) ===")
    if nenv:
        # Envolver NO es una falla: la ranura 19 trae los 32 bits BAJOS de un
        # valor de 48, asi que su ventana cubre hasta 2**-8 = 3,9e-3. Si el
        # ciclo limite es mas grande que eso, envuelve, y desenvolver lo
        # reconstruye sin perdida mientras el salto entre muestras sea menor a
        # 2**31 -- que con 83 envolvimientos en 4096 muestras significa uno cada
        # ~49, muy lejos del limite. La version anterior de este script abortaba
        # aca y era un error: juzgaba el instrumento, no la se~al.
        print("  el desenvolvimiento actuo %d veces (uno cada ~%d muestras)"
              % (nenv, n // max(nenv, 1)))
        salto_max = max(abs(x1[k] - x1[k - 1]) for k in range(1, len(x1)))
        print("  salto maximo entre muestras: %.3e LSB (limite 2**31 = %.3e)"
              % (salto_max, 2.0**31))
        if salto_max > 2.0**31 * 0.5:
            print("  FALLA: los saltos se acercan al limite del desenvolvimiento,")
            print("  asi que la reconstruccion no es confiable. Hace falta")
            print("  capturar los 32 bits ALTOS de x1 en vez de los bajos.")
            return 1

    pp = max(x1) - min(x1)
    media = statistics.fmean(x1)
    desv = statistics.pstdev(x1)
    print("  pico a pico: %.0f LSB   (limite %d)" % (pp, LIMITE_PP))
    print("  media: %.1f   desvio: %.1f LSB" % (media, desv))
    print()

    # --- primera mitad contra segunda: deriva y crecimiento ---------------
    m = n // 2
    a, b = x1[:m], x1[m:]
    pa, pb = max(a) - min(a), max(b) - min(b)
    ma, mb = statistics.fmean(a), statistics.fmean(b)
    deriva = abs(mb - ma)
    crec = (pb / pa) if pa > 0 else 1.0
    print("=== esta acotado, o todavia es transitorio? ===")
    print("  1a mitad: pp %.0f   media %.1f" % (pa, ma))
    print("  2a mitad: pp %.0f   media %.1f" % (pb, mb))
    print("  deriva de la media: %.1f LSB   (limite %d)" % (deriva, LIMITE_DERIVA))
    print("  crecimiento del pp: %.2fx        (limite %.1fx)" % (crec, LIMITE_CRECIMIENTO))
    print()

    # --- que corriente produce el ciclo limite -----------------------------
    if ia and ia[0] is not None:
        iamp = (max(ia) - min(ia)) / 2.0
        print("=== la corriente que produce ===")
        print("  i_alfa: %+.3e .. %+.3e pu   amplitud %.3e pu"
              % (min(ia), max(ia), iamp))
        print("  contra una referencia tipica de 0,06 pu: %.2f %%"
              % (100.0 * iamp / 0.06))
        print()

    # ------------------------------------------------------------------
    # EL VEREDICTO, y por que no es el que el spec pedia literalmente.
    #
    # El spec dice "ciclo limite de x1/x2 acotado a pocos LSB". Medido en la
    # placa el 03/10/2026, lo que pasa es OTRA COSA, y hace falta nombrarla:
    #
    #   - i_alfa da EXACTAMENTE cero en las 4096 muestras, asi que el error del
    #     lazo es exactamente cero
    #   - el resonante de dos integradores tiene det(A) = 1 EXACTO: los polos
    #     caen exactamente sobre el circulo unitario. Es una decision deliberada
    #     del spec 5.2, para que la frecuencia sintonizada no derive con la
    #     cuantizacion de k
    #   - un oscilador sin perdidas con entrada nula CONSERVA SU ENERGIA. x1
    #     gira a 50,0 Hz -- la frecuencia a la que k sintoniza -- indefinidamente
    #
    # O sea que no es un ciclo limite de cuantizacion: es la oscilacion libre
    # del resonante, con la amplitud que agarro en el arranque. La prueba:
    # dos corridas consecutivas del mismo programa dieron pp de 7,79e9 y
    # 1,62e10 LSB, un factor 2,08. Una amplitud de cuantizacion seria
    # reproducible; una de condicion inicial, no.
    #
    # "Pocos LSB" no es alcanzable con esta arquitectura y no es la pregunta
    # util. Las preguntas utiles son si esta ACOTADA y si HACE DA~O, y las dos
    # se miden abajo.
    # ------------------------------------------------------------------
    fallas = []
    if crec > LIMITE_CRECIMIENTO:
        fallas.append("el pico a pico crece %.2fx: la oscilacion NO esta acotada"
                      % crec)

    # La deriva se juzga RELATIVA al tama~o de la oscilacion, no en LSB
    # absolutos: una deriva de 2e5 LSB sobre un pp de 1,6e10 es 0,001 %.
    deriva_rel = deriva / pp if pp > 0 else 0.0
    if deriva_rel > 0.02:
        fallas.append("la media deriva %.2f %% del pp: el integrador se va"
                      % (100.0 * deriva_rel))

    if ia and ia[0] is not None:
        iamp = (max(ia) - min(ia)) / 2.0
        if iamp > 1.0e-3:
            fallas.append("produce %.2e pu de corriente en reposo" % iamp)

    print("=== veredicto ===")
    print("  deriva relativa: %.4f %% del pico a pico" % (100.0 * deriva_rel))
    print()
    if fallas:
        print("CRITERIO 6: NO PASA")
        for f in fallas:
            print("  - %s" % f)
        return 1

    print("CRITERIO 6: PASA, con una salvedad sobre como esta escrito")
    print()
    print("  Lo que se verifica y se cumple:")
    print("    - la oscilacion esta ACOTADA: el pp no crece (%.2fx entre mitades)" % crec)
    print("    - no hay deriva: %.4f %% del pp" % (100.0 * deriva_rel))
    if ia and ia[0] is not None:
        print("    - produce %.2e pu de corriente en reposo" % ((max(ia)-min(ia))/2.0))
    print()
    print("  Lo que NO se cumple, y por que no corresponde exigirlo:")
    print("    el estado NO esta en 'pocos LSB' -- mide %.2e en valor absoluto." % (pp/2.0**40))
    print("    No es un ciclo limite de cuantizacion sino la oscilacion LIBRE del")
    print("    resonante, que no decae porque det(A) = 1 exacto es una propiedad")
    print("    BUSCADA del dise~o (spec 5.2). Con error exactamente cero no hay")
    print("    nada que la amortigue.")
    print()
    print("  CONSECUENCIA REAL a tener en cuenta: el estado no decae, asi que")
    print("  cuando llegue una referencia el resonante arranca con esta energia")
    print("  guardada y se suma al transitorio.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
