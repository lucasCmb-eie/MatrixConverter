#!/usr/bin/env python3
"""Visor de la corriente de la planta RL, con datos de la placa.

    python SW/python/VisorCorriente.py COM12
    python SW/python/VisorCorriente.py --simular
    python SW/python/VisorCorriente.py --simular --png visor.png --tramas 3 --comando "A 0.10"

Antes, con la placa: programar con
    powershell -ExecutionPolicy Bypass -File SW\\ps\\programar_y_capturar.ps1 -SoloProgramar
(el .elf tiene que ser el de visor_corriente.c, ver ese archivo).

Arriba: las tres fases reconstruidas desde i_alfa/i_beta, y la referencia
punteada desde ref_alfa/ref_beta capturadas (los set points no dan la fase del
NCO). Abajo: la historia de amplitud y frecuencia, un punto por trama. Las cajas
de texto mandan un escalon que la placa aplica en la muestra 64 de la trama
siguiente, asi esa trama muestra el antes y el despues.

El ritmo de refresco lo pone la UART: 8236 bytes a 115200 son ~0,72 s.
"""

import argparse
import collections
import queue
import sys
import threading
import time

import numpy as np

import visor_metricas as VM
import visor_trama as VT

HISTORIA_S = 30.0
SPAN_AMP = 0.01             # pu: rango minimo del eje de |i| en la historia
SPAN_F = 2.0                # Hz: idem para f


def limites(valores, span_min):
    """Limites de un eje de la historia, con un rango MINIMO. Sin esto, con f
    constante el autoescalado hace zoom sobre el ruido numerico (1e-7 Hz) y el
    eje salta en cada trama."""
    v = np.asarray(valores, dtype=float)
    v = v[~np.isnan(v)]
    lo, hi = float(v.min()), float(v.max())
    margen = 0.1 * (hi - lo)
    lo, hi = lo - margen, hi + margen
    if hi - lo < span_min:
        centro = (hi + lo) / 2
        lo, hi = centro - span_min / 2, centro + span_min / 2
    return lo, hi


def elegir_trama(tramas):
    """Cual dibujar de las que se juntaron mientras la figura estaba ocupada:
    la mas nueva, salvo que alguna tenga el escalon. La trama del escalon es
    la razon de ser del visor; perderla por arrastrar la ventana no."""
    con_escalon = [t for t in tramas if t.flags & VT.FL_ESCALON]
    return (con_escalon or tramas)[-1]


def abrir(args):
    if args.simular:
        import visor_sim
        return visor_sim.PlacaSimulada(tiempo_real=not args.png)
    import serial
    try:
        return serial.Serial(args.puerto, args.baud, timeout=0.1)
    except serial.SerialException as e:
        print("NO se pudo abrir %s: %s" % (args.puerto, e))
        print("Hay un PuTTY o el Serial Terminal de Vitis abierto? El puerto es exclusivo.")
        return None


def lector(fuente, cola, parar):
    """Hilo: lee la UART sin pausa para que el buffer del driver no desborde
    mientras matplotlib dibuja."""
    parser = VT.Parser()
    while not parar.is_set():
        try:
            datos = fuente.read(4096)
        except Exception as e:          # puerto desenchufado, etc.
            print("# lector: %s" % e)
            break
        tramas, lineas = parser.alimentar(datos)
        for l in lineas:
            print(l)
        for t in tramas:
            cola.put(t)


