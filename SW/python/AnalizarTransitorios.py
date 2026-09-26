"""Criterios 1 a 4 del spec 7.4 sobre los CSV que escribe tb_criterios.vhd.

Uso:  python AnalizarTransitorios.py <directorio con crit2/ crit3/ crit4a/ crit4b/>

Devuelve codigo de salida 1 si algun criterio falla, para que sea usable como
regresion y no solo como algo que un humano lee.

Los objetivos NO van escritos a mano: se leen de la propia referencia del CSV.
Antes estaban hardcodeados y quedaron desincronizados del TB cuando el escalon
del criterio 2 bajo de 0,15 a 0,10 pu, con lo que el script reportaba una falla
falsa.

Los criterios 5 y 6 no estan aca: se miden sobre la placa.
"""

import csv
import math
import os
import sys

Q = 2**24
TS = 204.8e-6
W50 = 2 * math.pi * 50.0

fallas = []


def leer(d):
    with open(os.path.join(d, "control_corriente.csv")) as fh:
        return list(csv.DictReader(fh))


def mod(r, a, b):
    return math.hypot(int(r[a]) / Q, int(r[b]) / Q)


def ventana(f, t0, t1):
    return [r for r in f if t0 <= int(r["ts"]) <= t1]


def objetivo(f, ts_desde):
    """El objetivo sale de la REFERENCIA del propio CSV, no de una constante."""
    d = ventana(f, ts_desde + 200, ts_desde + 400)
    if not d:
        d = f[-100:]
    return math.sqrt(sum(mod(r, "ref_a", "ref_b") ** 2 for r in d) / len(d))


def chequear(nombre, valor, limite, unidad="%"):
    ok = valor < limite
    print("    %-34s %8.3f %s   (< %.3f)  %s"
          % (nombre, valor, unidad, limite, "OK" if ok else "FALLA"))
    if not ok:
        fallas.append(nombre)
    return ok


def frecuencia(f, t0, t1):
    """Por acumulacion de fase de la REFERENCIA, que es limpia por
    construccion. Contar vueltas de al_o no sirve: al_o sale del CORDIC sobre
    v*, tiene ruido de cuantizacion, y cualquier no-monotonia cerca del wrap
    suma una vuelta espuria."""
    d = ventana(f, t0, t1)
    ang = [math.atan2(int(r["ref_b"]) / Q, int(r["ref_a"]) / Q) for r in d]
    tot = 0.0
    for i in range(1, len(ang)):
        dd = ang[i] - ang[i - 1]
        while dd > math.pi:
            dd -= 2 * math.pi
        while dd < -math.pi:
            dd += 2 * math.pi
        tot += dd
    return tot / (2 * math.pi) / ((len(ang) - 1) * TS)


def criterio1(d):
    print("=== Criterio 1: regimen (cola del escenario del criterio 2) ===")
    f = leer(d)
    cola = f[-300:]
    rr = math.sqrt(sum(mod(r, "ref_a", "ref_b") ** 2 for r in cola) / len(cola))
    ri = math.sqrt(sum(mod(r, "i_a", "i_b") ** 2 for r in cola) / len(cola))
    ang = []
    for r in cola:
        a = math.degrees(math.atan2(int(r["i_b"]) / Q, int(r["i_a"]) / Q)
                         - math.atan2(int(r["ref_b"]) / Q, int(r["ref_a"]) / Q))
        ang.append((a + 180) % 360 - 180)
    print("    objetivo leido del CSV: %.5f pu" % rr)
    chequear("error de amplitud", 100 * abs(ri - rr) / rr, 1.0)
    chequear("error de fase", abs(sum(ang) / len(ang)), 1.0, "deg")
    print("    (el retardo inherente de 1 Ts a 50 Hz es %.3f deg; el "
          "resonante lo compensa)" % math.degrees(W50 * TS))


def criterio2(d):
    print("=== Criterio 2: escalon de amplitud en ts=488 ===")
    f = leer(d)
    obj = objetivo(f, 488)
    tras = ventana(f, 488, 488 + int(60e-3 / TS))
    print("    objetivo leido del CSV: %.5f pu" % obj)
    pico = max(mod(r, "i_a", "i_b") for r in tras)
    fin = sum(mod(r, "i_a", "i_b") for r in tras[-50:]) / 50
    chequear("sobrepico", max(0.0, 100 * (pico - obj) / obj), 20.0)
    chequear("error a 60 ms", 100 * abs(fin - obj) / obj, 2.0)
    print("    saturo %d de %d Ts de la ventana"
          % (sum(1 for r in tras if r["sat"] == "1"), len(tras)))


def criterio3(d):
    print("=== Criterio 3: escalon de f_o en ts=732 ===")
    f = leer(d)
    f_antes = frecuencia(f, 300, 700)
    f_despues = frecuencia(f, 900, 1400)
    print("    frecuencia de la referencia: %.3f -> %.3f Hz" % (f_antes, f_despues))
    tras = ventana(f, 732, 732 + int(60e-3 / TS))
    minimo = min(mod(r, "i_a", "i_b") for r in tras)
    obj = objetivo(f, 732)
    fin = sum(mod(r, "i_a", "i_b") for r in tras[-50:]) / 50
    chequear("caida de |i| en el transitorio", 100 * (1 - minimo / obj), 50.0)
    chequear("error a 60 ms", 100 * abs(fin - obj) / obj, 2.0)


def criterio4(da, db):
    print("=== Criterio 4: anti-windup diferencial ===")
    print("    El PICO al desaturar NO discrimina: q esta clampeado a q_max en")
    print("    los dos casos. Lo que el windup cuesta es TIEMPO.")
    res = {}
    for etiqueta, d in (("con freeze", da), ("sin freeze", db)):
        f = leer(d)
        tras = ventana(f, 976, 10**9)
        obj = objetivo(f, 976)
        t = None
        for r in tras:
            if abs(mod(r, "i_a", "i_b") - obj) / obj < 0.05:
                t = (int(r["ts"]) - 976) * TS * 1e3
                break
        # Ts saturados DESPUES del comando, no durante el sobrecomando.
        nsat = sum(1 for r in tras if r["sat"] == "1")
        res[etiqueta] = (t, nsat)
        print("    %-11s recupera al 5%% en %-12s  saturado despues: %d Ts"
              % (etiqueta, ("%.1f ms" % t) if t is not None else "NUNCA", nsat))
    (ta, sa), (tb, sb) = res["con freeze"], res["sin freeze"]
    ok = sa < sb and (tb is None or (ta is not None and ta <= tb))
    print("    %s" % ("OK: el freeze acorta la recuperacion" if ok
                      else "FALLA: el freeze no mejora nada"))
    if not ok:
        fallas.append("anti-windup diferencial")


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "."
    criterio1(os.path.join(base, "crit2"))
    print()
    criterio2(os.path.join(base, "crit2"))
    print()
    criterio3(os.path.join(base, "crit3"))
    print()
    criterio4(os.path.join(base, "crit4a"), os.path.join(base, "crit4b"))
    print()
    if fallas:
        print("FALLAN %d criterios: %s" % (len(fallas), ", ".join(fallas)))
        return 1
    print("Todos los criterios de simulacion pasan.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
