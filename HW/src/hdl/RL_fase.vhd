library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

-- Bloque monofásico RL discreto
-- Ecuación: I[n] = a0 * U[n] + a1 * U[n-1] - b1 * I[n-1]
entity RL_fase is
    generic (
        INT_BITS  : integer := 8;
        FRAC_BITS : integer := 24
    );
    port (
        i_clk    : in  std_logic;
        i_rst    : in  std_logic;
        
        i_c_a0 : in sfixed(INT_BITS-1 downto -FRAC_BITS);
        i_c_a1 : in sfixed(INT_BITS-1 downto -FRAC_BITS);
        i_c_b1 : in sfixed(INT_BITS-1 downto -FRAC_BITS);

        i_U : in sfixed(INT_BITS-1 downto -FRAC_BITS);
        o_I : out sfixed(INT_BITS-1 downto -FRAC_BITS)
    );
end entity RL_fase;

architecture Behavioral of RL_fase is

    constant PROD_INT_BITS  : integer := 2*INT_BITS;
    constant PROD_FRAC_BITS : integer := 2*FRAC_BITS;

    signal U_z1 : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');  -- U[n-1]
    signal I_z1 : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');  -- I[n-1]
    signal I_n  : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');  -- salida actual

begin
    process(i_clk, i_rst)
        variable term_a0_v_n   : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS) := (others => '0');
        variable term_a1_v_n_1 : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS) := (others => '0');
        variable term_b1_i_n_1 : sfixed(PROD_INT_BITS-1 downto -PROD_FRAC_BITS) := (others => '0');
        variable i_n_next      : sfixed(INT_BITS-1 downto -FRAC_BITS) := (others => '0');
    begin
        if (i_rst = '1') then
            U_z1 <= (others => '0');
            I_z1 <= (others => '0');
            I_n  <= (others => '0');

        elsif rising_edge(i_clk) then
            
            -- Multiplicaciones usando variables
            term_a0_v_n   := i_c_a0 * i_U;
            term_a1_v_n_1 := i_c_a1 * U_z1;
            term_b1_i_n_1 := i_c_b1 * I_z1;

            -- Ecuación de diferencia discreta
            i_n_next := resize(term_a0_v_n + term_a1_v_n_1 + term_b1_i_n_1, INT_BITS-1, -FRAC_BITS);

            -- Actualización de memorias
            I_n <= i_n_next;
            U_z1 <= i_U;
            I_z1 <= i_n_next;     
            
        end if;
    end process;

    o_I <= I_n;

end architecture;