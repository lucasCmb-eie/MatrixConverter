"""Metricas del visor de corriente y espejo de la aritmetica de set points.

Las metricas se calculan sobre i_alfa/i_beta, no sobre las fases: la planta
simulada son tres RL independientes y deja pasar secuencia cero (medido el
03/10/2026, Io_V +72 % sobre Io_U). Las fases que se dibujan salen de la
Clarke inversa, que es lo que veria una carga real de tres hilos.
"""

import math
from dataclasses import dataclass

import numpy as np

import visor_trama as VT

Q24 = 1 << 24
FS = 10e6 / 2048            # una muestra por Ts = 204,8 us
T_ESTAB = 0.060             # criterio 2: establece al 2 % en menos de 60 ms
AMP_MIN = 1e-4              # por debajo, la fase no esta definida
SQ3_2 = math.sqrt(3) / 2


def a_pu(raw):
    return np.asarray(raw, dtype=np.float64) / Q24


def clarke_inversa(alfa, beta):
    """Inversa de la Clarke de amplitud invariante de TransformadaClark.vhd
    (alfa = 2/3*(U - (V+W)/2), beta = (V-W)/sqrt(3))."""
    return alfa, -0.5 * alfa + SQ3_2 * beta, -0.5 * alfa - SQ3_2 * beta


@dataclass
class Metricas:
    amp: float
    freq: float
    amp_ref: float
    f_ref: float
    err_pct: object             # float, o None con referencia nula
    valida: bool


def _ventana(t):
    """Desde donde medir. Con escalon, recien despues de establecido; y si eso
    deja menos de un ciclo de la nueva f_o, la trama no se mide."""
    if not (t.flags & VT.FL_ESCALON):
        return 0
    inicio = t.muestra_escalon + int(math.ceil(T_ESTAB * FS))
    f_ref = t.f_mhz / 1000.0
    if f_ref <= 0 or (VT.N_MUESTRAS - inicio) < FS / f_ref:
        return None
    return inicio


def metricas(t):
    amp_ref = t.amp_ref / Q24
    f_ref = t.f_mhz / 1000.0
    inicio = _ventana(t)
    if inicio is None:
        return Metricas(math.nan, math.nan, amp_ref, f_ref, None, False)
    a = a_pu(t.i_alfa[inicio:])
    b = a_pu(t.i_beta[inicio:])
    amp = float(np.mean(np.hypot(a, b)))
    if amp < AMP_MIN:
        freq = math.nan
    else:
        fase = np.unwrap(np.arctan2(b, a))
        pendiente = np.polyfit(np.arange(len(fase)), fase, 1)[0]
        freq = float(pendiente * FS / (2 * math.pi))
    err = (amp - amp_ref) / amp_ref * 100.0 if amp_ref > 0 else None
    return Metricas(amp, freq, amp_ref, f_ref, err, True)


def texto_titulo(t, m, perdidas):
    """(texto, alarma). Alarma si CtrlRegs clampeo algo o se rechazo un
    comando: en esos casos la onda puede verse bien y no ser la pedida."""
    if m.valida:
        partes = ["|i| = %.4f pu (ref %.4g" % (m.amp, m.amp_ref)]
        partes[0] += ", err %+.1f %%)" % m.err_pct if m.err_pct is not None else ")"
        partes.append("f = %.2f Hz (ref %.4g)" % (m.freq, m.f_ref)
                      if not math.isnan(m.freq) else "f = -- (ref %.4g)" % m.f_ref)
    else:
        partes = ["escalon: ref %.4g pu, %.4g Hz (se mide en la proxima trama)"
                  % (m.amp_ref, m.f_ref)]
    partes.append("trama #%d" % t.contador)
    if perdidas:
        partes.append("%d perdidas" % perdidas)
    alarma = False
    if t.clamp:
        partes.append("CLAMP 0x%x" % t.clamp)
        alarma = True
    if t.flags & VT.FL_RECHAZO:
        partes.append("comando rechazado")
        alarma = True
    return "   ".join(partes), alarma


def tramas_perdidas(anterior, actual):
    if anterior is None or actual <= anterior:
        return 0                # primera trama, o la placa se reseteo
    return actual - anterior - 1


# ---- espejo de visor_corriente.c, operacion por operacion --------------------

def espejo_amp_q824(micro):
    return (micro * 16777216 + 500000) // 1000000


def espejo_paso_ref(f_mhz):
    p = float(f_mhz) * 4294967296.0 / 1e10
    return int(p + 0.5) * 2048


def espejo_k(f_mhz):
    x = math.pi * (f_mhz / 1000.0) * (2048.0 / 10e6)
    x2 = x * x
    s = x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0))
    return int(2.0 * s * 16777216.0 + 0.5)
