import numpy as np

# --- Parámetros ---
NUM_POINTS = 2048  # Número de puntos en la LUT (2^11)
INTEGER_BITS = 7   # Bits para la parte entera (excluyendo el signo)
FRACTIONAL_BITS = 24 # Bits para la parte fraccional
TOTAL_BITS = 1 + INTEGER_BITS + FRACTIONAL_BITS

# --- Generación de la onda senoidal ---
# Genera una onda senoidal completa de 0 a 2*pi
sine_wave_float = np.sin(np.linspace(0, 2 * np.pi, NUM_POINTS, endpoint=False))

# --- Conversión a punto fijo Q8.24 ---
# El valor se escala por 2^FRACTIONAL_BITS
# La salida está normalizada entre +1.0 y -1.0
sine_wave_fixed_point = []
for val in sine_wave_float:
    # Manejo del valor -1.0, que en complemento a 2 requiere un tratamiento especial
    if val == -1.0:
        # Representación de -1 en Qm.n es -(2^(m+n-1))
        # Para Q8.24, sería -2^31
        fixed_val = -2**(TOTAL_BITS - 1)
    else:
        fixed_val = int(round(val * (2**FRACTIONAL_BITS)))
    sine_wave_fixed_point.append(fixed_val)

# --- Generación del archivo VHDL ---
file_content = """
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sine_lut_pkg is
    -- Constantes para la LUT
    constant LUT_ADDR_WIDTH : integer := {addr_width};
    constant LUT_DEPTH      : integer := {depth};
    constant SINE_DATA_WIDTH: integer := {data_width};

    -- Definición del tipo para la tabla de la LUT
    type sine_table_t is array (0 to LUT_DEPTH - 1) of signed(SINE_DATA_WIDTH - 1 downto 0);

    -- Constante con los valores de la onda senoidal
    constant SINE_TABLE : sine_table_t := (
""".format(
    addr_width=int(np.log2(NUM_POINTS)),
    depth=NUM_POINTS,
    data_width=TOTAL_BITS
)

for i, val in enumerate(sine_wave_fixed_point):
    # Formatear el valor como un literal binario de 32 bits
    # Se usa la función to_signed de VHDL para la conversión
    file_content += '        {index} => to_signed({value}, {width})'.format(
        index=i, value=val, width=TOTAL_BITS
    )
    if i == len(sine_wave_fixed_point) - 1:
        file_content += "\n"
    else:
        file_content += ",\n"

file_content += """
    );
end package sine_lut_pkg;
"""

# Guardar el contenido en un archivo VHDL
with open("sine_lut_pkg.vhd", "w") as f:
    f.write(file_content)

print("Archivo 'sine_lut_pkg.vhd' generado exitosamente.")
print(f"Número de puntos: {NUM_POINTS}")
print(f"Formato: Q8.24 ({TOTAL_BITS} bits)")