library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;

entity RL is
    generic (
        INT_BITS    : integer := 8;
        FRAC_BITS   : integer := 24
    );
    port(
        -- Señales de control
        i_clk     : in  std_logic;
        i_rst   : in  std_logic; -- Reset asíncrono activo a nivel bajo

        -- Coeficientes del filtro (entradas configurables)
        i_c_a0    : in  sfixed(INT_BITS-1 downto -FRAC_BITS);
        i_c_a1    : in  sfixed(INT_BITS-1 downto -FRAC_BITS);
        i_c_b1    : in  sfixed(INT_BITS-1 downto -FRAC_BITS);

        -- Puertos de datos
        i_Vi    : in  sfixed(INT_BITS-1 downto -FRAC_BITS);
        o_IL    : out sfixed(INT_BITS-1 downto -FRAC_BITS)
    );
end RL;

architecture Behavioral of RL is

    -- Señales para almacenar los valores del ciclo anterior
    signal i_n_minus_1 : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');
    signal v_n_minus_1 : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');

    -- Señales para los productos intermedios
    constant PROD_INT_BITS  : integer := 2*INT_BITS;
    constant PROD_FRAC_BITS : integer := 2*FRAC_BITS;
    -- Registro para la salida
    signal i_n_reg : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');

begin

    process (i_clk, i_rst)
        variable term_a0_v_n   : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable term_a1_v_n_1 : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable term_b1_i_n_1 : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable i_n_next      : sfixed(INT_BITS-1 downto -FRAC_BITS);
    begin
        if i_rst = '1' then
            v_n_minus_1 <= (others => '0');
            i_n_minus_1 <= (others => '0');
            i_n_reg <= (others => '0');
        elsif rising_edge(i_clk) then
            -- Multiplicaciones usando variables
            term_a0_v_n   := i_c_a0 * i_Vi;
            term_a1_v_n_1 := i_c_a1 * v_n_minus_1;
            term_b1_i_n_1 := i_c_b1 * i_n_minus_1;

            -- Suma y resta
            i_n_next := resize(term_a0_v_n + term_a1_v_n_1 - term_b1_i_n_1, INT_BITS-1, -FRAC_BITS);

            -- Actualización de registros
            v_n_minus_1 <= i_Vi;
            i_n_minus_1 <= i_n_next;
            i_n_reg <= i_n_next;
        end if;
    end process;
    
    -- Asignación de la salida
    o_IL <= i_n_reg;

end Behavioral;
