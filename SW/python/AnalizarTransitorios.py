"""Criterios 2, 3 y 4 del spec 7.4 sobre los CSV de las corridas."""
import csv, math, sys

Q = 2**24
TS = 204.8e-6


def leer(d):
    return list(csv.DictReader(open(d + "/control_corriente.csv")))


def mod(r, a, b):
    return math.hypot(int(r[a]) / Q, int(r[b]) / Q)


def env(f, i0, i1):
    """Envolvente del vector de corriente entre dos indices de Ts."""
    return [(int(r["ts"]), mod(r, "i_a", "i_b"), mod(r, "ref_a", "ref_b"))
            for r in f if i0 <= int(r["ts"]) <= i1]


def criterio2(d):
    f = leer(d)
    print("=== Criterio 2: escalon de amplitud 0,05 -> 0,15 pu en ts=488 ===")
    tras = env(f, 488, 488 + int(60e-3 / TS))
    if not tras:
        print("  sin datos"); return
    pico = max(x[1] for x in tras)
    print("  objetivo 0,15   pico %.5f  -> sobrepico %.2f %%  (criterio < 20 %%)"
          % (pico, 100 * (pico - 0.15) / 0.15))
    cola = tras[-50:]
    fin = sum(x[1] for x in cola) / len(cola)
    print("  a los 60 ms: |i| medio %.5f  -> error %.2f %%  (criterio < 2 %%)"
          % (fin, 100 * abs(fin - 0.15) / 0.15))


def criterio3(d):
    f = leer(d)
    print("=== Criterio 3: escalon de f_o 50 -> 30 Hz en ts=732 ===")
    tras = env(f, 732, 732 + int(60e-3 / TS))
    if not tras:
        print("  sin datos"); return
    minimo = min(x[1] for x in tras)
    cola = tras[-50:]
    fin = sum(x[1] for x in cola) / len(cola)
    ref = sum(x[2] for x in cola) / len(cola)
    print("  |i| minimo durante el transitorio %.5f (si cae a ~0 se perdio "
          "el sincronismo)" % minimo)
    print("  a los 60 ms: |i| %.5f vs |ref| %.5f -> error %.2f %%  (criterio < 2 %%)"
          % (fin, ref, 100 * abs(fin - ref) / ref if ref else 0))
    # frecuencia efectiva: cuantos Ts tarda el angulo en dar una vuelta
    ang = [(int(r["ts"]), int(r["al_o"])) for r in f if int(r["ts"]) > 900]
    vueltas = sum(1 for i in range(1, len(ang)) if ang[i][1] < ang[i - 1][1])
    dur = (ang[-1][0] - ang[0][0]) * TS
    if dur > 0:
        print("  frecuencia de al_o despues del escalon: %.2f Hz (esperado 30)"
              % (vueltas / dur))


def criterio4(da, db):
    print("=== Criterio 4: anti-windup diferencial ===")
    print("    sobrecomando a 0,50 pu (max alcanzable 0,219) en ts=488,")
    print("    vuelta a 0,10 en ts=976; se compara el pico al desaturar.")
    out = {}
    for etiqueta, d in (("con freeze", da), ("sin freeze", db)):
        f = leer(d)
        tras = env(f, 976, 976 + int(80e-3 / TS))
        if not tras:
            print("  %s: sin datos" % etiqueta); continue
        pico = max(x[1] for x in tras)
        sat = sum(1 for r in f if 488 <= int(r["ts"]) <= 976 and r["sat"] == "1")
        out[etiqueta] = pico
        print("  %-11s pico al desaturar %.5f  (objetivo 0,10)  "
              "saturo %d Ts durante el sobrecomando" % (etiqueta, pico, sat))
    if len(out) == 2:
        a, b = out["con freeze"], out["sin freeze"]
        print("  -> el freeze %s el sobrepico (%.5f vs %.5f, %+.1f %%)"
              % ("REDUCE" if a < b else "NO reduce", a, b, 100 * (a - b) / b))


base = sys.argv[1] if len(sys.argv) > 1 else "."
criterio2(base + "/crit2"); print()
criterio3(base + "/crit3"); print()
criterio4(base + "/crit4a", base + "/crit4b")
