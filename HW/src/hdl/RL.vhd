library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;
use work.declaraciones.all;

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
        i_Vi    : in  vector(1 to 3)(31 downto 0);
        o_IL    : out vector(1 to 3)(31 downto 0)
    );
end RL;

architecture Behavioral of RL is

    constant PROD_INT_BITS  : integer := 2*INT_BITS;
    constant PROD_FRAC_BITS : integer := 2*FRAC_BITS;

    -- Señales para almacenar los valores del ciclo anterior
    signal i_n_minus_1 : sfvector(1 to 3)(INT_BITS-1 downto -FRAC_BITS) := (others => (others => '0'));
    signal v_n_minus_1 : sfvector(1 to 3)(INT_BITS-1 downto -FRAC_BITS) := (others => (others => '0'));

    -- Señal para la conversión de entrada
    signal  i_Vi_s : sfvector(1 to 3)(INT_BITS-1 downto -FRAC_BITS) := (others => (others => '0'));  
    
    -- Registro para la salida
    signal i_n_reg : sfvector(1 to 3)(INT_BITS-1 downto -FRAC_BITS) := (others => (others => '0'));

begin

    -- Conversión de std_logic_vector a sfixed para la entrada
    i_Vi_s(1) <= to_sfixed(i_Vi(1), INT_BITS-1, -FRAC_BITS);
    i_Vi_s(2) <= to_sfixed(i_Vi(2), INT_BITS-1, -FRAC_BITS);
    i_Vi_s(3) <= to_sfixed(i_Vi(3), INT_BITS-1, -FRAC_BITS);

    --Conversion de sfixed a std_logic_vector para la salida
    o_IL(1) <= to_slv(i_n_reg(1));
    o_IL(2) <= to_slv(i_n_reg(2));
    o_IL(3) <= to_slv(i_n_reg(3));

    process (i_clk, i_rst)
        variable term_a0_v_n   : sfvector(1 to 3)(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable term_a1_v_n_1 : sfvector(1 to 3)(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable term_b1_i_n_1 : sfvector(1 to 3)(PROD_INT_BITS-1 downto -PROD_FRAC_BITS);
        variable i_n_next      : sfvector(1 to 3)(INT_BITS-1 downto -FRAC_BITS);
    begin
        if i_rst = '1' then
            v_n_minus_1 <= (others => (others => '0'));
            i_n_minus_1 <= (others => (others => '0'));
            i_n_reg <= (others => (others => '0'));
        elsif rising_edge(i_clk) then
            for i in 1 to 3 loop
                -- Multiplicaciones usando variables
                term_a0_v_n(i)   := i_c_a0 * i_Vi_s(i);
                term_a1_v_n_1(i) := i_c_a1 * v_n_minus_1(i);
                term_b1_i_n_1(i) := i_c_b1 * i_n_minus_1(i);

                -- Suma y resta
                i_n_next(i) := resize(term_a0_v_n(i) + term_a1_v_n_1(i) - term_b1_i_n_1(i), INT_BITS-1, -FRAC_BITS);

                -- Actualización de registros
                v_n_minus_1(i) <= i_Vi_s(i);
                i_n_minus_1(i) <= i_n_next(i);
                i_n_reg(i)     <= i_n_next(i);
            end loop;
        end if;
    end process;

end Behavioral;
