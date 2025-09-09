library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library std;
use std.textio.all;
use work.declaraciones.all;

entity matrixConmut_tb is
end matrixConmut_tb;

architecture Behavioral of matrixConmut_tb is
    
    constant PER2 : time := (10 us /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_VLinea :  vector(1 to 3)(31 downto 0);
    signal test_Coef: std_logic_vector(17 downto 0);
    signal test_VLoad: vector(1 to 3)(31 downto 0);

begin

AC_Source: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        o_triV => test_VLinea
        );

Matrix: entity work.matrixConmut 
    port map(
        i_clk => test_clk_in,
        i_M => test_Coef,  -- Coeficientes dados por el algoritmo del modulador
        i_V => test_VLinea,  -- Vector entrada con la señal trifasica
        o_V => test_VLoad
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
        report "ncoLUT_tb start...";
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
