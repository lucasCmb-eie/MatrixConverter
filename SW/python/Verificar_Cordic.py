import math

def calcular_valor_esperado(x, y, bits_salida=11):
    """
    Calcula el valor entero esperado para un CORDIC con salida BAM (Binary Angle Measurement).
    """
    # 1. Calcular el ángulo real en radianes (rango -PI a +PI)
    rads = math.atan2(y, x)
    
    # 2. Convertir a grados para referencia visual
    grados = math.degrees(rads)
    
    # 3. Normalizar a 0 a 2*PI (para coincidir con tu VHDL unsigned)
    # Si el ángulo es negativo, le sumamos 360 grados (2*PI)
    rads_norm = rads
    if rads_norm < 0:
        rads_norm += 2 * math.pi
        
    # 4. Escalar al ancho de bits (BAM - Binary Angle Measurement)
    # Rango total: 2^bits
    max_count = 2 ** bits_salida
    
    # Fórmula: (radianes / 2*PI) * total_cuentas
    valor_entero = (rads_norm / (2 * math.pi)) * max_count
    
    # Redondeamos al entero más cercano
    valor_final = int(round(valor_entero))
    
    # Manejo del desbordamiento (wrap-around)
    # Si da 2048, en 11 bits eso es 0
    if valor_final == max_count:
        valor_final = 0

    return rads, grados, valor_final

# --- PRUEBA CON TUS VALORES ---
print("--- Verificador de CORDIC ---")
print(f"Resolución: 11 bits (0 - 2047)\n")

while True:
    try:
        s_x = input("Ingresa X (o 'q' para salir): ")
        if s_x.lower() == 'q': break
        x = float(s_x)
        
        y = float(input("Ingresa Y: "))
        
        rads, degs, entero = calcular_valor_esperado(x, y)
        
        print(f"\nResultados para X={x}, Y={y}:")
        print(f"  -> Ángulo Real (rads): {rads:.4f}")
        print(f"  -> Ángulo Real (deg):  {degs:.2f}°")
        print(f"  -> VALOR FPGA (dec):   {entero}")
        print(f"  -> VALOR FPGA (bin):   {entero:011b}")
        print("-" * 30)
        
    except ValueError:
        print("Por favor ingresa números válidos.")