"""Formato de trama del visor de corriente, el parser y los comandos.

ESPEJO de SW/ps/visor_corriente.c: el formato y la aritmetica de los comandos
estan definidos ALLA y replicados aca. Si se cambia uno, se cambia el otro.

Trama (placa -> PC), palabras u32 little-endian:

     0        sincronismo 0xA55A5AA5
     1        contador de trama
     2        amp_ref vigente al final de la trama (Q8.24)
     3        f_o vigente al final, en mHz
     4        flags: bit0 hubo escalon, bit1 se rechazo un comando
     5        muestra del escalon (64), 0 si no hubo
     6        amp_ref previo al escalon
     7        f_o previo al escalon (mHz)
     8        o_clamp de CtrlRegs (ranura 3, 16 bits bajos, sticky)
     9        N (512)
    10..      N cuaternas i_alfa, i_beta, ref_alfa, ref_beta (Q8.24 con signo)
    10+4N     checksum: suma u32 de las palabras 1 .. 10+4N-1

Comandos (PC -> placa), lineas ASCII:  "A <pu>\\n"  y  "F <Hz>\\n".
"""

import struct
from dataclasses import dataclass, field

SYNC = 0xA55A5AA5
SYNC_BYTES = struct.pack("<I", SYNC)
N_MUESTRAS = 512
N_CANALES = 4
N_ENCAB = 10
PALABRAS_TRAMA = N_ENCAB + N_CANALES * N_MUESTRAS + 1
BYTES_TRAMA = 4 * PALABRAS_TRAMA
MUESTRA_ESCALON = 64

FL_ESCALON = 1
FL_RECHAZO = 2

A_MAX_MICRO = 110000            # 0,11 pu
F_MIN_MICRO = 5000000           # 5 Hz
F_MAX_MICRO = 100000000         # 100 Hz


@dataclass
class Trama:
    contador: int
    amp_ref: int
    f_mhz: int
    flags: int
    muestra_escalon: int
    amp_ref_prev: int
    f_mhz_prev: int
    clamp: int
    i_alfa: list = field(repr=False)
    i_beta: list = field(repr=False)
    ref_alfa: list = field(repr=False)
    ref_beta: list = field(repr=False)


def a_signed32(u):
    return u - (1 << 32) if u & 0x80000000 else u


def codificar(t):
    """La trama tal como la manda el PS. La usa la placa simulada y los tests."""
    pal = [t.contador, t.amp_ref, t.f_mhz, t.flags, t.muestra_escalon,
           t.amp_ref_prev, t.f_mhz_prev, t.clamp, N_MUESTRAS]
    for n in range(N_MUESTRAS):
        pal += [t.i_alfa[n], t.i_beta[n], t.ref_alfa[n], t.ref_beta[n]]
    pal = [p & 0xFFFFFFFF for p in pal]
    suma = sum(pal) & 0xFFFFFFFF
    return SYNC_BYTES + struct.pack("<%dI" % (len(pal) + 1), *pal, suma)


def _decodificar(b):
    """b son exactamente BYTES_TRAMA bytes con el checksum ya verificado."""
    pal = struct.unpack("<%dI" % PALABRAS_TRAMA, b)
    cuerpo = [a_signed32(p) for p in pal[N_ENCAB:N_ENCAB + N_CANALES * N_MUESTRAS]]
    return Trama(contador=pal[1], amp_ref=pal[2], f_mhz=pal[3], flags=pal[4],
                 muestra_escalon=pal[5], amp_ref_prev=pal[6], f_mhz_prev=pal[7],
                 clamp=pal[8] & 0xFFFF,
                 i_alfa=cuerpo[0::4], i_beta=cuerpo[1::4],
                 ref_alfa=cuerpo[2::4], ref_beta=cuerpo[3::4])