class Vista:

    def __init__(self, plt, interactiva, mandar):
        self.plt = plt
        self.mandar = mandar
        self.fig = plt.figure(figsize=(11, 7.5))
        gs = self.fig.add_gridspec(2, 1, height_ratios=[3, 1.3], hspace=0.35,
                                   bottom=0.17, top=0.92)
        self.ax = self.fig.add_subplot(gs[0])
        self.axh = self.fig.add_subplot(gs[1])
        self.axf = self.axh.twinx()

        t_ms = np.arange(VT.N_MUESTRAS) / VM.FS * 1e3
        self.t_ms = t_ms
        self.l_i, self.l_r = [], []
        for nombre, c in zip("UVW", ["C0", "C1", "C2"]):
            self.l_i += self.ax.plot(t_ms, np.zeros_like(t_ms), c, lw=1.4, label="i_" + nombre)
            self.l_r += self.ax.plot(t_ms, np.zeros_like(t_ms), c, lw=0.9, ls="--")
        self.l_esc = self.ax.axvline(VT.MUESTRA_ESCALON / VM.FS * 1e3, color="k",
                                     ls=":", visible=False)
        self.ax.set_xlabel("t [ms]")
        self.ax.set_ylabel("i [pu]")
        self.ax.set_xlim(0, t_ms[-1])
        self.ax.grid(True, alpha=0.3)
        self.ax.legend(loc="upper right", fontsize=8, ncol=3,
                       title="punteada: referencia", title_fontsize=8)

        self.hist = collections.deque()
        self.t0 = time.monotonic()
        self.lh_amp, = self.axh.plot([], [], "C0.-", lw=1, ms=3, label="|i|")
        self.lh_aref, = self.axh.plot([], [], "C0--", lw=0.8, label="ref |i|")
        self.lh_f, = self.axf.plot([], [], "C3.-", lw=1, ms=3, label="f")
        self.lh_fref, = self.axf.plot([], [], "C3--", lw=0.8, label="ref f")
        self.axh.set_xlabel("t [s]")
        self.axh.set_ylabel("|i| [pu]", color="C0")
        self.axf.set_ylabel("f [Hz]", color="C3")
        self.axh.grid(True, alpha=0.3)

        self.titulo = self.fig.suptitle("esperando la primera trama...")
        self.cajas = {}
        if interactiva:
            from matplotlib.widgets import TextBox
            for letra, etiqueta, x in [("A", "I ref [pu] ", 0.17), ("F", "f_o [Hz] ", 0.58)]:
                caja = TextBox(self.fig.add_axes([x, 0.03, 0.14, 0.05]), etiqueta)
                caja.on_submit(lambda texto, l=letra: self._enviar(l, texto))
                self.cajas[letra] = caja

        self.anterior = None
        self.perdidas = 0

    def _enviar(self, letra, texto):
        """Manda SOLO con Enter. matplotlib dispara 'submit' tambien al perder
        el foco (stop_typing, o sea cualquier clic fuera de la caja) y desde
        set_val; los dos llegan con capturekeystrokes en False, y Enter llega
        con True. Sin este filtro, un clic en el grafico mandaba lo que hubiera
        en la caja -- "0.0" a medio escribir bajaba la corriente a cero."""
        caja = self.cajas[letra]
        if not caja.capturekeystrokes:
            return
        # Enter no saca el foco: sin esto la caja seguiria "editandose", no se
        # resincronizaria y el proximo clic volveria a mandar.
        caja.eventson = False
        try:
            caja.stop_typing()
        finally:
            caja.eventson = True
        try:
            x = VT.numero_de_texto(texto)
            cmd = VT.comando_amp(x) if letra == "A" else VT.comando_frec(x)
        except ValueError as e:
            caja.ax.set_facecolor("#ffc8c8")
            print("# rechazado en la PC: %s" % e)
            return
        caja.ax.set_facecolor("white")
        self.mandar(cmd)

    def _sincronizar_cajas(self, t):
        """Las cajas muestran lo que tiene la placa, salvo mientras se edita.
        Una edicion abandonada (clic afuera sin Enter) vuelve al valor real.
        set_val dispara 'submit', pero _enviar lo ignora: no hay foco."""
        valores = {"A": "%.4g" % (t.amp_ref / VM.Q24), "F": "%.4g" % (t.f_mhz / 1000.0)}
        for letra, caja in self.cajas.items():
            if not caja.capturekeystrokes and caja.text != valores[letra]:
                caja.set_val(valores[letra])

    def procesar(self, tramas):
        """Todas las tramas llegadas cuentan para 'perdidas' y para la historia;
        se dibuja una sola, la de elegir_trama()."""
        ahora = time.monotonic() - self.t0
        for t in tramas:
            self.perdidas += VM.tramas_perdidas(self.anterior, t.contador)
            self.anterior = t.contador
            m = VM.metricas(t)
            if m.valida:
                self.hist.append((ahora, m.amp, m.amp_ref, m.freq, m.f_ref))
        self.dibujar(elegir_trama(tramas), ahora)

    def dibujar(self, t, ahora):
        m = VM.metricas(t)
        for linea, y in zip(self.l_i, VM.clarke_inversa(VM.a_pu(t.i_alfa), VM.a_pu(t.i_beta))):
            linea.set_ydata(y)
        for linea, y in zip(self.l_r, VM.clarke_inversa(VM.a_pu(t.ref_alfa), VM.a_pu(t.ref_beta))):
            linea.set_ydata(y)
        self.l_esc.set_visible(bool(t.flags & VT.FL_ESCALON))
        tope = max(0.02, 1.15 * max(np.max(np.abs(l.get_ydata())) for l in self.l_i + self.l_r))
        self.ax.set_ylim(-tope, tope)

        while self.hist and self.hist[0][0] < ahora - HISTORIA_S:
            self.hist.popleft()
        if self.hist:
            h = np.array(self.hist, dtype=float)
            self.lh_amp.set_data(h[:, 0], h[:, 1])
            self.lh_aref.set_data(h[:, 0], h[:, 2])
            self.lh_f.set_data(h[:, 0], h[:, 3])
            self.lh_fref.set_data(h[:, 0], h[:, 4])
            self.axh.set_ylim(*limites(h[:, 1:3].ravel(), SPAN_AMP))
            self.axf.set_ylim(*limites(h[:, 3:5].ravel(), SPAN_F))
            self.axh.set_xlim(max(0.0, ahora - HISTORIA_S), max(ahora, 1.0))

        texto, alarma = VM.texto_titulo(t, m, self.perdidas)
        self.titulo.set_text(texto)
        self.titulo.set_color("red" if alarma else "black")
        self._sincronizar_cajas(t)


