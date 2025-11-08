library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;

entity TransformadaClark is
port (
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
    -- Constantes en formato Q8.24 para amplitud invariante
    constant K_CLARK_AMPL : sfixed(7 downto -24) := to_sfixed(2.0/3.0, 7, -24);     -- 2/3
    constant K_CLARK_A : sfixed(7 downto -24) := to_sfixed(-0.5, 7, -24);            --1/2
    constant K_CLARK_B : sfixed(7 downto -24) := to_sfixed(0.81649658, 7, -24);     -- sqrt(3)/2
    constant K_CLARK_C : sfixed(7 downto -24) := to_sfixed(-0.81649658, 7, -24);    -- -sqrt(3)/2

    -- Señales internas para las componentes alfa y beta
    signal w_alfa : sfixed(25 downto -72) := (others => '0');
    signal w_beta : sfixed(24 downto -72) := (others => '0');

    begin

        process (i_U, i_V, i_W)
        begin
            w_alfa <= K_CLARK_AMPL * (to_sfixed(i_U, 7, -24) + K_CLARK_A * to_sfixed(i_V, 7, -24) + K_CLARK_A * to_sfixed(i_W, 7, -24));
            w_beta <= K_CLARK_AMPL * (K_CLARK_B * to_sfixed(i_V, 7, -24) + K_CLARK_C * to_sfixed(i_W, 7, -24));
        end process;

        -- Asignación de las salidas
        o_alfa <= to_slv(resize(w_alfa, 7, -24));
        o_beta <= to_slv(resize(w_beta, 7, -24));
    end Behavioral;