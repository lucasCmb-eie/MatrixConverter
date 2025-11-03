library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;
use work.declaraciones.all;

entity tb_RL is
end tb_RL;

architecture Behavioral of tb_RL is
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;

    constant PER2 : time := (10 ns /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_nco_out_s :  vector(1 to 3)(31 downto 0);
    signal test_o_I : vector(1 to 3)(31 downto 0);
    signal tick_enable : std_logic;

    constant alpha1_slv : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.00066613376, INT_BITS-1, -FRAC_BITS);
    constant beta1_slv  : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(-0.998401279, INT_BITS-1, -FRAC_BITS);

begin

    --NCO
    AC: entity work.AC_SOURCE
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        o_triV => test_nco_out_s
        );

    RL: entity work.RL
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        i_enable => tick_enable,
        i_c_a0 => alpha1_slv,
        i_c_a1 => alpha1_slv,
        i_c_b1 => beta1_slv,
        i_Vi => test_nco_out_s,
        o_IL => test_o_I
        );

    U_EnableGen : entity work.EnableGen
        generic map (
            CLK_FREQ_HZ => 100000000,
            TCONV_US    => 16     -- Tconv = 16 µs
        )
        port map (
            i_clk  => test_clk_in,
            i_rst  => test_rst_in,
            o_tick => tick_enable
        );

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
end Behavioral;
