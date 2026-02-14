library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.sine_lut_pkg.all;

entity tb_PhaseSaw_with_Clark is
end entity;

architecture tb of tb_PhaseSaw_with_Clark is

    -- Clock period: 100 kHz → 10 us per period
    constant CLK_FREQ : real := 1.0e8;
    constant PER      : time := 10 ns;
    constant PER2     : time := PER / 2.0;

    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;

    signal clk : std_logic;
    signal rst : std_logic;

    -- Señales de tension trifasica
    signal tension_fase_U : std_logic_vector(31 downto 0);
    signal tension_fase_V : std_logic_vector(31 downto 0);
    signal tension_fase_W : std_logic_vector(31 downto 0);
    
    -- Señales T. Clark 
    signal Clark_alfa_Vi : std_logic_vector(31 downto 0);
    signal Clark_beta_Vi : std_logic_vector(31 downto 0);

    signal Clark_alfa_Io : std_logic_vector(31 downto 0);
    signal Clark_beta_Io : std_logic_vector(31 downto 0);

    -- Salida diente de sierra
    signal Sierra_angle_50Hz : std_logic_vector(10 downto 0);-- Salida del diente de sierra 50Hz
    signal Sierra_angle_Var : std_logic_vector(10 downto 0);-- Salida del diente de sierra variable
begin
     --NCO
    AC: entity work.AC_SOURCE
        port map (
            i_clk => clk,
            i_rst => rst,

            o_U   => tension_fase_U,
            o_V   => tension_fase_V,
            o_W   => tension_fase_W
        );

    TClark_Vi: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_start => '1',

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_valido => open,

            o_alfa => Clark_alfa_Vi,
            o_beta => Clark_beta_Vi
        );

    TClark_Io: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_start => '1',

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_valido => open,

            o_alfa => Clark_alfa_Io,
            o_beta => Clark_beta_Io
        );

    PhaseGenVar: entity work.PhaseSawGen
        generic map(
            G_CLK_FREQ => 1.0e8,  -- frecuencia de reloj (Hz)
            G_SAW_FREQ   => 100.0    -- frecuencia de la senoide (Hz)
        )
        port map (
            i_clk   => clk,
            i_rst   => rst,
            i_sin   => to_sfixed(Clark_alfa_Vi, INT_BITS - 1, -FRAC_BITS),  -- usamos componente α
            o_angle => Sierra_angle_Var
        );

    PhaseGen50: entity work.PhaseSawGen
        port map (
            i_clk   => clk,
            i_rst   => rst,
            i_sin   => to_sfixed(Clark_alfa_Vi, INT_BITS - 1, -FRAC_BITS),  -- usamos componente α
            o_angle => Sierra_angle_50Hz
        );

    DoClock: process
    begin
        clk <= '1';
        wait for PER2;
        clk <= '0';
        wait for PER2;
        
    end process DoClock;

    -- Init
    InitTest: process
        begin
            --Starting Test
            report "ncoLUT_tb start...";
            report "Reset";   
            rst <= '1';
            wait for (2*PER2);
            rst <= '0';
            wait;
        end process InitTest;
end architecture;
