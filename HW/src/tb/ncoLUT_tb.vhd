library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library std;
use std.textio.all;


entity ncoLUT_tb is
end entity ncoLUT_tb;

architecture ncoLUT_tb_arch of ncoLUT_tb is

    constant PER2 : time := (10 ns /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_o_U : std_logic_vector(31 downto 0);
    signal test_o_V : std_logic_vector(31 downto 0);
    signal test_o_W : std_logic_vector(31 downto 0);
begin

--NCO
nco: entity work.design_TestAC_wrapper
    port map(
        i_clk_0 => test_clk_in,
        i_rst_0 => test_rst_in,
        o_U_0 => test_o_U,
        o_V_0 => test_o_V,
        o_W_0 => test_o_W
        );

--Clock
DoClock: process
begin
    test_clk_in <= '1';
    wait for PER2;
    test_clk_in <= '0';
    wait for PER2;
    
end process DoClock;

--Test
DoTest: process
begin
        --Starting Test
        report "ncoLUT_tb start...";
        report "Reset";
        test_rst_in <= '1';
        wait for 2*PER2;
        report "Begin";
        test_rst_in <= '0';
        wait;
end process DoTest;

end architecture ncoLUT_tb_arch;