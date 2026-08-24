library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library std;
use std.textio.all;

entity matrixConmut_tb is
end matrixConmut_tb;

architecture Behavioral of matrixConmut_tb is

    constant PER2 : time := (100 ns /2); --periodo/2 -> reloj de 10 MHz

    -- Step del NCO de AC_Source para 50 Hz con reloj de 10 MHz:
    --     round(50 * 2**32 / 10e6) = 21475
    constant STEP_50HZ : std_logic_vector(31 downto 0) := x"000053E3";

    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;

    -- Tensiones de linea que entrega la fuente trifasica
    signal test_VLinea_U : std_logic_vector(31 downto 0);
    signal test_VLinea_V : std_logic_vector(31 downto 0);
    signal test_VLinea_W : std_logic_vector(31 downto 0);

    signal test_Coef : std_logic_vector(17 downto 0);

    -- Tensiones sobre la carga a la salida de la matriz
    signal test_VLoad_U : std_logic_vector(31 downto 0);
    signal test_VLoad_V : std_logic_vector(31 downto 0);
    signal test_VLoad_W : std_logic_vector(31 downto 0);

begin

AC_Source: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        i_frec => STEP_50HZ,

        o_U => test_VLinea_U,
        o_V => test_VLinea_V,
        o_W => test_VLinea_W
        );

Matrix: entity work.matrixConmut
    port map(
        i_clk => test_clk_in,
        i_M => test_Coef,        -- Coeficientes dados por el algoritmo del modulador

        i_U => test_VLinea_U,    -- Señal trifasica de entrada
        i_V => test_VLinea_V,
        i_W => test_VLinea_W,

        o_U => test_VLoad_U,     -- Tension aplicada a la carga
        o_V => test_VLoad_V,
        o_W => test_VLoad_W
    );

--Clock
DoClock: process
begin
    test_clk_in <= '1';
    wait for PER2;
    test_clk_in <= '0';
    wait for PER2;

end process DoClock;

--Init
InitTest: process
begin
        --Starting Test
        report "matrixConmut_tb start...";
        report "Reset";
        test_rst_in <= '1';
        wait for (2*PER2);
        report "Begin";
        test_rst_in <= '0';
        wait;
end process InitTest;

--Test
DoTest: process
begin
    test_Coef <= "000000000111010101";
    --wait for 2*PER2*2000;
    --test_Coef <= "000000000"&"101"&"110"&"011";
    wait;
end process DoTest;

end architecture Behavioral;
