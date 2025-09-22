library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity DienteSierraGen is
    port (
        i_clk     : in  std_logic;
        i_rst   : in  std_logic;
        i_delta   : in  sfixed(7 downto -24);  -- incremento (Q8.24)
        o_saw     : out sfixed(7 downto -24)   -- salida (Q8.24)
    );
end entity;

architecture rtl of DienteSierraGen is
    constant C_PI : sfixed(8 downto -24) := to_sfixed(3.14159265, 8, -24);
    signal r_acc  : sfixed(7 downto -24) := to_sfixed(0.0, 7, -24);
begin

    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
                r_acc <= to_sfixed(0.0, 7, -24);
        end if;

        if rising_edge(i_clk) then
            -- Acumulador
            if (r_acc + i_delta) >= C_PI then
                r_acc <= resize((r_acc + i_delta) - C_PI, 7, -24);
            else
                r_acc <= resize(r_acc + i_delta, 7, -24);
            end if;
        end if;
    end process;

    o_saw <= resize(r_acc, 7, -24);

end architecture;
