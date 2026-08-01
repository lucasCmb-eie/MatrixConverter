library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sine_lut_pkg.all;

entity sine_generator is
    generic (
        -- fase inicial de la Senoide
        PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        frec_inp : in  std_logic_vector(1 downto 0);
        -- Salida de la onda senoidal en formato Q8.24
        sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
    );
end entity sine_generator;

architecture rtl of sine_generator is

    -- Parámetros del NCO
    constant PHASE_ACCUM_WIDTH : integer := 32;

    -- Palabras de sintonía para 50 Hz pre-calculadas
    constant FTW_100MHZ : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := to_unsigned(2147, PHASE_ACCUM_WIDTH);
    constant FTW_10MHZ  : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := to_unsigned(21475, PHASE_ACCUM_WIDTH);
    constant FTW_1MHZ   : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := to_unsigned(214748, PHASE_ACCUM_WIDTH);

    -- Señales internas
    signal freq_tuning_word  : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0);
    signal phase_accumulator : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := (others => '0');
    signal lut_address       : unsigned(LUT_ADDR_WIDTH - 1 downto 0);

begin

    freq_mux_process : process(frec_inp)
    begin
        case frec_inp is
            when "00" => 
                freq_tuning_word <= FTW_1MHZ;
            when "01" => 
                freq_tuning_word <= FTW_10MHZ;
            when others =>
                freq_tuning_word <= FTW_100MHZ;
        end case;
    end process;


    -- Proceso del NCO: Acumulador de Fase
    nco_process : process (clk, reset)
    begin
        if reset = '1' then
            -- Carga el valor del genérico, convirtiéndolo a unsigned.
            phase_accumulator <= PHASE_INITIAL;
        end if;

        if rising_edge(clk) then
    
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