library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sine_lut_pkgV2.all; 

entity sine_generatorV2 is
    generic (
        PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        
        --Salida explícita en Q3.29
        sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
    );
end entity sine_generatorV2;

architecture rtl of sine_generatorV2 is

    -- Parámetros del NCO
    constant PHASE_ACCUM_WIDTH : integer := 32;
    
    -- Tuning Word para 50 Hz @ 100 MHz
    -- Calc: 50 * 2^32 / 100e6 = 2147.48 -> 2147
    constant FREQ_TUNING_WORD  : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) 
        := to_unsigned(2147, PHASE_ACCUM_WIDTH);

    -- Señales internas
    signal phase_accumulator : unsigned(PHASE_ACCUM_WIDTH - 1 downto 0) := (others => '0');
    signal lut_address       : unsigned(LUT_ADDR_WIDTH - 1 downto 0);
    
begin

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