"""Placa simulada para el visor: imita a serial.Serial lo justo.

Genera tramas con el MISMO formato binario que visor_corriente.c, que pasan por
el mismo Parser, y responde a los comandos con la misma regla: el escalon se
aplica en la muestra 64 de la trama siguiente. La planta es un primer orden de
tau = 20 ms sobre la ENVOLVENTE, en el marco que gira con la referencia (~60 ms
al 5 %, el orden de magnitud del criterio 2). OJO: un primer orden en marco
estacionario no sirve, porque a 50 Hz con tau = 20 ms atenua a 1/|1+jwt| =
0,16 y desfasa 81 grados: es un filtro, no un lazo que sigue. No pretende ser
el lazo real: sirve para ver la figura sin placa.
"""

import cmath
import math
import time

import visor_metricas as VM
import visor_trama as VT

TAU = 0.020
# Techo de corriente de la planta de la placa: 0,113 pu a 50 Hz, escalado con
# 1/|Z(f)| para R = 1,2 ohm y la L efectiva de 24 mH de RL_fase. Medido en la
# placa: 0,06 pu a 100 Hz satura (|i| = 0,0562). La simulacion solo recorta la
# amplitud; no reproduce la deriva de fase que se ve en la placa.
TECHO_50 = 0.1133
R_PLANTA, L_PLANTA = 1.2, 0.024
T_TRAMA = VT.BYTES_TRAMA * 10 / 115200       # lo que tarda en salir por la UART
GAP = int(T_TRAMA * VM.FS)                   # Ts que pasan mientras se transmite


class PlacaSimulada:

    def __init__(self, tiempo_real=True):
        self.tiempo_real = tiempo_real
        self._amp_q = VM.espejo_amp_q824(60000)
        self._f_mhz = 50000
        self._contador = 0
        self._pend = {}
        self._rechazo = False
        self._rx = bytearray()
        self._tx = bytearray()
        self._fase = 0.0
        self._z = complex(self._amp_q / VM.Q24, 0.0)    # envolvente, marco giratorio
        self._proxima = time.monotonic()
        self._alfa = 1.0 - math.exp(-1.0 / (VM.FS * TAU))

    # ---- interfaz de serial.Serial ------------------------------------------
    def write(self, datos):
        self._rx += datos
        while b"\n" in self._rx:
            j = self._rx.index(b"\n")
            linea = self._rx[:j].decode("ascii", errors="replace")
            del self._rx[:j + 1]
            cmd = VT.interpretar_comando(linea)
            if cmd is None:
                self._rechazo = True
            elif cmd[0] == "A":
                self._pend["A"] = VM.espejo_amp_q824(cmd[1])
            else:
                self._pend["F"] = cmd[1] // 1000
        return len(datos)

    def read(self, n):
        if not self._tx:
            if self.tiempo_real:
                ahora = time.monotonic()
                if ahora < self._proxima:
                    time.sleep(min(0.05, self._proxima - ahora))
                    return b""
                self._proxima = ahora + T_TRAMA
            self._tx += VT.codificar(self._trama())
        out = bytes(self._tx[:n])
        del self._tx[:n]
        return out

    def close(self):
        pass

    # ---- la simulacion ------------------------------------------------------
    def _techo(self):
        z = lambda f: abs(complex(R_PLANTA, 2 * math.pi * f * L_PLANTA))
        return TECHO_50 * z(50.0) / z(self._f_mhz / 1000.0)

    def _paso(self):
        """Un Ts. Devuelve (referencia, corriente, saturo) con las senales
        como complejos alfa + j*beta."""
        amp = self._amp_q / VM.Q24
        techo = self._techo()
        self._z += (min(amp, techo) - self._z) * self._alfa
        giro = cmath.exp(1j * self._fase)
        self._fase += 2 * math.pi * (self._f_mhz / 1000.0) / VM.FS
        return amp * giro, self._z * giro, amp > techo

    def _trama(self):
        escalon = bool(self._pend)
        amp_prev, f_prev = self._amp_q, self._f_mhz
        ia, ib, ra, rb = [], [], [], []
        n_sat = 0
        for n in range(VT.N_MUESTRAS):
            if escalon and n == VT.MUESTRA_ESCALON:
                self._amp_q = self._pend.get("A", self._amp_q)
                self._f_mhz = self._pend.get("F", self._f_mhz)
                self._pend = {}
            ref, i, saturo = self._paso()
            n_sat += saturo
            ia.append(int(round(i.real * VM.Q24)))
            ib.append(int(round(i.imag * VM.Q24)))
            ra.append(int(round(ref.real * VM.Q24)))
            rb.append(int(round(ref.imag * VM.Q24)))
        flags = ((VT.FL_ESCALON if escalon else 0) | (VT.FL_RECHAZO if self._rechazo else 0)
                 | (VT.FL_SATURA if n_sat else 0))
        self._rechazo = False
        t = VT.Trama(contador=self._contador, amp_ref=self._amp_q, f_mhz=self._f_mhz,
                     flags=flags, muestra_escalon=VT.MUESTRA_ESCALON if escalon else 0,
                     amp_ref_prev=amp_prev, f_mhz_prev=f_prev, clamp=0,
                     i_alfa=ia, i_beta=ib, ref_alfa=ra, ref_beta=rb, n_sat=n_sat)
        self._contador += 1
        for _ in range(GAP):    # el tiempo que la placa real pasa transmitiendo
            self._paso()
        return t
