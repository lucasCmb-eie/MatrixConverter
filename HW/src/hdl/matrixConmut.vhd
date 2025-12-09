library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use ieee.fixed_pkg.all;

entity matrixConmut is
    generic (
        -- Configuración de punto fijo (Q8.24 por defecto)
        INT_BITS    : integer := 8;  -- Parte entera (incluye signo)
        FRAC_BITS   : integer := 24  -- Parte fraccionaria
    );
    port(
        i_clk : in std_logic;
        
        -- Matriz de control (9 bits usados de los 18 disponibles)
        i_M   : in std_logic_vector(17 downto 0);

        -- Entradas dinámicas (El ancho se ajusta automáticamente)
        -- Ancho total = INT_BITS + FRAC_BITS
        i_U   : in std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);
        i_V   : in std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);
        i_W   : in std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);

        -- Salidas dinámicas
        o_U   : out std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);
        o_V   : out std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);
        o_W   : out std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0)
    );
end matrixConmut;

architecture Behavioral of matrixConmut is

    -- ========================================================================
    -- DEFINICIÓN DE CONSTANTES Y RANGOS
    -- ========================================================================
    -- Calculamos los límites del sfixed. 
    -- Ejemplo Q8.24: High=7, Low=-24.
    constant HIGH_BIT : integer := INT_BITS - 1;
    constant LOW_BIT  : integer := -FRAC_BITS;
    
    -- Bits de guarda para el acumulador. 
    -- Al sumar 3 señales, el valor puede crecer log2(3) = 1.58 bits.
    -- Agregamos 2 bits extra a la parte entera para evitar desbordamiento interno.
    constant ACC_HIGH_BIT : integer := HIGH_BIT + 2;

    -- ========================================================================
    -- SEÑALES INTERNAS
    -- ========================================================================
    -- Señales convertidas a tipo sfixed con el rango dinámico
    signal s_U, s_V, s_W : sfixed(HIGH_BIT downto LOW_BIT);
    
    -- Array para los términos intermedios (AND lógico entre señal y matriz)
    type t_phase_terms is array (0 to 2) of sfixed(HIGH_BIT downto LOW_BIT);
    signal terms_U, terms_V, terms_W : t_phase_terms;

    -- Acumuladores con rango extendido
    signal acc_U, acc_V, acc_W : sfixed(ACC_HIGH_BIT downto LOW_BIT);

begin

    -- 1. Conversión de entrada (std_logic_vector -> sfixed)
    -- Se usa los límites calculados para interpretar correctamente el vector
    s_U <= to_sfixed(i_U, HIGH_BIT, LOW_BIT);
    s_V <= to_sfixed(i_V, HIGH_BIT, LOW_BIT);
    s_W <= to_sfixed(i_W, HIGH_BIT, LOW_BIT);

    -- 2. Lógica de Matriz (Enrutamiento/Enmascarado)
    -- Fila U (Indices de i_M: 0, 3, 6)
    terms_U(0) <= s_U when i_M(0) = '1' else (others => '0');
    terms_U(1) <= s_V when i_M(3) = '1' else (others => '0');
    terms_U(2) <= s_W when i_M(6) = '1' else (others => '0');

    -- Fila V (Indices de i_M: 1, 4, 7)
    terms_V(0) <= s_U when i_M(1) = '1' else (others => '0');
    terms_V(1) <= s_V when i_M(4) = '1' else (others => '0');
    terms_V(2) <= s_W when i_M(7) = '1' else (others => '0');

    -- Fila W (Indices de i_M: 2, 5, 8)
    terms_W(0) <= s_U when i_M(2) = '1' else (others => '0');
    terms_W(1) <= s_V when i_M(5) = '1' else (others => '0');
    terms_W(2) <= s_W when i_M(8) = '1' else (others => '0');

    -- 3. Suma y Registro
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            -- Resize maneja la extensión de signo automáticamente al tamaño de ACC_HIGH_BIT
            acc_U <= resize(terms_U(0) + terms_U(1) + terms_U(2), ACC_HIGH_BIT, LOW_BIT);
            acc_V <= resize(terms_V(0) + terms_V(1) + terms_V(2), ACC_HIGH_BIT, LOW_BIT);
            acc_W <= resize(terms_W(0) + terms_W(1) + terms_W(2), ACC_HIGH_BIT, LOW_BIT);
        end if;
    end process;

    -- 4. Salida (Recorte y conversión a std_logic_vector)
    -- Tomamos solo los bits que corresponden al formato de salida, descartando los bits de guarda
    o_U <= to_slv(acc_U(HIGH_BIT downto LOW_BIT));
    o_V <= to_slv(acc_V(HIGH_BIT downto LOW_BIT));
    o_W <= to_slv(acc_W(HIGH_BIT downto LOW_BIT));

end Behavioral;