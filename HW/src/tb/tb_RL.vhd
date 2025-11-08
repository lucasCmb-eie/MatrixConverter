library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

entity tb_RL is
end tb_RL;

architecture Behavioral of tb_RL is
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;
    constant alpha1_slv : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.00066613376, INT_BITS-1, -FRAC_BITS);
    constant beta1_slv  : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.998401279, INT_BITS-1, -FRAC_BITS);
    constant PER2 : time := (10 ns /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    constant CLK_FREQ : real := 1.0e8;

    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    signal test_enable : std_logic;

    -- Señales de tension trifasica
    signal test_wU : std_logic_vector(31 downto 0);
    signal test_wV : std_logic_vector(31 downto 0);
    signal test_wW : std_logic_vector(31 downto 0);

    -- Señales de corriente trifasica RL
    signal test_oIu : std_logic_vector(31 downto 0);
    signal test_oIv : std_logic_vector(31 downto 0);
    signal test_oIw : std_logic_vector(31 downto 0);

    -- Señales T. Clark de tension trifasica
    signal test_oAlfa : std_logic_vector(31 downto 0);
    signal test_oBeta : std_logic_vector(31 downto 0);

    -- Salida diente de sierra
    signal test_o_angle : std_logic_vector(10 downto 0);-- Salida del diente de sierra (11 bits)

    

begin

    --NCO
    AC: entity work.AC_SOURCE
        port map (
            i_clk => test_clk_in,
            i_rst => test_rst_in,

            o_U   => test_wU,
            o_V   => test_wV,
            o_W   => test_wW
        );

    
    RL: entity work.RL_wrapper
        port map (
            i_clk   => test_clk_in,
            i_rst   => test_rst_in,

            o_Enable => test_enable,

            i_c_a0  => to_slv(alpha1_slv),
            i_c_a1  => to_slv(beta1_slv),
            i_c_b1  => to_slv(beta1_slv),

            i_U => test_wU,
            i_V => test_wV,
            i_W => test_wW,

            o_Iu => test_oIu,
            o_Iv => test_oIv,
            o_Iw => test_oIw
        );

    TClark: entity work.TransformadaClark
        port map (
            i_U   => test_wU,
            i_V   => test_wV,
            i_W   => test_wW,

            o_alfa => test_oAlfa,
            o_beta => test_oBeta
        );

    PhaseGen: entity work.PhaseSawGen
        generic map (
            G_CLK_FREQ => CLK_FREQ,
            G_F_SINE   => 100.0
        )
        port map (
            i_clk   => test_clk_in,
            i_rst   => test_rst_in,
            i_sin   => to_sfixed(test_oAlfa, 7, -24),  -- usamos componente α
            o_angle => test_o_angle
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
