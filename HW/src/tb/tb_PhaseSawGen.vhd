library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

use work.declaraciones.all;
use work.sine_lut_pkg.all;

entity tb_PhaseSaw_with_Clark is
end entity;

architecture tb of tb_PhaseSaw_with_Clark is

    -- Clock period: 100 kHz → 10 us per period
    constant CLK_FREQ : real := 1.0e8;
    constant PER      : time := 10 ns;
    constant PER2     : time := PER / 2.0;

    -- Señales de prueba
    signal test_clk_in  : std_logic := '0';
    signal test_rst_in  : std_logic := '0';

    -- AC_SOURCE → salida trifásica
    signal test_w_uvw : vector(1 to 3)(31 downto 0);

    -- Transformada de Clark → αβ
    signal test_o_alfa_beta : vector(1 to 2)(31 downto 0);

    -- Salida del diente de sierra (11 bits)
    signal test_o_angle : std_logic_vector(10 downto 0);

begin
    ------------------------------------------------------------
    -- Instancia del DUT (PhaseSawGen11b)
    ------------------------------------------------------------
    UUT: entity work.PhaseSawGen
        generic map (
            G_CLK_FREQ => CLK_FREQ,
            G_F_SINE   => 50.0
        )
        port map (
            i_clk   => test_clk_in,
            i_rst   => test_rst_in,
            i_sin   => to_sfixed(test_o_alfa_beta(1), 7, -24),  -- usamos componente α
            o_angle => test_o_angle
        );

    ------------------------------------------------------------
    -- Fuente trifásica
    ------------------------------------------------------------
    AC: entity work.AC_SOURCE
        port map (
            i_clk  => test_clk_in,
            i_rst  => test_rst_in,
            o_triV => test_w_uvw
        );

    ------------------------------------------------------------
    -- Transformada de Clark
    ------------------------------------------------------------
    TClark: entity work.TransformadaClark
        port map (
            i_uvw       => test_w_uvw,
            o_alfa_beta => test_o_alfa_beta
        );

    ------------------------------------------------------------
    -- Generador de clock
    ------------------------------------------------------------
    DoClock: process
    begin
        test_clk_in <= '1';
        wait for PER2;
        test_clk_in <= '0';
        wait for PER2;
    end process DoClock;

    ------------------------------------------------------------
    -- Proceso de inicialización
    ------------------------------------------------------------
    InitTest: process
    begin
        report ">>> Testbench PhaseSaw + Clark start..." severity note;
        test_rst_in <= '1';
        wait for (5*PER);
        test_rst_in <= '0';
        report ">>> Reset released, running simulation..." severity note;
        wait for 50 ms;
        report ">>> Simulation finished." severity note;
        wait;
    end process InitTest;

end architecture;
