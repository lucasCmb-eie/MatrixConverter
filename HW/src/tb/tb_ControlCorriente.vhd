library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

--! Lazo cerrado completo del conversor matricial con control de corriente:
--!
--!   AC_Source -> SVM_wrapper -> RL_wrapper -> ControlLazo -> SVM_wrapper
--!
--! y en paralelo, la rama que fija el angulo de la corriente de entrada:
--!
--!   AC_Source -> TClark_wrapper -> CORDIC_atan2 -> be_i = theta_v - phi_f
--!
--! Ese `- phi_f` y el hecho de que al_o venga ahora del lazo son lo que
--! rompe el enganche al_o = be_i que hasta hoy ataba la frecuencia de salida
--! a la de entrada.
--!
--! Escribe una fila de CSV por Ts. Analizar con SW/python.
--!
--! Los valores de los set points salen de:
--!     python SW/python/ModeloControlPR.py params
entity tb_ControlCorriente is
    generic (
        -- Frecuencias y amplitud, sobreescribibles con -generic_top en xelab.
        G_PASO_IN  : integer := 21475;        -- 50 Hz de entrada
        G_PASO_REF : integer := 21475;        -- 50 Hz de referencia de salida
        G_AMP_REF  : integer := 1677722;      -- 0,10 pu en Q8.24
        G_AMP_2    : integer := 1677722;      -- amplitud despues del escalon
        G_T_ESCALON : time   := 1 sec;        -- por defecto, nunca
        G_FREEZE   : std_logic := '1';
        G_T_FIN    : time    := 400 ms
    );
end entity tb_ControlCorriente;

architecture sim of tb_ControlCorriente is
    constant PER : time := 100 ns;            -- 10 MHz

    constant K_RES : std_logic_vector(24 downto 0) :=
        std_logic_vector(to_signed(1079257, 25));          -- k(50 Hz) Q1.24
    constant KP : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(169613184, 32));        -- Kp = 10,1097
    constant B_KR : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(2718742, 32));          -- b = Kr*Ts
    -- 1/(1,976 * V_i). MEDIDO en lazo abierto el 26/09/2026: el modulador
    -- entrega |v_o| = 1,976 * q * V_i, no q * V_i. Coincide con el factor
    -- 1,980 que quedo registrado en la investigacion de agosto. V_i medido
    -- = 1,0 en Q8.24, asi que el 1,976 es todo del modulador.
    constant INV_VI : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(8490494, 32));
    constant Q_MAX : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(14529495, 32));         -- sqrt(3)/2

    -- Desfasaje del filtro de entrada, en cuentas de 11 bits. Sin filtro
    -- modelado todavia, va en cero.
    constant PHI_F : unsigned(10 downto 0) := to_unsigned(0, 11);

    -- Carga: R = 1,2 ohm, L = 12 mH a 10 MHz. ModeloControlPR.py params.
    constant C_A0 : std_logic_vector(31 downto 0) := std_logic_vector(to_signed(70, 32));
    constant C_A1 : std_logic_vector(31 downto 0) := std_logic_vector(to_signed(70, 32));
    constant C_B1 : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(16777048, 32));

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal en  : std_logic := '0';
    signal fin : boolean := false;

    signal paso_ref : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(G_PASO_REF * 2048, 32));
    signal amp_ref : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(G_AMP_REF, 32));

    -- entrada
    signal vU, vV, vW : std_logic_vector(31 downto 0);
    signal va, vb     : std_logic_vector(31 downto 0);
    signal clark_val  : std_logic;
    signal theta_v    : unsigned(10 downto 0);
    signal be_i       : std_logic_vector(10 downto 0);

    -- matriz y carga
    signal oU, oV, oW : std_logic_vector(31 downto 0);
    signal iU, iV, iW : std_logic_vector(31 downto 0);

    -- lazo
    signal q     : std_logic_vector(8 downto 0);
    signal al_o  : std_logic_vector(10 downto 0);
    signal sat   : std_logic;
    signal listo : std_logic;
    signal trg   : std_logic;

    signal ref_a, ref_b : std_logic_vector(31 downto 0);
    signal i_a,   i_b   : std_logic_vector(31 downto 0);
    signal v_a,   v_b   : std_logic_vector(31 downto 0);

