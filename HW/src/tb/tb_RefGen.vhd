library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! TB unitario de RefGen: amplitud, cuadratura y sentido de giro.
--! VHDL-93 para que corra bajo GHDL 0.29.
entity tb_RefGen is
end entity tb_RefGen;

architecture sim of tb_RefGen is
    constant PER  : time := 100 ns;
    -- paso_nco(50 Hz) * 2048, porque RefGen avanza una vez por Ts.
    constant PASO : unsigned(31 downto 0) := to_unsigned(21475 * 2048, 32);
    constant AMP  : signed(31 downto 0) := to_signed(8388608, 32);  -- 0,5 en Q8.24

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';
    signal en   : std_logic := '0';
    signal alfa : signed(31 downto 0);
    signal beta : signed(31 downto 0);
    signal fin  : boolean := false;
begin

    clk <= not clk after PER / 2 when not fin else '0';

    dut : entity work.RefGen
        port map (i_clk => clk, i_rst => rst, i_en => en,
                  i_paso => PASO, i_amp => AMP,
                  o_alfa => alfa, o_beta => beta, o_theta => open);

    estimulo : process
        variable pico   : integer := 0;
        variable r2     : integer;
        variable r2_min : integer := integer'high;
        variable r2_max : integer := 0;
        variable a_i, b_i : integer;
        variable a_0, b_0 : integer := 0;
        variable a_1, b_1 : integer := 0;

        procedure avanzar is
        begin
            en <= '1';
            wait until rising_edge(clk);
            en <= '0';
            wait until rising_edge(clk);
        end procedure avanzar;
    begin
        wait for 4 * PER;
        rst <= '0';
        wait until rising_edge(clk);

        -- Un periodo de 50 Hz son 1/50/Ts = 97,66 pasos de control.
        -- Trabajamos en unidades de 2^-14 para que los cuadrados entren en
        -- el integer de 32 bits de VHDL-93.
        for n in 0 to 97 loop
            avanzar;
            a_i := to_integer(alfa(31 downto 14));
            b_i := to_integer(beta(31 downto 14));
            if n = 0 then
                a_0 := a_i; b_0 := b_i;
            elsif n = 1 then
                a_1 := a_i; b_1 := b_i;
            end if;
            if abs(a_i) > pico then
                pico := abs(a_i);
            end if;
            r2 := a_i * a_i + b_i * b_i;
            if r2 < r2_min then r2_min := r2; end if;
            if r2 > r2_max then r2_max := r2; end if;
        end loop;

        -- 0,5 en Q8.24 truncado a 18 bits utiles = 512 cuentas.
        assert abs(pico - 512) <= 8
            report "amplitud fuera de rango: " & integer'image(pico)
            severity failure;

        -- Cuadratura: alfa^2 + beta^2 constante dentro del 3 %.
        assert (r2_max - r2_min) * 100 < 3 * r2_max
            report "alfa y beta no estan en cuadratura" severity failure;

        -- Sentido de giro: el modelo define alfa = A*cos(th), beta = A*sin(th),
        -- asi que el primer paso arranca en (A, 0) y beta tiene que CRECER.
        -- Si estuviera al reves (alfa=sen, beta=cos) la secuencia seria
        -- negativa y el lazo perseguiria una referencia en contrafase.
        assert abs(a_0 - 512) <= 8 and abs(b_0) <= 8
            report "el primer paso no es (A, 0): alfa=" & integer'image(a_0) &
                   " beta=" & integer'image(b_0) severity failure;
        assert b_1 > b_0
            report "secuencia invertida: beta no crece en el segundo paso"
            severity failure;

        report "RefGen OK: pico = " & integer'image(pico) severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
