library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vectores_pr_pkg.all;

--! TB unitario de PR_2int contra los vectores del modelo de oro en Python.
--!
--! VHDL-93 a proposito: tiene que correr bajo GHDL 0.29, que no soporta
--! VHDL-2008 ni ieee.fixed_pkg. Regenerar los vectores con:
--!   python SW/python/ModeloControlPR.py vectores
entity tb_PR_2int is
end entity tb_PR_2int;

architecture sim of tb_PR_2int is
    constant PER : time := 100 ns;          -- 10 MHz

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal en  : std_logic := '0';
    signal sat : std_logic := '0';
    signal e   : signed(31 downto 0) := (others => '0');
    signal u   : signed(31 downto 0);
    signal x1  : signed(47 downto 0);
    signal x2  : signed(47 downto 0);
    signal fin : boolean := false;
begin

    clk <= not clk after PER / 2 when not fin else '0';

    dut : entity work.PR_2int
        port map (i_clk => clk, i_rst => rst, i_en => en, i_sat => sat,
                  i_k => K_PR, i_b => B_PR, i_kp => KP_PR,
                  i_e => e, o_u => u, o_x1 => x1, o_x2 => x2);

    estimulo : process
        variable errores : integer := 0;
    begin
        wait for 4 * PER;
        rst <= '0';
        wait until rising_edge(clk);

        -- Review Focus 1: el resonante ideal no amortigua, asi que cualquier
        -- basura inicial se queda para siempre. El reset TIENE que dejar los
        -- estados exactamente en cero.
        --
        -- Ojo: asertar cero aca sin ensuciar antes NO prueba nada, porque los
        -- signals de PR_2int estan inicializados a cero en su declaracion y
        -- la asercion pasaria aunque la rama de reset no existiera. Primero
        -- se ensucia el estado, se verifica que quedo sucio, y RECIEN AHI se
        -- pulsa el reset.
        for n in 0 to 39 loop
            e   <= VEC_E(n);
            sat <= '0';
            en  <= '1';
            wait until rising_edge(clk);
            en  <= '0';
            wait until rising_edge(clk);
        end loop;

        assert x1 /= to_signed(0, 48) or x2 /= to_signed(0, 48)
            report "el estimulo no logro ensuciar el estado; el test de reset "
                 & "no probaria nada" severity failure;

        rst <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        assert x1 = to_signed(0, 48) and x2 = to_signed(0, 48)
            report "el reset no dejo x1/x2 en cero" severity failure;

        for n in 0 to N_VEC - 1 loop
            e   <= VEC_E(n);
            sat <= VEC_SAT(n);
            en  <= '1';
            wait until rising_edge(clk);
            en  <= '0';
            wait until rising_edge(clk);

            if x1 /= VEC_X1(n) or x2 /= VEC_X2(n) or u /= VEC_U(n) then
                errores := errores + 1;
                report "vector " & integer'image(n) &
                       ": x1 esperado " & integer'image(to_integer(VEC_X1(n)(43 downto 12))) &
                       " obtenido "     & integer'image(to_integer(x1(43 downto 12))) &
                       " | u esperado " & integer'image(to_integer(VEC_U(n))) &
                       " obtenido "     & integer'image(to_integer(u))
                    severity error;
            end if;
            exit when errores > 5;
        end loop;

        assert errores = 0
            report "PR_2int difiere del modelo en " & integer'image(errores) &
                   " vectores" severity failure;
        report "PR_2int: " & integer'image(N_VEC) & " vectores OK" severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
