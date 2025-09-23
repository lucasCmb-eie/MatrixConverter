library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity DienteSierraGen is
    port (
        i_clk     : in  std_logic;
        i_rst   : in  std_logic;
        i_k       : in  unsigned(11 downto 0); -- factor K (1..2000 aprox)
        o_saw     : out sfixed(7 downto -24)   -- salida Q8.24
    );
end entity;

architecture rtl of DienteSierraGen is
    -- Constante PI en Q8.24
    constant C_PI   : sfixed(8 downto -24) := to_sfixed(3.14159265, 8, -24);

    -- Step mínimo (corresponde a 50 Hz deseados -> 100 Hz reales de sierra)
    constant C_STEP : sfixed(7 downto -24) :=
        to_sfixed(3.14159265 * (2.0 * 50.0) / real(100_000_000), 7, -24);

    signal r_acc   : sfixed(7 downto -24) := to_sfixed(0.0, 7, -24);
    signal delta_k : sfixed(7 downto -24);
begin

    -- Multiplicación: step fijo * K
    delta_k <= resize(C_STEP * to_integer(i_k), 7, -24);

    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            r_acc <= to_sfixed(0.0, 7, -24);
        end if;

        if rising_edge(i_clk) then
            if (r_acc + delta_k) >= C_PI then
                r_acc <= resize((r_acc + delta_k) - C_PI, 7, -24);
            else
                r_acc <= resize(r_acc + delta_k, 7, -24);
            end if;
        end if;
    end process;

    o_saw <= r_acc;

end architecture;