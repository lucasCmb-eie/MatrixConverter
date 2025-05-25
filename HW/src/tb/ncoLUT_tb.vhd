---------------------------------------------------------------------------
---- Entity:  ncoLUT_tb                                                ----
---- Description:    Implement Testbench for NCO and LUT               ----
---- Author:  Martín A. Heredia                                        ----
---- Last revision:    24/05/2020                                      ----
---- Dependencies:                                                     ----
----	IEEE.std_logic_1164                                            ----
----	IEEE.numeric_std                                               ----
----	IEEE.math_real                                                 ----
----	IEEE.std_logic_textio                                          ----
----        This last dependency requires '-fsynopsys' option          ----
----        of GHDL                                                    ----
----    std.textio                                                     ----
----    work.parametersPackage                                         ----
----	                                                               ----
----	                                                               ----
----                                                                   ----
----                                                                   ----
---------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library std;
use std.textio.all;
library work;

entity ncoLUT_tb is
end entity ncoLUT_tb;

architecture ncoLUT_tb_arch of ncoLUT_tb is
    constant PER2 : time := (10 us /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in_n : std_logic;
    signal test_fcw_in_s : std_logic_vector(2 downto 0);
    signal test_nco_out_s :  std_logic_vector(10 downto 0);
    signal test_data_out_s : std_logic_vector(8 downto 0);
begin

--NCO
nco: entity work.AC_SOURCE
    generic map(ncoBits => 11, freqControlBits => 3)
    port map(
        clk_in => test_clk_in,
        rst_in_n => test_rst_in_n,
        fcw_in => test_fcw_in_s,
        nco_out => test_nco_out_s
        );

--LUT (Look Up Table)
LUT: entity work.SENO_LT
    port map(Address => test_nco_out_s, DATA => test_data_out_s);

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
        test_rst_in_n <= '0';
        test_fcw_in_s <= std_logic_vector(to_unsigned(1,3));
        wait for 2*PER2;
        report "Begin";
        test_rst_in_n <= '1';
        wait;

end process DoTest;

end architecture ncoLUT_tb_arch;