def correr_png(args, fuente):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    vista = Vista(plt, interactiva=False, mandar=fuente.write)
    parser = VT.Parser()
    hechas = 0
    limite = time.monotonic() + 30.0 * args.tramas
    while hechas < args.tramas and time.monotonic() < limite:
        tramas, lineas = parser.alimentar(fuente.read(4096))
        for l in lineas:
            print(l)
        for t in tramas:
            vista.procesar([t])
            hechas += 1
            if hechas == 1:
                for c in args.comando:
                    if VT.interpretar_comando(c) is None:
                        print("comando invalido: %r" % c)
                        return 1
                    fuente.write(c.encode("ascii") + b"\n")
    if hechas < args.tramas:
        print("llegaron %d de %d tramas" % (hechas, args.tramas))
        return 1
    vista.fig.savefig(args.png, dpi=100)
    print("figura -> %s" % args.png)
    return 0


def correr_interactivo(fuente):
    import matplotlib.pyplot as plt
    cola = queue.Queue()
    parar = threading.Event()
    hilo = threading.Thread(target=lector, args=(fuente, cola, parar), daemon=True)
    hilo.start()
    vista = Vista(plt, interactiva=True, mandar=fuente.write)
    plt.show(block=False)
    try:
        while plt.fignum_exists(vista.fig.number):
            llegadas = []
            while True:
                try:
                    llegadas.append(cola.get_nowait())
                except queue.Empty:
                    break
            if llegadas:
                vista.procesar(llegadas)
            plt.pause(0.05)
    except KeyboardInterrupt:
        pass
    finally:
        parar.set()
        hilo.join(timeout=1.0)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("puerto", nargs="?")
    ap.add_argument("--simular", action="store_true")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--png")
    ap.add_argument("--tramas", type=int, default=3)
    ap.add_argument("--comando", action="append", default=[])
    args = ap.parse_args(argv)
    if not args.simular and not args.puerto:
        print("falta el puerto (ej. COM12) o --simular")
        return 1
    fuente = abrir(args)
    if fuente is None:
        return 1
    try:
        return correr_png(args, fuente) if args.png else correr_interactivo(fuente)
    finally:
        fuente.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
