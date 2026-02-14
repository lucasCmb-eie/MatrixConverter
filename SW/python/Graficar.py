import serial
import struct
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from collections import deque

# --- CONFIGURACIÓN ---
PUERTO_COM = 'COM12'   # <--- Verifica tu puerto
BAUD_RATE = 115200
ENDIANNESS = '<'      # Little Endian (Lo usual si envías b[0] primero)

# Rango Y para Q8.24 normalizado
# Como 1.0 es el máximo en Q8.24 (aprox), ponemos un rango cómodo
RANGO_Y = (-1.5, 1.5) 

def leer_dato_sincronizado(ser):
    """
    Busca la secuencia 0xAA -> 0xBB.
    Lee 4 bytes, los interpreta como entero y los convierte a float Q8.24.
    """
    while True:
        # 1. Buscar primer byte de cabecera (0xAA)
        byte1 = ser.read(1)
        if len(byte1) == 0: return None # Timeout

        if ord(byte1) == 0xAA:
            # 2. Buscar segundo byte de cabecera (0xBB)
            byte2 = ser.read(1)
            if len(byte2) == 0: return None
            
            if ord(byte2) == 0xBB:
                # 3. Leer los 4 bytes de datos
                data = ser.read(4)
                if len(data) == 4:
                    # A. Desempaquetar como entero con signo de 32 bits
                    raw_int = struct.unpack(ENDIANNESS + 'i', data)[0]
                    
                    # B. Convertir formato Q8.24 a Float real
                    # Dividimos por 2^24 (16,777,216)
                    val_float = raw_int / 16777216.0
                    return val_float
            else:
                # Si falla la secuencia (ej: AA CC), seguimos buscando
                pass

def graficar(ser):
    # Buffer para 200 puntos
    data_buffer = deque([0.0] * 200, maxlen=200)
    
    fig, ax = plt.subplots()
    line, = ax.plot(data_buffer)
    
    # Configuramos el eje Y con el rango acotado
    ax.set_ylim(*RANGO_Y)
    ax.grid(True)
    ax.set_title("Señal Q8.24 (Sincronizada AA BB)")
    ax.set_ylabel("Amplitud (Float)")

    def update(frame):
        # Leemos el buffer del puerto serial hasta vaciarlo o llegar a un límite
        # Esto previene el lag si llegan datos muy rápido
        datos_leidos = 0
        while ser.in_waiting >= 6: # 2 Header + 4 Data
            val = leer_dato_sincronizado(ser)
            if val is not None:
                data_buffer.append(val)
                datos_leidos += 1
            
            if datos_leidos > 50: break # Protección contra bloqueo de GUI
        
        line.set_ydata(data_buffer)
        return line,

    ani = animation.FuncAnimation(fig, update, interval=10, blit=True)
    plt.show()

if __name__ == "__main__":
    try:
        ser = serial.Serial(PUERTO_COM, BAUD_RATE, timeout=0.1)
        ser.reset_input_buffer()
        print(f"Conectado a {PUERTO_COM}. Esperando cabecera 0xAA 0xBB...")
        graficar(ser)
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()