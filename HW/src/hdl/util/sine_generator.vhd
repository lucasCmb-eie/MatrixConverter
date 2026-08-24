library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sine_lut_pkg.all;

--!
-- Generador senoidal por NCO (acumulador de fase de 32 bits + LUT).
--
-- El bloque esta pensado para un reloj de 10 MHz. La frecuencia de salida no se
-- fija por generico: la impone el step (Frequency Tuning Word) que entra por
-- 'frec_inp', de modo que se puede variar en tiempo de ejecucion.
--
--     f_out = frec_inp * f_clk / 2**32
--     frec_inp = round(f_out * 2**32 / f_clk)
--
-- Para f_clk = 10 MHz queda frec_inp = round(f_out * 429.4967296):
--
--     50 Hz -> 21475 (x"000053E3")      60 Hz -> 25770 (x"000064AA")
--
-- Cambiar 'frec_inp' en caliente es seguro: altera la pendiente del acumulador
-- de fase, no su valor, asi que la senoide no da saltos de fase.
entity sine_generator is
    generic (
        -- fase inicial de la Senoide
        PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
    );
    port (
        clk   : in  std_logic;  --! Entrada de Clock : 10 MHz
        reset : in  std_logic;
        --! Step del NCO. Por defecto 21475 = 50 Hz con reloj de 10 MHz.
        frec_inp : in  std_logic_vector(31 downto 0) := x"000053E3";
        -- Salida de la onda senoidal en formato Q8.24
        sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
    );
end entity sine_generator;

architecture rtl of sine_generator is

    -- Parámetros del NCO
    constant PHASE_ACCUM_WIDTH : integer := 32;

    -- Señales internas
    signal freq_tuning_word  : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0);
    signal phase_accumulator : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := PHASE_INITIAL;
    signal lut_address       : unsigned(LUT_ADDR_WIDTH - 1 downto 0);

begin

    -- El step entra directo al acumulador: ya no hay tabla de palabras de
    -- sintonia pre-calculadas ni seleccion por frecuencia de reloj.
    freq_tuning_word <= unsigned(frec_inp);

    -- Proceso del NCO: Acumulador de Fase
    nco_process : process (clk, reset)
    begin
        if reset = '1' then
            -- Carga el valor del genérico, convirtiéndolo a unsigned.
            phase_accumulator <= PHASE_INITIAL;
        elsif rising_edge(clk) then
            phase_accumulator <= phase_accumulator + freq_tuning_word;
        end if;
    end process nco_process;

    -- El resto del código no cambia
    lut_address <= phase_accumulator(PHASE_ACCUM_WIDTH - 1 downto PHASE_ACCUM_WIDTH - LUT_ADDR_WIDTH);

    lut_process : process (lut_address)
    begin
        sine_out <= SINE_TABLE(to_integer(lut_address));
    end process lut_process;

end architecture rtl;
