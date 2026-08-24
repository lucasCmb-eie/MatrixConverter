library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Es importante incluir la librería que contiene el paquete de la LUT
use work.sine_lut_pkg.all;

-- La entidad del testbench siempre está vacía
entity sine_generator_tb is
end entity sine_generator_tb;

architecture simulation of sine_generator_tb is

    -- 1. Declaración del Componente a Probar (UUT - Unit Under Test)
    component sine_generator is
        generic (
            PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
        );
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            frec_inp : in  std_logic_vector(31 downto 0);
            sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
        );
    end component sine_generator;

    -- 2. Constantes de Simulación
    constant CLK_FREQUENCY : real    := 10.0e6; -- 10 MHz
    -- Step del NCO para 50 Hz con ese reloj: round(50 * 2**32 / 10e6) = 21475
    constant STEP_50HZ     : std_logic_vector(31 downto 0) := x"000053E3";
    constant CLK_PERIOD    : time    := 1 sec / CLK_FREQUENCY;
    constant SINE_PERIOD   : time    := 20 ms; -- Período de la onda de 50 Hz

    -- 3. Señales para conectar al UUT
    signal tb_clk   : std_logic := '0';
    signal tb_reset : std_logic;
    signal tb_sine_out : signed(SINE_DATA_WIDTH - 1 downto 0);

begin

    -- 4. Instanciación del UUT
    uut_sine_generator : component sine_generator
        port map (
            clk      => tb_clk,
            reset    => tb_reset,
            frec_inp => STEP_50HZ,
            sine_out => tb_sine_out
        );

    -- 5. Proceso para generar el Clock
    -- Este proceso genera una señal de reloj continua con el período definido.
    clk_process : process
    begin
        tb_clk <= '0';
        wait for CLK_PERIOD / 2;
        tb_clk <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_process;

    -- 6. Proceso de Estímulo (el "cerebro" del testbench)
    -- Aquí se definen las acciones a lo largo del tiempo.
    stimulus_process : process
    begin
        report "Iniciando Testbench para sine_generator...";

        -- Aplicar un pulso de reset inicial
        tb_reset <= '1';
        wait for CLK_PERIOD * 10; -- Mantener el reset por 10 ciclos
        tb_reset <= '0';

        report "Reset liberado. El generador comenzará a funcionar.";

        -- Dejar que la simulación corra por 2 períodos de la onda senoidal
        wait for SINE_PERIOD * 2;

        report "Simulación completada después de 2 períodos de la onda de 50 Hz.";

        -- Detener la simulación
        std.env.stop;

    end process stimulus_process;

end architecture simulation;