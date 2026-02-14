library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity PhaseSawGen is
    generic (
        G_CLK_FREQ  : real := 1.0e8; -- Frecuencia de reloj (Hz)
        G_SAW_FREQ  : real := 50.0;  -- Frecuencia DESEADA de la diente de sierra (Hz)
        INT_BITS    : integer := 8;
        FRAC_BITS   : integer := 24
    );
    port (
        i_clk       : in  std_logic;
        i_rst       : in  std_logic;
        
        i_sin       : in  std_logic_vector(31 downto 0);
        o_angle     : out std_logic_vector(10 downto 0)
    );
end entity;

architecture sim of PhaseSawGen is
    constant C_PHASE_BITS : integer := 11;
    -- Usamos real para mantener la precisión en simulación
    constant C_PHASE_MAX  : real    := 2.0**C_PHASE_BITS;
    
    -- Calculamos el paso exacto basado en los generics
    -- Delta = (Max_Cuentas * Frec_Objetivo) / Frec_Reloj
    constant C_DELTA      : real    := (C_PHASE_MAX * G_SAW_FREQ) / G_CLK_FREQ;

    signal phase_acc  : unsigned(C_PHASE_BITS-1 downto 0) := (others => '0');

begin

    process(i_clk, i_rst)
        variable phase_real : real := 0.0;
    begin
        if i_rst = '1' then
            phase_acc  <= (others => '0');
            phase_real := 0.0;
        elsif rising_edge(i_clk) then
            
            -- Acumulador simple (Integrador)
            phase_real := phase_real + C_DELTA;

            -- Manejo de desbordamiento (Wrap around)
            -- Al llegar al máximo, restamos el máximo para volver a empezar
            -- manteniendo el remanente decimal para precisión perfecta.
            if phase_real >= C_PHASE_MAX then
                phase_real := phase_real - C_PHASE_MAX;
            end if;

            -- Conversión a salida
            phase_acc <= to_unsigned(integer(phase_real), C_PHASE_BITS);
            
        end if;
    end process;

    o_angle <= std_logic_vector(phase_acc);

end architecture;