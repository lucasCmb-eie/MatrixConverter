library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library std;
use std.textio.all;
use work.declaraciones.all;
use work.sine_lut_pkg.all;


entity ncoLUT_tb is
end entity ncoLUT_tb;

architecture ncoLUT_tb_arch of ncoLUT_tb is

    constant PER2 : time := (10 ns /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_nco_out_s :  vector(1 to 3)(31 downto 0);
begin

--NCO
nco: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        o_triV => test_nco_out_s
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