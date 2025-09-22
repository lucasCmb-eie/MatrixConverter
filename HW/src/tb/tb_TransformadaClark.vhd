library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

use work.declaraciones.all;
use work.sine_lut_pkg.all;

entity tb_TransformadaClark is
end tb_TransformadaClark;

architecture Behavioral of tb_TransformadaClark is

    constant PER2 : time := (10 us /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_w_uvw : vector(1 to 3)(31 downto 0);
    signal test_o_alfa_beta : vector(1 to 2)(31 downto 0);
begin

    --TransformadaClark
    UUT: entity work.TransformadaClark
    port map(
        i_uvw => test_w_uvw,
        o_alfa_beta => test_o_alfa_beta
        );

    DoClock: process
    begin
        test_clk_in <= '1';
        wait for PER2;
        test_clk_in <= '0';
        wait for PER2;
        
    end process DoClock;
    
    AC: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        o_triV => test_w_uvw
        );
        
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
    
end Behavioral;