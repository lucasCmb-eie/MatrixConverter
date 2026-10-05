library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! TB unitario de TrgRetardo. VHDL-93 para que corra bajo GHDL 0.29.
--!
--! Lo que tiene que quedar fijado:
--!   - el pulso sale retardo+1 ciclos despues del flanco de i_trg
--!   - es UN ciclo, no un nivel (CaptureBank detecta flanco)
--!   - un solo pulso por flanco, aunque i_trg quede alto
--!   - un flanco nuevo mientras cuenta REARRANCA la cuenta
--!   - el reset limpia todo
entity tb_TrgRetardo is
end entity tb_TrgRetardo;

architecture sim of tb_TrgRetardo is
    constant PER : time := 100 ns;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal trg     : std_logic := '0';
    signal retardo : std_logic_vector(10 downto 0) := (others => '0');
    signal o_trg   : std_logic;
    signal fin     : boolean := false;
begin

    clk <= not clk after PER / 2 when not fin else '0';

    dut : entity work.TrgRetardo
        port map (i_clk => clk, i_rst => rst, i_trg => trg,
                  i_retardo => retardo, o_trg => o_trg);

    estimulo : process
        -- Cuenta ciclos hasta ver el pulso. Devuelve -1 si no llega en el
        -- limite, para distinguir "tarde" de "nunca".
        --
        -- El `wait for 1 ns` NO es cosmetico: `wait until rising_edge(clk)`
        -- reanuda EN el flanco, antes de que se apliquen las actualizaciones de
        -- ese flanco, asi que leer o_trg ahi devuelve el valor del ciclo
        -- ANTERIOR y toda la medicion sale corrida en uno.
        procedure medir (limite : in integer; ciclos : out integer) is
            variable n : integer := 0;
        begin
            ciclos := -1;
            while n <= limite loop
                wait until rising_edge(clk);
                wait for 1 ns;
                n := n + 1;
                if o_trg = '1' then
                    ciclos := n;
                    return;
                end if;
            end loop;
        end procedure medir;

        -- Verifica que el pulso dure UN solo ciclo.
        procedure chequear_un_ciclo (etiqueta : in string) is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
            assert o_trg = '0'
                report "el pulso duro mas de un ciclo en " & etiqueta
                severity failure;
        end procedure chequear_un_ciclo;

        variable n : integer;
    begin
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- ---- retardo = 0: el pulso sale al ciclo siguiente del flanco ----
        retardo <= (others => '0');
        wait until rising_edge(clk);
        trg <= '1';
        medir(10, n);
        assert n = 1
            report "con retardo=0 el pulso tendria que salir en 1 ciclo y salio en "
                   & integer'image(n) severity failure;
        chequear_un_ciclo("retardo=0");
        trg <= '0';
        wait until rising_edge(clk);

        -- ---- i_trg sigue alto: NO tiene que volver a disparar ----
        trg <= '1';
        wait until rising_edge(clk);
        medir(20, n);
        assert n = -1
            report "i_trg alto volvio a disparar: detecta nivel y no flanco"
            severity failure;
        trg <= '0';
        wait until rising_edge(clk);
        report "NIVEL OK: solo dispara por flanco" severity note;

        -- ---- retardo = 5 ----
        retardo <= std_logic_vector(to_unsigned(5, 11));
        wait until rising_edge(clk);
        trg <= '1';
        medir(30, n);
        assert n = 6
            report "con retardo=5 el pulso tendria que salir en 6 ciclos y salio en "
                   & integer'image(n) severity failure;
        chequear_un_ciclo("retardo=5");
        trg <= '0';
        wait until rising_edge(clk);

        -- ---- retardo = 2047, el maximo que entra en 11 bits ----
        -- El pulso sale en retardo+1 = 2048 ciclos, o sea un Ts completo: por
        -- eso el barrido util es 0..2046, que es la ventana sin chocar con el
        -- disparo siguiente.
        -- El estimulo es el MISMO patron que los de arriba -- trg sube y medir
        -- arranca en el acto -- porque un `wait` de mas entre los dos consume
        -- el ciclo de deteccion del flanco y corre la cuenta en uno. Que el
        -- pulso no necesite trg sostenido ya lo cubre el test de nivel.
        retardo <= std_logic_vector(to_unsigned(2047, 11));
        wait until rising_edge(clk);
        trg <= '1';
        medir(3000, n);
        assert n = 2048
            report "con retardo=2047 el pulso tendria que salir en 2048 ciclos y salio en "
                   & integer'image(n) severity failure;
        chequear_un_ciclo("retardo=2047");
        trg <= '0';
        wait until rising_edge(clk);
        report "RETARDOS OK: 0, 5 y 2047" severity note;

        -- ---- un flanco nuevo mientras cuenta REARRANCA ----
        -- Se dispara con retardo grande, se espera poco, y se vuelve a
        -- disparar: el pulso tiene que medirse desde el SEGUNDO flanco.
        retardo <= std_logic_vector(to_unsigned(20, 11));
        wait until rising_edge(clk);
        trg <= '1';
        wait until rising_edge(clk);
        trg <= '0';
        for k in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        trg <= '1';                     -- segundo flanco, a mitad de la cuenta
        medir(40, n);
        assert n = 21
            report "el flanco nuevo no rearranco la cuenta: el pulso salio en "
                   & integer'image(n) & " y se esperaba 21" severity failure;
        trg <= '0';
        wait until rising_edge(clk);
        report "REARRANQUE OK" severity note;

        -- ---- el reset limpia la cuenta en curso ----
        retardo <= std_logic_vector(to_unsigned(50, 11));
        wait until rising_edge(clk);
        trg <= '1';
        wait until rising_edge(clk);
        trg <= '0';
        for k in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '1';
        wait until rising_edge(clk);
        rst <= '0';
        medir(100, n);
        assert n = -1
            report "el reset no abortó la cuenta: salio un pulso despues"
            severity failure;
        report "RESET OK" severity note;

        report "TrgRetardo OK" severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
