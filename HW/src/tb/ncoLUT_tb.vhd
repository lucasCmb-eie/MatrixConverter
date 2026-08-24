library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.fixed_pkg.all;

library std;
use std.textio.all;


entity ncoLUT_tb is
end entity ncoLUT_tb;

architecture ncoLUT_tb_arch of ncoLUT_tb is

    constant PER2 : time := (100 ns /2);  -- periodo/2 -> reloj de 10 MHz
    -- Step del NCO de AC_Source para 50 Hz con reloj de 10 MHz:
    --     round(50 * 2**32 / 10e6) = 21475
    constant STEP_50HZ : std_logic_vector(31 downto 0) := x"000053E3";
    constant INT_BITS    : integer := 3;
    constant FRAC_BITS   : integer := 29;
    constant coef_Alpha : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.00000041667, INT_BITS-1, -FRAC_BITS);
    constant coef_Beta  : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.99999900000, INT_BITS-1, -FRAC_BITS);
    
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_o_U : std_logic_vector(31 downto 0);
    signal test_o_V : std_logic_vector(31 downto 0);
    signal test_o_W : std_logic_vector(31 downto 0);
    
    -- Señales de corriente trifasica RL
    signal corriente_fase_U : std_logic_vector(31 downto 0);
    signal corriente_fase_V : std_logic_vector(31 downto 0);
    signal corriente_fase_W : std_logic_vector(31 downto 0);
    
begin

--NCO
nco: entity work.AC_Source
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        i_frec => STEP_50HZ,

        o_U => test_o_U,
        o_V => test_o_V,
        o_W => test_o_W
        );
        
-- RL: entity work.RL_wrapper
--     generic map (
--         INT_BITS  => 3,
--         FRAC_BITS => 29
--     )
--     port map (
--         i_clk   => test_clk_in,
--         i_rst   => test_rst_in,
    
--         i_c_a0  => to_slv(coef_Alpha),
--         i_c_a1  => to_slv(coef_Alpha),
--         i_c_b1  => to_slv(coef_Beta),
    
--         i_U => test_o_U,
--         i_V => test_o_V,
--         i_W => test_o_W,
    
--         o_Iu => corriente_fase_U,
--         o_Iv => corriente_fase_V,
--         o_Iw => corriente_fase_W
--     );

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