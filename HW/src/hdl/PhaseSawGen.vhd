library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity PhaseSawGen is
    generic (
        G_CLK_FREQ : real := 1.0e8;  -- frecuencia de reloj (Hz)
        G_F_SINE   : real := 50.0    -- frecuencia de la senoide (Hz)
    );
    port (
        i_clk    : in  std_logic;
        i_rst    : in  std_logic;
        i_sin    : in  sfixed(7 downto -24);
        o_angle  : out std_logic_vector(10 downto 0)
    );
end entity;

architecture rtl of PhaseSawGen is
    constant C_PHASE_BITS   : integer := 11;
    constant C_PHASE_MAX    : integer := 2**C_PHASE_BITS;
    constant C_PERIOD_TICKS : integer := integer(G_CLK_FREQ / G_F_SINE);

    -- incremento de fase por tick
    constant C_DELTA : real := real(C_PHASE_MAX) / real(C_PERIOD_TICKS);

    signal phase_acc  : unsigned(C_PHASE_BITS-1 downto 0) := (others => '0');
    signal sin_d      : sfixed(7 downto -24);
    signal zero_cross : std_logic := '0';
begin

    process(i_clk, i_rst)
        variable phase_real : real := 0.0;
    begin
        if i_rst = '1' then
            phase_acc  <= (others => '0');
            sin_d      <= to_sfixed(0.0, 7, -24);
            zero_cross <= '0';
            phase_real := 0.0;
        elsif rising_edge(i_clk) then
            sin_d <= i_sin;

            -- Detecta cruce por cero ascendente
            if (sin_d < 0.0) and (i_sin >= 0.0) then
                zero_cross <= '1';
            else
                zero_cross <= '0';
            end if;

            if zero_cross = '1' then
                phase_acc  <= (others => '0');
                phase_real := 0.0;
            else
                -- incremento de fase
                phase_real := phase_real + C_DELTA;

                if phase_real >= real(C_PHASE_MAX) then
                    phase_real := phase_real - real(C_PHASE_MAX);
                end if;

                phase_acc <= to_unsigned(integer(phase_real), C_PHASE_BITS);
            end if;
        end if;
    end process;

    o_angle <= std_logic_vector(phase_acc);

end architecture;
