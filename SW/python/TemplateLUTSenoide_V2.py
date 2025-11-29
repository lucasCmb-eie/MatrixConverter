import numpy as np

# --- 1. Configuración del Formato (Q3.29) ---
NUM_POINTS = 2048       # 2^11
INTEGER_BITS = 2        # Bits enteros (sin contar el signo). Rango aprox +/- 4
FRACTIONAL_BITS = 29    # Precisión extrema
TOTAL_BITS = 1 + INTEGER_BITS + FRACTIONAL_BITS # Total 32 bits

# Nombre del archivo y del paquete
PKG_NAME = "sine_lut_pkg"
FILE_NAME = "sine_lut_pkg.vhd"

# --- 2. Generación de la onda ---
# Generamos la onda senoidal perfecta
sine_wave_float = np.sin(np.linspace(0, 2 * np.pi, NUM_POINTS, endpoint=False))

# --- 3. Conversión a Punto Fijo ---
sine_wave_fixed = []
min_val_allowed = -(2**(TOTAL_BITS - 1))
max_val_allowed = (2**(TOTAL_BITS - 1)) - 1

print(f"Generando LUT para formato Q{INTEGER_BITS+1}.{FRACTIONAL_BITS}")
print(f"Resolución (LSB): {1.0/(2**FRACTIONAL_BITS):.3e}")

for val in sine_wave_float:
    # Escalar
    scaled = val * (2**FRACTIONAL_BITS)
    # Redondear al entero más cercano
    fixed_int = int(round(scaled))
    
    # Clipping de seguridad (Saturnación)
    # Aunque +/- 1.0 cabe de sobra en Q3.29, esto protege contra errores numéricos
    if fixed_int > max_val_allowed:
        fixed_int = max_val_allowed
    elif fixed_int < min_val_allowed:
        fixed_int = min_val_allowed
        
    sine_wave_fixed.append(fixed_int)

# --- 4. Generación del VHDL ---
header = f"""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all; -- Agregamos fixed_pkg para facilitar el uso

package {PKG_NAME} is

    constant LUT_DEPTH       : integer := {NUM_POINTS};
    constant LUT_ADDR_WIDTH  : integer := {int(np.log2(NUM_POINTS))};
    
    -- Definimos el subtipo exacto para evitar errores de tipeo en el RTL
    subtype t_lut_val is sfixed({INTEGER_BITS} downto -{FRACTIONAL_BITS});
    
    -- Array de sfixed directamente. 
    -- Esto permite usar la LUT sin hacer casts molestos en el código principal.
    type t_sine_table is array (0 to LUT_DEPTH - 1) of t_lut_val;

    constant SINE_TABLE : t_sine_table := (
"""

body = ""
for i, val in enumerate(sine_wave_fixed):
    # Convertimos el entero a binario/hex y luego a sfixed usando to_sfixed
    # Truco: Escribimos el valor como bit_string para que VHDL lo interprete directo
    # o usamos to_sfixed con el valor real double, pero para exactitud bit a bit
    # lo mejor es pasar el 'integer' a 'signed' y hacer un cast visual.
    
    # Sin embargo, la forma más limpia en VHDL moderno para constantes grandes es:
    # index => to_sfixed(real_value, ...)
    # Pero para garantizar que sea EXACTO al python, usaremos to_sfixed sobre el crudo.
    
    # Opción más compatible: array de std_logic_vector o signed, y cast en la lectura.
    # Para este script, mantendremos 'signed' en la tabla base para máxima compatibilidad
    # y tú harás el cast a sfixed en la lectura.
    
    vhdl_val = f"to_sfixed({val}, {INTEGER_BITS}, -{FRACTIONAL_BITS})"
    
    # Nota: to_sfixed(integer, ...) interpreta el entero como el valor real? NO.
    # numeric_std 'to_signed' toma el entero crudo. fixed_pkg 'to_sfixed' toma reales o enteros escalados.
    # CORRECCIÓN DE ESTRATEGIA PARA EL SCRIPT:
    # Lo más seguro es guardar la tabla como SIGNED (std_logic_vector friendly) 
    # y hacer el cast al leer. Evita problemas de compilación con literales grandes.
    
    pass 

# RE-GENERACIÓN DEL HEADER PARA USAR SIGNED (MÁS SEGURO) Y CAST AUTOMÁTICO
header_v2 = f"""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package {PKG_NAME} is

    constant LUT_DEPTH       : integer := {NUM_POINTS};
    constant LUT_DATA_WIDTH  : integer := {TOTAL_BITS};

    type t_sine_table_raw is array (0 to LUT_DEPTH - 1) of signed(LUT_DATA_WIDTH - 1 downto 0);

    constant SINE_TABLE_RAW : t_sine_table_raw := (
"""

content = header_v2
for i, val in enumerate(sine_wave_fixed):
    separator = ",\n" if i < len(sine_wave_fixed) - 1 else "\n"
    content += f"        {i} => to_signed({val}, {TOTAL_BITS}){separator}"

footer = f"""    );
    
    -- Función auxiliar opcional para recuperar como sfixed si usas VHDL 2008
    -- o simplemente haz el cast en tu código: to_sfixed(SINE_TABLE_RAW(i), 2, -29)
    
end package {PKG_NAME};
"""

with open(FILE_NAME, "w") as f:
    f.write(content + footer)

print(f"Archivo '{FILE_NAME}' generado.")
print("Recuerda: Al leer la tabla en tu VHDL, usa: to_sfixed(SINE_TABLE_RAW(addr), 2, -29)")