library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! TB unitario de CtrlRegs. VHDL-93 para que corra bajo GHDL 0.29.
entity tb_CtrlRegs is
end entity tb_CtrlRegs;

architecture sim of tb_CtrlRegs is
    constant PER : time := 100 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal trg : std_logic := '0';
    signal wr_data : std_logic_vector(31 downto 0) := (others => '0');
    signal wr_idx  : std_logic_vector(3 downto 0)  := (others => '0');
    signal wr_stb  : std_logic := '0';

    signal frec_in, paso_ref, amp_ref : std_logic_vector(31 downto 0);
    signal kp, b_kr, q_max, inv_vi    : std_logic_vector(31 downto 0);
    signal k      : std_logic_vector(24 downto 0);
    signal phi_i  : std_logic_vector(10 downto 0);
    signal freeze : std_logic;
    signal clamp  : std_logic_vector(15 downto 0);
    signal fin    : boolean := false;
begin

    clk <= not clk after PER / 2 when not fin else '0';

    dut : entity work.CtrlRegs
        port map (i_clk => clk, i_rst => rst, i_trg => trg,
                  i_wr_data => wr_data, i_wr_idx => wr_idx, i_wr_stb => wr_stb,
                  o_frec_in => frec_in, o_paso_ref => paso_ref,
                  o_amp_ref => amp_ref, o_k => k, o_kp => kp, o_b => b_kr,
                  o_phi_i => phi_i, o_q_max => q_max, o_inv_vi => inv_vi,
                  o_freeze => freeze, o_clamp => clamp);

    estimulo : process

        --! Una escritura del PS: dato, despues idx+stb, despues stb='0'.
        --! Son tres transacciones AXI separadas; el strobe es lo que hace que
        --! la no-atomicidad entre ellas no importe.
        procedure escribir (idx : in integer; dato : in integer) is
        begin
            wr_data <= std_logic_vector(to_signed(dato, 32));
            wr_idx  <= std_logic_vector(to_unsigned(idx, 4));
            wait until rising_edge(clk);
            wr_stb  <= '1';
            wait until rising_edge(clk);
            wr_stb  <= '0';
            wait until rising_edge(clk);
        end procedure escribir;

        --! El commit se materializa en el proximo flanco de i_trg.
        procedure pulso_trg is
        begin
            trg <= '1';
            wait until rising_edge(clk);
            trg <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure pulso_trg;

    begin
        wait for 4 * PER;
        rst <= '0';
        wait until rising_edge(clk);

        -- ---- defaults: el lazo tiene que arrancar INERTE ----
        assert frec_in = x"000053E3"
            report "default de frec_in mal" severity failure;
        assert k = std_logic_vector(to_signed(16#1077D9#, 25))
            report "default de k mal" severity failure;
        assert q_max = x"00DDB3D7"
            report "default de q_max mal" severity failure;
        assert amp_ref = x"00000000" and kp = x"00000000" and b_kr = x"00000000"
            report "el lazo NO arranca inerte: amp_ref/Kp/b deberian ser 0"
            severity failure;
        assert freeze = '1'
            report "el anti-windup deberia arrancar activo" severity failure;

        -- ---- los defaults de k y paso_ref tienen que ser la MISMA f_o ----
        -- El spec 6.5 lo pide como chequeo: si k dice 50 Hz y paso_ref dice
        -- otra cosa, el resonante arranca sintonizado a una frecuencia
        -- distinta de la referencia y nadie se entera hasta ver el error de
        -- regimen.
        --   paso_ref = round(f*2**32/10e6) * 2048
        --   k        = 2*sin(pi*f*Ts) en Q1.24
        -- Para f = 50 Hz: 21475*2048 = 0x029F0800 y k = 0x1077D9.
        assert paso_ref = x"029F0800"
            report "el default de paso_ref no es 50 Hz" severity failure;
        assert k = std_logic_vector(to_signed(16#1077D9#, 25))
            report "k y paso_ref arrancan en frecuencias distintas"
            severity failure;

        -- ---- una escritura no se ve hasta el commit ----
        escribir(2, 1677722);              -- amp_ref = 0,10 pu
        assert amp_ref = x"00000000"
            report "la escritura se vio SIN commit: el shadow no esta aislando"
            severity failure;
        escribir(15, 0);                   -- pide commit
        assert amp_ref = x"00000000"
            report "el commit se aplico sin esperar a i_trg" severity failure;
        pulso_trg;
        assert amp_ref = std_logic_vector(to_signed(1677722, 32))
            report "el commit no llego al banco activo" severity failure;

        -- ---- Review Focus 1: indices sin asignar no escriben nada ----
        escribir(11, 16#DEADBEE#);
        escribir(15, 0);
        pulso_trg;
        assert amp_ref = std_logic_vector(to_signed(1677722, 32))
            report "una escritura a un indice sin asignar corrompio el banco"
            severity failure;

        -- ---- Review Focus 2: k >= 2**24 se clampea ----
        -- En 25 bits, 2**24 tiene el bit de signo puesto: el resonante
        -- sintonizaria la secuencia conjugada sin avisar.
        escribir(3, 16#1000000#);          -- k = 1,0 exacto, fuera de Q1.24
        escribir(15, 0);
        pulso_trg;
        assert k = std_logic_vector(to_signed(16#FFFFFF#, 25))
            report "k no se clampeo: quedo " & integer'image(to_integer(signed(k)))
            severity failure;
        assert clamp(3) = '1'
            report "el clampeo de k no dejo rastro en o_clamp" severity failure;
        assert k(24) = '0'
            report "k quedo NEGATIVO; el resonante giraria al reves"
            severity failure;

        -- ---- Review Focus 3: q_max >= 2**24 se clampea ----
        escribir(7, 16#2000000#);
        escribir(15, 0);
        pulso_trg;
        assert q_max = x"00FFFFFF"
            report "q_max no se clampeo" severity failure;
        assert clamp(7) = '1'
            report "el clampeo de q_max no dejo rastro" severity failure;

        -- ---- Review Focus 4: commits degenerados ----
        escribir(15, 0);                   -- commit sin escrituras previas
        pulso_trg;
        pulso_trg;                         -- y un trg de mas
        assert q_max = x"00FFFFFF" and amp_ref = std_logic_vector(to_signed(1677722, 32))
            report "un commit vacio o un trg de mas corrompio el banco activo"
            severity failure;

        -- ---- un trg sin commit pendiente no mueve nada ----
        escribir(2, 999);                  -- escribe al shadow, sin commit
        pulso_trg;
        assert amp_ref = std_logic_vector(to_signed(1677722, 32))
            report "i_trg aplico el shadow sin que nadie pidiera commit"
            severity failure;

        report "CtrlRegs OK" severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
