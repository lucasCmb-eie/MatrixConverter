library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Importar el paquete con la LUT generado por Python
library work;
use work.sine_lut_pkg.all;

entity sine_generator is
    generic (
        -- fase inicial de la Senoide
        PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        -- Salida de la onda senoidal en formato Q8.24
        sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
    );
end entity sine_generator;

architecture rtl of sine_generator is

    -- Parámetros del NCO
    constant PHASE_ACCUM_WIDTH : integer := 32;
    -- Palabra de sintonía para 50 Hz con clock de 100 kHz
    constant FREQ_TUNING_WORD  : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0)
        := to_unsigned(integer(50.0 * 2.0**32 / 100_000_000.0), PHASE_ACCUM_WIDTH);
        -- = 2147

    -- Señales internas
    signal phase_accumulator : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := (others => '0');
    signal lut_address       : unsigned(LUT_ADDR_WIDTH - 1 downto 0);

begin

    -- Proceso del NCO: Acumulador de Fase
    nco_process : process (clk, reset)
    begin
        if reset = '1' then
            -- Carga el valor del genérico, convirtiéndolo a unsigned.
            phase_accumulator <= PHASE_INITIAL;
        end if;

        if rising_edge(clk) then
    
            phase_accumulator <= phase_accumulator + FREQ_TUNING_WORD;
        end if;
    end process nco_process;

    -- El resto del código no cambia
    lut_address <= phase_accumulator(PHASE_ACCUM_WIDTH - 1 downto PHASE_ACCUM_WIDTH - LUT_ADDR_WIDTH);

    lut_process : process (lut_address)
    begin
        sine_out <= SINE_TABLE(to_integer(lut_address));
    end process lut_process;

end architecture rtl;