begin

    clk <= not clk after PER / 2 when not fin else '0';
    rst <= '0' after 20 * PER;
    en  <= '1' after 40 * PER;

    -- ---------------- fuente de entrada ----------------
    fuente : entity work.AC_Source
        port map (i_clk => clk, i_rst => rst,
                  i_frec => std_logic_vector(to_unsigned(G_PASO_IN, 32)),
                  o_U => vU, o_V => vV, o_W => vW);

    -- ---------------- angulo de la tension de red ----------------
    clark_in : entity work.TClark_wrapper
        port map (i_clk => clk, i_rst => rst, i_start => trg,
                  i_U => vU, i_V => vV, i_W => vW,
                  o_valido => clark_val, o_alfa => va, o_beta => vb);

    angulo_in : entity work.CORDIC_atan2
        port map (clk => clk, rst => rst, start => clark_val,
                  x_in => signed(va), y_in => signed(vb),
                  angle_out => theta_v, mag_out => open, done => open);

    -- be_i = theta_v - phi_f. al_o ya NO sale de aca: lo da el lazo.
    be_i <= std_logic_vector(theta_v - PHI_F);

    -- ---------------- lazo de corriente ----------------
    lazo : entity work.ControlLazo
        port map (i_clk => clk, i_rst => rst, i_en => en, i_trg => trg,
                  i_paso_ref => paso_ref, i_amp_ref => amp_ref,
                  i_k => K_RES, i_kp => KP, i_b => B_KR,
                  i_inv_vi => INV_VI, i_q_max => Q_MAX, i_freeze => G_FREEZE,
                  i_iU => iU, i_iV => iV, i_iW => iW,
                  o_q => q, o_al_o => al_o, o_sat => sat,
                  o_ref_alfa => ref_a, o_ref_beta => ref_b,
                  o_i_alfa => i_a, o_i_beta => i_b,
                  o_v_alfa => v_a, o_v_beta => v_b,
                  o_listo => listo);

    -- ---------------- modulador + matriz ----------------
    svm : entity work.SVM_wrapper
        port map (i_clk => clk, i_enable => en,
                  i_al_o => al_o, i_be_i => be_i, i_q_i => q,
                  i_phi_i => "00000000000",
                  o_trg_calculo => trg, o_direcciones_Matriz => open,
                  i_U => vU, i_V => vV, i_W => vW,
                  o_U => oU, o_V => oV, o_W => oW);

    -- ---------------- carga ----------------
    carga : entity work.RL_wrapper
        generic map (INT_BITS => 8, FRAC_BITS => 24)
        port map (i_clk => clk, i_rst => rst,
                  i_c_a0 => C_A0, i_c_a1 => C_A1, i_c_b1 => C_B1,
                  i_U => oU, i_V => oV, i_W => oW,
                  o_Iu => iU, o_Iv => iV, o_Iw => iW);

    -- ---------------- escalon de amplitud ----------------
    escalon : process
    begin
        wait for G_T_ESCALON;
        amp_ref <= std_logic_vector(to_signed(G_AMP_2, 32));
        wait;
    end process escalon;

    -- ---------------- registro a CSV ----------------
    registro : process (clk)
        file csv         : text open write_mode is "control_corriente.csv";
        variable linea   : line;
        variable primera : boolean := true;

        procedure campo (v : in integer; ultimo : in boolean) is
        begin
            write(linea, v);
            if not ultimo then
                write(linea, string'(","));
            end if;
        end procedure campo;
    begin
        if rising_edge(clk) then
            if primera then
                write(linea, string'("ts,ref_a,ref_b,i_a,i_b,v_a,v_b,q,al_o,sat"));
                writeline(csv, linea);
                primera := false;
            end if;
            if listo = '1' then
                campo(now / (2048 * PER), false);
                campo(to_integer(signed(ref_a)), false);
                campo(to_integer(signed(ref_b)), false);
                campo(to_integer(signed(i_a)), false);
                campo(to_integer(signed(i_b)), false);
                campo(to_integer(signed(v_a)), false);
                campo(to_integer(signed(v_b)), false);
                campo(to_integer(unsigned(q)), false);
                campo(to_integer(unsigned(al_o)), false);
                if sat = '1' then campo(1, true); else campo(0, true); end if;
                writeline(csv, linea);
            end if;
        end if;
    end process registro;

    -- ---------------- vigilancia: el lazo cierra dentro del Ts ----------------
    vigilancia : process (clk)
        variable ciclos : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' or en = '0' then
                ciclos := 0;
            elsif listo = '1' then
                ciclos := 0;
            else
                ciclos := ciclos + 1;
                assert ciclos < 3 * 2048
                    report "el lazo no cerro dentro de un Ts"
                    severity failure;
            end if;
        end if;
    end process vigilancia;

    corte : process
    begin
        wait for G_T_FIN;
        report "fin de la simulacion" severity note;
        fin <= true;
        wait;
    end process corte;

end architecture sim;
