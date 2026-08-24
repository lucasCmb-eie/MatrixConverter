library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_CORDIC_atan2 is
end tb_CORDIC_atan2;

architecture Behavioral of tb_CORDIC_atan2 is

    constant PER2 : time := (10 ns /2);
    -- Step del NCO de AC_Source para 50 Hz con el reloj de 100 MHz de este tb:
    --     round(50 * 2**32 / 100e6) = 2147   ->  49,988 Hz
    constant STEP_50HZ : std_logic_vector(31 downto 0) := x"00000863";
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;

    signal clk : std_logic;
    signal rst : std_logic;

    -- Señales de tension trifasica
    signal tension_fase_U : std_logic_vector(31 downto 0);
    signal tension_fase_V : std_logic_vector(31 downto 0);
    signal tension_fase_W : std_logic_vector(31 downto 0);

    -- Señales T. Clark de tension trifasica
    signal Clark_alfa_Vi : std_logic_vector(31 downto 0);
    signal Clark_beta_Vi : std_logic_vector(31 downto 0);

    -- Salida diente de sierra
    signal angulo_result : unsigned(10 downto 0);

    signal w_trigger : std_logic := '0';
    signal w_ClarkValido : std_logic := '0';
    signal w_AnguloValido : std_logic := '0';

    constant MAX_COUNT : integer := 4000;
    signal counter     : integer range 0 to MAX_COUNT - 1 := 0;

begin
    
    AC: entity work.AC_SOURCE
        port map (
            i_clk => clk,
            i_rst => rst,
            i_frec => STEP_50HZ,

            o_U   => tension_fase_U,
            o_V   => tension_fase_V,
            o_W   => tension_fase_W
        );

    CORDIC : entity work.CORDIC_atan2
        port map (
            clk => clk,
            rst => rst,
            start => w_ClarkValido,

            x_in => signed(Clark_alfa_Vi),
            y_in => signed(Clark_beta_Vi),

            angle_out => angulo_result,
            done => w_AnguloValido
        );

    TClark_Vi: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_start => w_trigger,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_valido => w_ClarkValido,

            o_alfa => Clark_alfa_Vi,
            o_beta => Clark_beta_Vi
        );
    
    process(clk, rst)
    begin
        if rst = '1' then
            counter <= 0;
            w_trigger <= '0';
        elsif rising_edge(clk) then
            if counter = MAX_COUNT - 1 then
                counter <= 0;
                w_trigger <= '1'; -- Pulso activo por 1 ciclo de clk
            else
                counter <= counter + 1;
                w_trigger <= '0';
            end if;
        end if;
    end process;

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
end Behavioral;
