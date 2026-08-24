library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_CaptureBank is
end entity tb_CaptureBank;

architecture sim of tb_CaptureBank is
    constant PER2 : time := 50 ns;              -- 10 MHz
    signal clk, rst, capture : std_logic := '0';
    signal sel  : std_logic_vector(31 downto 0) := (others => '0');
    signal d    : std_logic_vector(31 downto 0);
    signal done : boolean := false;

    type slv32_t is array (0 to 12) of std_logic_vector(31 downto 0);
    signal src : slv32_t := (others => (others => '0'));

    procedure check (signal   got : in std_logic_vector(31 downto 0);
                     constant exp : in std_logic_vector(31 downto 0);
                     constant msg : in string) is
    begin
        assert got = exp
            report msg & ": esperado " & integer'image(to_integer(unsigned(exp))) &
                   " y se leyo " & integer'image(to_integer(unsigned(got)))
            severity failure;
    end procedure;
begin
    clk <= not clk after PER2 when not done else '0';

    uut : entity work.CaptureBank
        port map (i_clk => clk, i_rst => rst, i_capture => capture, i_sel => sel,
                  i_d00 => src(0),  i_d01 => src(1),  i_d02 => src(2),
                  i_d03 => src(3),  i_d04 => src(4),  i_d05 => src(5),
                  i_d06 => src(6),  i_d07 => src(7),  i_d08 => src(8),
                  i_d09 => src(9),  i_d10 => src(10),
                  i_d11 => src(11), i_d12 => src(12),
                  o_data => d);

    estimulo : process
    begin
        -- 1) reset deja los registros en cero
        rst <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);
        rst <= '0';
        wait for 1 ns;
        check(d, x"00000000", "tras reset, sel=0");

        -- 2) captura: 13 valores distintos, un pulso, y se leen todos
        for k in 0 to 12 loop
            src(k) <= std_logic_vector(to_unsigned(16#A0# + k, 32));
        end loop;
        wait until rising_edge(clk);
        capture <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        capture <= '0';
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)), "lectura sel=" & integer'image(k));
        end loop;
        report "CAPTURA OK: los 13 registros se leen";

        -- 3) coherencia: cambiar las fuentes NO cambia lo capturado
        for k in 0 to 12 loop
            src(k) <= std_logic_vector(to_unsigned(16#5000# + k, 32));
        end loop;
        wait until rising_edge(clk); wait until rising_edge(clk);
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)),
                  "coherencia sel=" & integer'image(k));
        end loop;
        report "COHERENCIA OK: los registros no siguen a la entrada";

        -- 4) selector fuera de rango devuelve cero, incluso con el bit 31 en 1
        for v in 0 to 2 loop
            case v is
                when 0 => sel <= std_logic_vector(to_unsigned(13, 32));
                when 1 => sel <= std_logic_vector(to_unsigned(100, 32));
                when others => sel <= x"FFFFFFFF";
            end case;
            wait for 1 ns;
            check(d, x"00000000", "fuera de rango");
        end loop;
        report "FUERA DE RANGO OK";

        report "TODAS LAS VERIFICACIONES OK";
        done <= true;
        wait;
    end process;
end architecture sim;
