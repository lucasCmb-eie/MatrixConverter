library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! TB unitario de CtrlRegs. VHDL-93 para que corra bajo GHDL 0.29.
entity tb_CtrlRegs is
end entity tb_CtrlRegs;

architecture sim of tb_CtrlRegs is
    constant PER : time := 100 ns;
    --! Ts = 2048 clocks a 10 MHz = 204,8 us
    constant TS_SEG : real := 2048.0 / 10.0e6;
    --! GHDL 0.29 no trae ieee.math_real, asi que PI va como literal
    constant PI_R   : real := 3.14159265358979;
    --! Tolerancia del chequeo de coherencia: un LSB del step del NCO,
    --! 10e6/2**32 = 2,33 mHz. Es la resolucion con que paso_ref puede
    --! expresar una frecuencia, asi que pedir mas seria pedirle a los dos
    --! registros que coincidan mejor de lo que uno de ellos puede. El par
    --! correcto (21475, 0x1077D9) difiere 0,37 mHz; el nibble de menos que
    --! tenia este default difiere 4,3 mHz.
    constant TOL_HZ : real := 10.0e6 / 2.0**32;

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
    signal freeze  : std_logic;
    signal retardo : std_logic_vector(10 downto 0);
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
                  o_freeze => freeze, o_retardo => retardo,
                  o_clamp => clamp);

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

        -- frecuencias derivadas de los registros, para el chequeo de coherencia
        variable f_de_paso : real;
        variable f_de_k    : real;
        -- snapshot del banco activo, para el Review Focus 1
        variable v_frec, v_paso, v_amp, v_kp, v_b, v_q, v_inv : std_logic_vector(31 downto 0);
        variable v_k   : std_logic_vector(24 downto 0);
        variable v_phi : std_logic_vector(10 downto 0);
        variable v_frz : std_logic;
        variable v_ret : std_logic_vector(10 downto 0);
        variable sen_x     : real;
        variable asen_x    : real;

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

        -- inv_vi es la constante que el LAZO ESCONDE: el resonante compensa el
        -- error de ganancia y el regimen da bien igual, asi que si el default no
        -- coincide con el valor con que se validó en XSIM
        -- (tb_ControlCorriente.vhd:62) nada lo delata hasta comparar el q de
        -- regimen contra |v*|/V_i analitico. Por eso se asevera explicito.
        assert inv_vi = x"01EE54BB"
            report "el default de inv_vi no es 32396475 (1/0,5179 en Q8.24), es " &
                   integer'image(to_integer(unsigned(inv_vi))) severity failure;
        assert q_max = x"00DDB3D7"
            report "el default de q_max no es sqrt(3)/2 en Q8.24" severity failure;
        assert clamp = x"0000"
            report "o_clamp deberia arrancar limpio" severity failure;

        -- ---- los defaults de k y paso_ref tienen que ser la MISMA f_o ----
        -- El spec 6.5 lo pide como chequeo: si k dice 50 Hz y paso_ref dice
        -- otra cosa, el resonante arranca sintonizado a una frecuencia
        -- distinta de la referencia y nadie se entera hasta ver el error de
        -- regimen.
        --   paso_ref = round(f*2**32/10e6) * 2048
        --   k        = 2*sin(pi*f*Ts) en Q1.24
        --
        -- OJO: comparar cada registro contra un literal NO chequea esto. Dos
        -- aserciones independientes pasan felices con dos frecuencias
        -- distintas, que es exactamente el bug que esto tiene que cazar. Hay
        -- que DERIVAR la frecuencia de cada uno y compararlas entre si.
        f_de_paso := real(to_integer(unsigned(paso_ref)) / 2048)
                     * 10.0e6 / 2.0**32;
        -- k = 2*sin(pi*f*Ts) -> f = arcsin(k/2) / (pi*Ts). Sin math_real,
        -- arcsin por serie: x + x^3/6 + 3x^5/40. A x ~ 0,032 el error del
        -- truncamiento es ~1e-9, cuatro ordenes menos que los mHz que hay
        -- que resolver.
        sen_x  := real(to_integer(signed(k))) / 2.0**24 / 2.0;
        asen_x := sen_x + (sen_x**3) / 6.0 + 3.0 * (sen_x**5) / 40.0;
        f_de_k := asen_x / (PI_R * TS_SEG);
        report "f(paso_ref) = " & real'image(f_de_paso) &
               " Hz   f(k) = " & real'image(f_de_k) & " Hz";
        assert abs(f_de_paso - f_de_k) < TOL_HZ
            report "k y paso_ref arrancan en frecuencias distintas: " &
                   real'image(f_de_paso) & " Hz vs " & real'image(f_de_k) &
                   " Hz" severity failure;
        -- y que ademas sean los 50 Hz que los comentarios prometen
        assert abs(f_de_paso - 50.0) < TOL_HZ
            report "el default de paso_ref no es 50 Hz, es " &
                   real'image(f_de_paso) severity failure;

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
        -- OJO: son 11..14, no 10..14. El 10 se asigno a `retardo` cuando se
        -- agrego TrgRetardo, y el test de mas abajo verifica que SI escriba.
        -- Son DOS propiedades y hay que medir las dos por separado. Escribir
        -- en 11 y despues commitear, aseverando un solo registro, no mide
        -- ninguna: shadow(11) no tiene salida, asi que lo unico que podria
        -- detectar es un aliasing sobre ese registro puntual.
        --
        -- El snapshot cubre los ONCE registros con salida, retardo incluido:
        -- asi un alias sobre el indice 10 tampoco pasa.
        v_frec := frec_in; v_paso := paso_ref; v_amp := amp_ref;
        v_k    := k;       v_kp   := kp;       v_b   := b_kr;
        v_phi  := phi_i;   v_q    := q_max;    v_inv := inv_vi;
        v_frz  := freeze;  v_ret := retardo;

        -- (a) NO deben hacer ALIAS sobre un registro mapeado. Se escribe a los
        -- cinco y se commitea EN LIMPIO (shadow == activo salvo por un alias),
        -- asi que si alguno cayera sobre un indice mapeado, el commit lo
        -- aplicaria y el snapshot no cerraria.
        --
        -- OJO con el orden: esta mitad tiene que medirse ANTES de ensuciar el
        -- shadow en (b). Una escritura de restauracion a un indice mapeado
        -- pisaria justamente el alias que se quiere detectar.
        for idx in 11 to 14 loop
            escribir(idx, 16#DEADBEE#);
        end loop;
        escribir(15, 0);
        pulso_trg;
        assert frec_in = v_frec and paso_ref = v_paso and amp_ref = v_amp
           and k = v_k and kp = v_kp and b_kr = v_b and phi_i = v_phi
           and q_max = v_q and inv_vi = v_inv and freeze = v_frz
           and retardo = v_ret
            report "una escritura a un indice sin asignar corrompio el banco"
            severity failure;

        -- (b) NO deben dejar un commit pendiente. Para que sea detectable el
        -- shadow tiene que diferir del activo: si alguno de los 11..14 pusiera
        -- `pendiente`, el pulso_trg de abajo aplicaria ese 424242 sin que nadie
        -- lo pidiera.
        escribir(2, 424242);
        for idx in 11 to 14 loop
            escribir(idx, 16#C0FFEE#);
        end loop;
        pulso_trg;
        assert amp_ref = v_amp
            report "un indice sin asignar dejo un commit pendiente: i_trg " &
                   "aplico el shadow sin que nadie lo pidiera"
            severity failure;

        -- se restaura el shadow, que quedo con 424242 colgado (CtrlRegs no
        -- tiene como descartarlo; si no, viajaria con el proximo commit ajeno)
        escribir(2, to_integer(signed(v_amp)));

        -- NOTA sobre la otra mitad del Review Focus 1: que una escritura a
        -- 10..14 escriba o no shadow(10..14) es INOBSERVABLE desde los puertos,
        -- porque esos indices no tienen salida. Un mutante que saque la guarda
        -- `idx <= 9` no lo caza ningun test de caja negra. La guarda sigue
        -- siendo correcta -- importa el dia que se mapee el indice 10 -- pero
        -- lo testeable es el aliasing de (a), no el escribir en si.

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

        -- ---- el indice 10 SI escribe: es el retardo de captura ----
        -- Se agrego con TrgRetardo. El default es 0 (la conducta anterior, que
        -- cae siempre en el vector nulo del patron SSVM), asi que el PS lo tiene
        -- que mover para ver vectores activos.
        assert retardo = "00000000000"
            report "el default de retardo no es 0" severity failure;
        escribir(10, 1234);
        assert retardo = "00000000000"
            report "retardo se vio SIN commit: el shadow no esta aislando"
            severity failure;
        escribir(15, 0);
        pulso_trg;
        assert retardo = std_logic_vector(to_unsigned(1234, 11))
            report "el indice 10 no escribio retardo: se leyo " &
                   integer'image(to_integer(unsigned(retardo)))
            severity failure;
        -- 11 bits: lo que sobra se trunca, que es correcto para un retardo
        -- acotado a la ventana de 2048 clocks
        escribir(10, 16#FFFF#);
        escribir(15, 0);
        pulso_trg;
        assert retardo = "11111111111"
            report "el truncado a 11 bits de retardo no anda" severity failure;
        report "RETARDO OK: el indice 10 escribe y trunca a 11 bits" severity note;

        report "CtrlRegs OK" severity note;
        fin <= true;
        wait;
    end process estimulo;

end architecture sim;