class Parser:
    """Arma tramas a partir de un flujo de bytes cortado en cualquier lado.

    Ante cualquier inconsistencia (N invalido, checksum malo) descarta UN byte
    y vuelve a buscar el sincronismo: asi engancharse a mitad de una trama, o
    recibir el banner de texto del PS, nunca lo deja desalineado.
    """

    def __init__(self):
        self._buf = bytearray()
        self._texto = bytearray()

    def alimentar(self, datos):
        self._buf += datos
        tramas = []
        while True:
            i = self._buf.find(SYNC_BYTES)
            if i < 0:
                # Puede haber un sincronismo partido al final: se guarda SOLO
                # el sufijo que coincide con un prefijo del sincronismo. Guardar
                # siempre 3 bytes retendria el '\r\n' de una linea de texto.
                k = next((kk for kk in (3, 2, 1)
                          if self._buf.endswith(SYNC_BYTES[:kk])), 0)
                corte = len(self._buf) - k
                self._texto += self._buf[:corte]
                del self._buf[:corte]
                break
            self._texto += self._buf[:i]
            del self._buf[:i]
            if len(self._buf) < 4 * N_ENCAB:
                break
            n = struct.unpack_from("<I", self._buf, 4 * 9)[0]
            if n != N_MUESTRAS:
                del self._buf[:1]
                continue
            if len(self._buf) < BYTES_TRAMA:
                break
            pal = struct.unpack_from("<%dI" % PALABRAS_TRAMA, self._buf)
            if (sum(pal[1:-1]) & 0xFFFFFFFF) != pal[-1]:
                del self._buf[:1]
                continue
            tramas.append(_decodificar(bytes(self._buf[:BYTES_TRAMA])))
            del self._buf[:BYTES_TRAMA]
        return tramas, self._lineas()

    def _lineas(self):
        lineas = []
        while True:
            j = self._texto.find(b"\n")
            if j < 0:
                break
            l = self._texto[:j].decode("ascii", errors="replace").strip()
            del self._texto[:j + 1]
            if l.startswith("#"):
                lineas.append(l)
        if len(self._texto) > 4096:     # basura sin '\n': que no crezca sin fin
            del self._texto[:-256]
        return lineas


def parsear_micro(s):
    """ESPEJO de parsear_micro() en visor_corriente.c.

    "<1..3 digitos>[.<1..6 digitos>]" con espacios o '\\r' alrededor, a un
    entero escalado por 1e6. Sin signo, sin exponente, sin coma: la coma la
    traduce la PC antes de mandar.
    """
    s = s.strip(" \r")
    ent, punto, frac = s.partition(".")
    if not (1 <= len(ent) <= 3 and ent.isdigit() and ent.isascii()):
        return None
    if punto and not (1 <= len(frac) <= 6 and frac.isdigit() and frac.isascii()):
        return None
    return int(ent) * 1000000 + int((frac or "0").ljust(6, "0"))


def interpretar_comando(linea):
    """ESPEJO de procesar_linea() en visor_corriente.c."""
    if len(linea) < 3 or linea[1] != " " or linea[0] not in "AF":
        return None
    v = parsear_micro(linea[2:])
    if v is None:
        return None
    if linea[0] == "A" and v <= A_MAX_MICRO:
        return ("A", v)
    if linea[0] == "F" and F_MIN_MICRO <= v <= F_MAX_MICRO:
        return ("F", v)
    return None


def numero_de_texto(s):
    """Lo que el usuario escribe en una caja: acepta '0,08' igual que '0.08'."""
    return float(s.strip().replace(",", "."))


def comando_amp(x):
    if not (0.0 <= x <= A_MAX_MICRO / 1e6):
        raise ValueError("amplitud fuera de [0, %.2f] pu" % (A_MAX_MICRO / 1e6))
    return b"A %.6f\n" % x


def comando_frec(f):
    if not (F_MIN_MICRO / 1e6 <= f <= F_MAX_MICRO / 1e6):
        raise ValueError("frecuencia fuera de [%g, %g] Hz" % (F_MIN_MICRO / 1e6, F_MAX_MICRO / 1e6))
    return b"F %.6f\n" % f
