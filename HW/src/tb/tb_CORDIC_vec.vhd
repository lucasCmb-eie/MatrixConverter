library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! TB del CORDIC en modo vectoring: verifica el modulo ademas del angulo.
--! VHDL-93 para que corra bajo GHDL 0.29.
entity tb_CORDIC_vec is
end entity tb_CORDIC_vec;

architecture sim of tb_CORDIC_vec is
    constant PER : time := 100 ns;
    constant UNO : integer := 16777216;           -- 1,0 en Q8.24

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal x_in  : signed(31 downto 0) := (others => '0');
    signal y_in  : signed(31 downto 0) := (others => '0');
    signal ang   : unsigned(10 downto 0);
    signal mag   : signed(31 downto 0);
    signal done  : std_logic;
    signal fin   : boolean := false;
begin

    clk <= not clk after PER / 2 when not fin else '0';

    dut : entity work.CORDIC_atan2
        port map (clk => clk, rst => rst, start => start,
                  x_in => x_in, y_in => y_in,
                  angle_out => ang, mag_out => mag, done => done);

    estimulo : process

        procedure medir (x, y : in integer) is
        begin
            x_in  <= to_signed(x, 32);
            y_in  <= to_signed(y, 32);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            wait until done = '1';
            wait until rising_edge(clk);
        end procedure medir;

    begin
        wait for 4 * PER;
        rst <= '0';
        wait until rising_edge(clk);

        -- (1, 0): modulo 1, angulo 0.
        medir(UNO, 0);
        assert abs(to_integer(mag) - UNO) < UNO / 200
            report "modulo de (1,0) mal: " & integer'image(to_integer(mag))
            severity failure;
        assert to_integer(ang) < 8 or to_integer(ang) > 2040
            report "angulo de (1,0) mal: " & integer'image(to_integer(ang))
            severity failure;

        -- (0, 2): modulo 2, angulo 90 grados = 512 cuentas.
        medir(0, 2 * UNO);
        assert abs(to_integer(mag) - 2 * UNO) < UNO / 100
            report "modulo de (0,2) mal: " & integer'image(to_integer(mag))
            severity failure;
        assert abs(to_integer(ang) - 512) < 8
            report "angulo de (0,2) mal: " & integer'image(to_integer(ang))
            severity failure;

        -- (-1, -1): modulo sqrt(2) = 1,41421, angulo 225 grados = 1280.
        medir(-UNO, -UNO);
        assert abs(to_integer(mag) - 23726566) < UNO / 100
            report "modulo de (-1,-1) mal: " & integer'image(to_integer(mag))
            severity failure;
        assert abs(to_integer(ang) - 1280) < 8
            report "angulo de (-1,-1) mal: " & integer'image(to_integer(ang))
            severity failure;

        -- Review Focus 4: (0,0) tiene que dar modulo exactamente cero, para
        -- que el lazo quede en q=0 y no en un angulo basura que mueva la
        -- matriz. El angulo que salga es irrelevante.
        medir(0, 0);
        assert to_integer(mag) = 0
            report "(0,0) no dio modulo cero: " & integer'image(to_integer(mag))
            severity failure;

        report "CORDIC_vec OK" severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
