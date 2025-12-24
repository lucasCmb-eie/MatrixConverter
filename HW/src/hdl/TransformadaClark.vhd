library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;

entity TransformadaClark is
generic (
        INT_BITS  : integer := 8;
        FRAC_BITS : integer := 24
    );
port (
    i_clk : in std_logic;
    i_rst : in std_logic;
    i_enable : in std_logic;
    -- Entradas de tensiones trifasicas (U, V ,W)
    i_U : in std_logic_vector (31 downto 0);
    i_V : in std_logic_vector (31 downto 0);
    i_W : in std_logic_vector (31 downto 0);

    -- Salidas de tensiones en el sistema alfa-beta
    o_alfa : out std_logic_vector(31 downto 0);
    o_beta : out std_logic_vector(31 downto 0)
);
end TransformadaClark;

architecture Behavioral of TransformadaClark is
    -- Constantes en formato Q3.29 para amplitud invariante
    constant K_CLARK_AMPL : sfixed(INT_BITS - 1 downto -FRAC_BITS) := to_sfixed(2.0/3.0, INT_BITS - 1, -FRAC_BITS);     -- 2/3
    constant K_CLARK_A : sfixed(INT_BITS - 1 downto -FRAC_BITS) := to_sfixed(-0.5, INT_BITS - 1, -FRAC_BITS);            --1/2
    constant K_CLARK_B : sfixed(INT_BITS - 1 downto -FRAC_BITS) := to_sfixed(0.81649658, INT_BITS - 1, -FRAC_BITS);     -- sqrt(3)/2
    constant K_CLARK_C : sfixed(INT_BITS - 1 downto -FRAC_BITS) := to_sfixed(-0.81649658, INT_BITS - 1, -FRAC_BITS);    -- -sqrt(3)/2

    -- Señales internas para las componentes alfa y beta
    signal w_alfa: sfixed(INT_BITS*3 +1 downto -(FRAC_BITS*3)) := (others => '0');
    signal w_beta : sfixed(INT_BITS*3 downto -(FRAC_BITS*3)) := (others => '0');
    signal r_alfa : sfixed(INT_BITS - 1 downto -FRAC_BITS);
    signal r_beta : sfixed(INT_BITS - 1 downto -FRAC_BITS);

    begin
        w_alfa <= K_CLARK_AMPL * (to_sfixed(i_U, INT_BITS - 1, -FRAC_BITS) + K_CLARK_A * to_sfixed(i_V, INT_BITS - 1, -FRAC_BITS) + K_CLARK_A * to_sfixed(i_W, INT_BITS - 1, -FRAC_BITS));
        w_beta <= K_CLARK_AMPL * (K_CLARK_B * to_sfixed(i_V, INT_BITS - 1, -FRAC_BITS) + K_CLARK_C * to_sfixed(i_W, INT_BITS - 1, -FRAC_BITS));
        
        process (i_clk, i_rst)
        begin
            if i_rst = '1' then
                r_alfa <= (others => '0');
                r_beta <= (others => '0');
            elsif rising_edge(i_clk) then
                if i_enable = '1' then
                    r_alfa <= resize(w_alfa, INT_BITS - 1, -FRAC_BITS);
                    r_beta <= resize(w_beta, INT_BITS - 1, -FRAC_BITS);
                end if;
            end if;
        end process;

        -- Asignación de las salidas
        o_alfa <= to_slv(r_alfa);
        o_beta <= to_slv(r_beta);
    end Behavioral;