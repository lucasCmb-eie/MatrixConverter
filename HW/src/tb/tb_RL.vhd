----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.08.2025 18:20:21
-- Design Name: 
-- Module Name: tb_RL - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;
use ieee.numeric_std.all;
use work.declaraciones.all;

entity tb_RL is
end tb_RL;

architecture Behavioral of tb_RL is
    constant PER2 : time := (10 us /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_fcw_in_s : std_logic_vector(3 downto 0);
    signal test_nco_out_s :  vector(1 to 3)(8 downto 0);

    signal  coef_a0 : sfixed(7 downto -24) := to_sfixed(0.00842835894893406, 7, -24);
    signal  coef_a1 : sfixed(7 downto -24) := to_sfixed(0.00842835894893406, 7, -24);
    signal  coef_b1 : sfixed(7 downto -24) := to_sfixed(-0.9831432821021319, 7, -24);

    signal  salida_IL : sfixed(7 downto -24);
begin

--NCO
    nco: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        i_fcw => test_fcw_in_s,
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

--RL
    RL: entity work.RL
    port map(
        i_clk => test_clk_in,
        i_rst_n => not test_rst_in,
        i_c_a0    => coef_a0,
        i_c_a1    => coef_a1,
        i_c_b1    => coef_b1,
        i_Vi    => to_sfixed(test_nco_out_s(1), 7, -24),
        o_IL    => salida_IL
        );


    DoTest: process
        begin
        --Starting Test
        report "ncoLUT_tb start...";
        report "Reset";
        test_rst_in <= '1';
        test_fcw_in_s <= std_logic_vector(to_unsigned(1, 4));
        wait for 2*PER2;
        report "Begin";
        test_rst_in <= '0';
        wait;
    end process DoTest;


end Behavioral;
