library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;
use IEEE.NUMERIC_STD.ALL;

entity tb_testSistemaLA is
end tb_testSistemaLA;

architecture tb of tb_testSistemaLA is
  
  constant INT_BITS    : integer := 8;
  constant FRAC_BITS   : integer := 24;

  constant PER2 : time := (10 ns /2); --Frecuencia de 100MHz
  constant CLK_FREQ : real := 1.0e8;

  constant COEF_ALPHA_01 : std_logic_vector(31 downto 0) := to_slv(to_sfixed(0.00066613376, INT_BITS-1, -FRAC_BITS));
  constant COEF_BETA1  : std_logic_vector(31 downto 0) := to_slv(to_sfixed(-0.998401279, INT_BITS-1, -FRAC_BITS));
  constant PARAM_Qi : std_logic_vector(8 downto 0) := "100000000"; -- q(8) = 0.5 (Formato Q0.9?)
  constant PARAM_PHIi : std_logic_vector(10 downto 0) := "00000000000";

  signal test_clk_in : std_logic;
  signal test_rst_in : std_logic;
  signal test_enable_SVM : std_logic;
  signal phase50_angle  : std_logic_vector(10 downto 0);
  signal phase100_angle : std_logic_vector(10 downto 0);
  signal alfa_Output : std_logic_vector(10 downto 0);
  signal w_alfa_Vi : std_logic_vector(31 downto 0);
  signal w_alfa_Io : std_logic_vector(31 downto 0);
  signal o_U_0 : std_logic_vector(31 downto 0);
  signal o_V_0 : std_logic_vector(31 downto 0);
  signal o_W_0 : std_logic_vector(31 downto 0);

  --Componentes
  component test_Trifa_Clark_PhaseSaw_wrapper is
    port (
      alfa_Io : out STD_LOGIC_VECTOR ( 31 downto 0 );
      alfa_Vi : out STD_LOGIC_VECTOR ( 31 downto 0 );
      beta_Io : out STD_LOGIC_VECTOR ( 31 downto 0 );
      i_al_o_0 : in STD_LOGIC_VECTOR ( 10 downto 0 );
      i_be_i_0 : in STD_LOGIC_VECTOR ( 10 downto 0 );
      i_c_a0_0 : in STD_LOGIC_VECTOR ( 31 downto 0 );
      i_c_a1_0 : in STD_LOGIC_VECTOR ( 31 downto 0 );
      i_c_b1_0 : in STD_LOGIC_VECTOR ( 31 downto 0 );
      i_enable_SVM : in STD_LOGIC;
      i_phi_i_0 : in STD_LOGIC_VECTOR ( 10 downto 0 );
      i_q_i_0 : in STD_LOGIC_VECTOR ( 8 downto 0 );
      o_U_0 : out STD_LOGIC_VECTOR ( 31 downto 0 );
      o_V_0 : out STD_LOGIC_VECTOR ( 31 downto 0 );
      o_W_0 : out STD_LOGIC_VECTOR ( 31 downto 0 );
      pl_clock : in STD_LOGIC;
      reset_rtl : in STD_LOGIC
  );
  end component test_Trifa_Clark_PhaseSaw_wrapper;

  -- component PhaseSawGen is
  --   generic (
  --     G_CLK_FREQ : real := 1.0e8;
  --     G_F_SINE   : real := 50.0
  --   );
  --   port (
  --     i_clk   : in  std_logic;
  --     i_rst   : in  std_logic;
  --     i_sin   : in  sfixed(7 downto -24);
  --     o_angle : out std_logic_vector(10 downto 0)
  --   );
  -- end component PhaseSawGen;

begin

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
      test_enable_SVM <= '0';   
      test_rst_in <= '1';
      wait for (2*PER2);
      report "Begin";
      test_rst_in <= '0';
      test_enable_SVM <= '1';
      wait;
    end process InitTest;


  CambioVeloc : process
    begin
      alfa_Output <= phase50_angle;
      wait for 45 ms;
      report "Change Frequency to 100Hz";
      alfa_Output <= phase100_angle;
      wait for 45 ms;
      test_enable_SVM <= '0';
      wait;
    end process CambioVeloc;
  -- Instance: PhaseSawGen with G_F_SINE = 50 -> Vi
  PhaseSawGen_50 : entity work.PhaseSawGen
    generic map (
      G_CLK_FREQ => CLK_FREQ,
      G_F_SINE   => 50.0
    )
    port map (
      i_clk   => test_clk_in,
      i_rst   => test_rst_in,
      i_sin   => to_sfixed(w_alfa_Vi, 7, -24),
      o_angle => phase50_angle
    );

  -- Instance: PhaseSawGen with G_F_SINE = 100
  PhaseSawGen_100 : entity work.PhaseSawGen
    generic map (
      G_CLK_FREQ => CLK_FREQ,
      G_F_SINE   => 100.0
    )
    port map (
      i_clk   => test_clk_in,
      i_rst   => test_rst_in,
      i_sin   => to_sfixed(w_alfa_Io, 7, -24),
      o_angle => phase100_angle
    );

  test_Trifa_Clark_PhaseSaw_i: test_Trifa_Clark_PhaseSaw_wrapper
    port map (
      --Salidas de T.Clark
      alfa_Io => w_alfa_Io,
      alfa_Vi => w_alfa_Vi,
      beta_Io => open,
      
      --Parametros del Modulador
      i_al_o_0 => alfa_Output,
      i_be_i_0 => phase50_angle,
      i_q_i_0 => PARAM_Qi,
      i_phi_i_0 => PARAM_PHIi,

      --Parametros de la RL
      i_c_a0_0 => COEF_ALPHA_01,
      i_c_a1_0 => COEF_ALPHA_01,
      i_c_b1_0 => COEF_BETA1,
      
      --Salidas de la RL
      o_U_0 => o_U_0,
      o_V_0 => o_V_0,
      o_W_0 => o_W_0,

      --Señales de control
      pl_clock => test_clk_in,
      reset_rtl => test_rst_in,
      i_enable_SVM => '1'
    );
end tb;
