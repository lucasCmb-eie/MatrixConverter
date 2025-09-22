library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;
use std.env.all;

entity tb_DienteSierraGen is
end tb_DienteSierraGen;

architecture Behavioral of tb_DienteSierraGen is
    -- Constantes para configurar el test
    constant C_CLK_FREQ_HZ   : integer := 100000000; -- 100 MHz
    constant C_CLK_PERIOD    : time    := 1 sec / C_CLK_FREQ_HZ; -- Calcula el periodo del clock (10 ns)
    constant C_DELTA        : sfixed(7 downto -24) := to_sfixed(0.000003141, 7, -24); -- Incremento para 50 Hz
    -- Señales para conectar al DUT
    signal w_clk        : std_logic := '0';
    signal w_rst        : std_logic;
    signal w_std_sawtooth   : STD_LOGIC_VECTOR(31 downto 0);
    signal w_sawtooth      : sfixed(7 downto -24);


begin
    
    w_std_sawtooth <= to_slv(w_sawtooth);
    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    -- 3. Instanciación del DUT (Device Under Test)
    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    Sawtooth : entity work.DienteSierraGen
    port map (
        i_clk       => w_clk,
        i_rst       => w_rst,
        i_delta     => C_DELTA,
        o_saw       => w_sawtooth
    );

    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    -- 4. Generador de Reloj (Clock)
    --    Este proceso corre indefinidamente, generando el w_clk.
    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    clk_process : process
    begin
        w_clk <= '0';
        wait for C_CLK_PERIOD / 2; -- Espera medio periodo (5 ns)
        w_clk <= '1';
        wait for C_CLK_PERIOD / 2; -- Espera el otro medio periodo (5 ns)
    end process clk_process;

    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    -- 5. Proceso de Estímulo
    --    Aquí se controla el reset y la duración de la simulación.
    --=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    stimulus_process : process
    begin
        report "Inicio del Testbench para sawtooth_generator...";

        -- Aplicar pulso de reset
        w_rst <= '1';
        wait for 10 * C_CLK_PERIOD; -- Mantener el reset por 10 ciclos
        w_rst <= '0';
        report "Reset liberado, la simulación comienza.";

        -- Esperar un tiempo para ver la salida
        -- La frecuencia de salida es 1 kHz, su periodo es 1 ms.
        -- Esperamos 3 ms para ver 3 ciclos completos de la onda.
        wait;

        report "Simulación completada." severity note;
       
        
    end process stimulus_process;


end Behavioral;
