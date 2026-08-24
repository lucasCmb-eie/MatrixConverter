library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

entity tb_RL_Tustin is
end tb_RL_Tustin;

architecture Behavioral of tb_RL_Tustin is
    
    constant PER2 : time := (10 ns /2); -- Se busca 100MHz
    constant CLK_FREQ : real := 1.0e8;
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;
    constant coef_Alpha : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.00004166, INT_BITS-1, -FRAC_BITS);
    constant coef_Beta  : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.999999000, INT_BITS-1, -FRAC_BITS);
    
    constant q_value : std_logic_vector(8 downto 0) := "100000000"; -- Valor fijo de q (Q0.8)
    constant phi_value : std_logic_vector(10 downto 0) := "00000000000"; -- Valor fijo de phi_i

    signal fin_calc_ts : std_logic;
    signal fin_ciclo : std_logic;
    signal inicio_ciclo : std_logic;

    signal clk : std_logic;
    signal rst : std_logic;
    signal enable_SVM : std_logic;
    signal tick_enable : std_logic;

    signal alph_O : std_logic_vector(10 downto 0);

    -- Señales de tension trifasica
    signal tension_fase_U : std_logic_vector(31 downto 0);
    signal tension_fase_V : std_logic_vector(31 downto 0);
    signal tension_fase_W : std_logic_vector(31 downto 0);

    -- Señales entre SVM y RL
    signal tension_SVM_U : std_logic_vector(31 downto 0);
    signal tension_SVM_V : std_logic_vector(31 downto 0);
    signal tension_SVM_W : std_logic_vector(31 downto 0);

    -- Señales de corriente trifasica RL
    signal corriente_fase_U : std_logic_vector(31 downto 0);
    signal corriente_fase_V : std_logic_vector(31 downto 0);
    signal corriente_fase_W : std_logic_vector(31 downto 0);

    -- Señales T. Clark de tension trifasica
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

    
    RL_Tustin: entity work.RL_wrapper
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk   => clk,
            i_rst   => rst,

            i_c_a0  => to_slv(coef_Alpha),
            i_c_a1  => to_slv(coef_Alpha),
            i_c_b1  => to_slv(coef_Beta),

            i_U => tension_SVM_U,
            i_V => tension_SVM_V,
            i_W => tension_SVM_W,

            o_Iu => corriente_fase_U,
            o_Iv => corriente_fase_V,
            o_Iw => corriente_fase_W
        );

    SVM: entity work.SVM_wrapper
        port map (
            i_clk    => clk,
            i_enable => enable_SVM,
            i_al_o   => Sierra_angle_50Hz,
            i_be_i   => Sierra_angle_50Hz, -- Usamos los 11 bits menos significativos
            i_q_i    => "001000000", -- Valor fijo de q (Q0.8)
            i_phi_i  => "00000000000", -- Valor fijo de phi_i

            o_fin_ciclo    => fin_ciclo,
            o_inicio_ciclo => inicio_ciclo,
            o_fin_calc_ts  => fin_calc_ts,

            i_U => tension_fase_U,
            i_V => tension_fase_V,
            i_W => tension_fase_W,

            o_U => tension_SVM_U,
            o_V => tension_SVM_V,
            o_W => tension_SVM_W
        );

    U_EnableGen : entity work.EnableGen
        generic map (
            CLK_FREQ_HZ => 100000000,
            TCONV_NS    => 16000     -- Tconv = 16 µs
        )
        port map (
            i_clk  => clk,
            i_rst  => rst,
            o_tick => tick_enable
        );

    TClark_Vi: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_enable => tick_enable,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

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
            i_enable => tick_enable,

            i_U   => corriente_fase_U,
            i_V   => corriente_fase_V,
            i_W   => corriente_fase_W,

            o_alfa => Clark_alfa_Io,
            o_beta => Clark_beta_Io
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
            enable_SVM <= '0';
            wait for (2*PER2);
            report "Begin";
            rst <= '0';
            enable_SVM <= '1';
            alph_O <= Sierra_angle_50Hz;
            wait for 90ms;
            alph_O <= Sierra_angle_Var;

        end process InitTest;


end Behavioral;
