library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Lazo de corriente completo: referencia -> error -> PR -> rect2polar -> q/al_o.
--!
--! Secuencia por cada Ts, arrancada por el flanco de i_trg (o_trg_calculo del
--! SVM_wrapper). Cada bloque tiene su handshake, asi que la FSM espera a cada
--! uno: la Clarke por o_valido, el CORDIC por done. El camino completo son
--! decenas de ciclos de 10 MHz contra los 2048 del Ts.
--!
--! La referencia avanza AL PRINCIPIO del Ts, igual que el modelo de Python
--! (Lazo.correr llama a ref.paso() antes de calcular el error).
--!
--! i_sat de los PR va REGISTRADO del Ts anterior, igual que el _sat_z1 del
--! modelo. Es comun a los dos ejes porque la restriccion es sobre el modulo
--! conjunto del vector, no sobre cada eje por separado.
--!
--! Este archivo es VHDL-93 pero instancia TClark_wrapper, que abajo usa
--! ieee.fixed_pkg: por eso GHDL no lo puede elaborar y se verifica en XSIM.
entity ControlLazo is
    port (
        i_clk : in  std_logic;
        i_rst : in  std_logic;                        --! activo alto
        i_en  : in  std_logic;
        i_trg : in  std_logic;                        --! o_trg_calculo

        -- set points
        i_paso_ref : in std_logic_vector(31 downto 0); --! avance de fase por Ts
        i_amp_ref  : in std_logic_vector(31 downto 0); --! Q8.24
        i_k        : in std_logic_vector(24 downto 0); --! Q1.24
        i_kp       : in std_logic_vector(31 downto 0); --! Q8.24
        i_b        : in std_logic_vector(31 downto 0); --! Q8.24, Kr*Ts
        i_inv_vi   : in std_logic_vector(31 downto 0); --! Q8.24, 1/V_i
        i_q_max    : in std_logic_vector(31 downto 0); --! Q8.24 (0,866)
        i_freeze   : in std_logic;                     --! habilita el anti-windup

        -- corrientes medidas
        i_iU : in std_logic_vector(31 downto 0);
        i_iV : in std_logic_vector(31 downto 0);
        i_iW : in std_logic_vector(31 downto 0);

        -- al modulador
        o_q    : out std_logic_vector(8 downto 0);
        o_al_o : out std_logic_vector(10 downto 0);
        o_sat  : out std_logic;

        -- observabilidad (van a CaptureBank y al CSV del TB)
        o_ref_alfa : out std_logic_vector(31 downto 0);
        o_ref_beta : out std_logic_vector(31 downto 0);
        o_i_alfa   : out std_logic_vector(31 downto 0);
        o_i_beta   : out std_logic_vector(31 downto 0);
        o_v_alfa   : out std_logic_vector(31 downto 0);
        o_v_beta   : out std_logic_vector(31 downto 0);
        --! Estado x1 del resonante alfa: los 32 bits BAJOS de Q8.40.
        --!
        --! Es la sonda del criterio 6 (spec 6.4, ranura 19 de CaptureBank), que
        --! pide acotar el ciclo limite de x1/x2 a pocos LSB. Por eso van los
        --! bits BAJOS y no los altos: un ciclo limite de unos pocos LSB de
        --! Q8.40 es invisible si se truncan 16 bits a Q8.24.
        --!
        --! La magnitud de x1 no se pierde: o_v_alfa es u = kp*e + x1(47..16),
        --! asi que la parte alta ya se observa por la ranura 16. Esta ranura
        --! lleva lo que no esta en ningun otro lado.
        o_x1_alfa  : out std_logic_vector(31 downto 0);
        o_listo    : out std_logic                     --! un pulso al cerrar el Ts
    );
end entity ControlLazo;

architecture rtl of ControlLazo is

    type t_estado is (ESPERA, CLARKE, RESTA, PR, PR_ESPERA,
                      CORDIC_ESPERA, NORMALIZA);
    signal estado : t_estado := ESPERA;

    signal trg_z1 : std_logic := '0';

    -- referencia
    signal ref_en   : std_logic := '0';
    signal ref_alfa : signed(31 downto 0);
    signal ref_beta : signed(31 downto 0);

    -- medicion
    signal clarke_start : std_logic := '0';
    signal clarke_val   : std_logic;
    signal i_alfa_slv   : std_logic_vector(31 downto 0);
    signal i_beta_slv   : std_logic_vector(31 downto 0);

    -- control
    signal e_alfa : signed(31 downto 0) := (others => '0');
    signal e_beta : signed(31 downto 0) := (others => '0');
    signal pr_en  : std_logic := '0';
    signal sat_z1 : std_logic := '0';
    signal v_alfa : signed(31 downto 0);
    --! x1 del resonante alfa, Q8.40 en 48 bits (solo se exportan los 32 bajos)
    signal x1_alfa : signed(47 downto 0);
    signal v_beta : signed(31 downto 0);

    -- rect -> polar
    signal cordic_start : std_logic := '0';
    signal cordic_done  : std_logic;
    signal cordic_ang   : unsigned(10 downto 0);
    signal cordic_mag   : signed(31 downto 0);

    signal q_reg    : std_logic_vector(8 downto 0)  := (others => '0');
    signal al_o_reg : std_logic_vector(10 downto 0) := (others => '0');
    signal sat_reg  : std_logic := '0';
    signal listo    : std_logic := '0';

    signal congelar : std_logic;

begin

    congelar <= sat_z1 and i_freeze;

    o_ref_alfa <= std_logic_vector(ref_alfa);
    o_ref_beta <= std_logic_vector(ref_beta);
    o_i_alfa   <= i_alfa_slv;
    o_i_beta   <= i_beta_slv;
    o_v_alfa   <= std_logic_vector(v_alfa);
    o_x1_alfa  <= std_logic_vector(x1_alfa(31 downto 0));
    o_v_beta   <= std_logic_vector(v_beta);
    o_q        <= q_reg;
    o_al_o     <= al_o_reg;
    o_sat      <= sat_reg;
    o_listo    <= listo;

    referencia : entity work.RefGen
        port map (i_clk => i_clk, i_rst => i_rst, i_en => ref_en,
                  i_paso => unsigned(i_paso_ref), i_amp => signed(i_amp_ref),
                  o_alfa => ref_alfa, o_beta => ref_beta, o_theta => open);

    medicion : entity work.TClark_wrapper
        port map (i_clk => i_clk, i_rst => i_rst, i_start => clarke_start,
                  i_U => i_iU, i_V => i_iV, i_W => i_iW,
                  o_valido => clarke_val,
                  o_alfa => i_alfa_slv, o_beta => i_beta_slv);

    pr_alfa : entity work.PR_2int
        port map (i_clk => i_clk, i_rst => i_rst, i_en => pr_en,
                  i_sat => congelar,
                  i_k => signed(i_k), i_b => signed(i_b), i_kp => signed(i_kp),
                  i_e => e_alfa, o_u => v_alfa, o_x1 => x1_alfa, o_x2 => open);

    pr_beta : entity work.PR_2int
        port map (i_clk => i_clk, i_rst => i_rst, i_en => pr_en,
                  i_sat => congelar,
                  i_k => signed(i_k), i_b => signed(i_b), i_kp => signed(i_kp),
                  i_e => e_beta, o_u => v_beta, o_x1 => open, o_x2 => open);

    rect2polar : entity work.CORDIC_atan2
        port map (clk => i_clk, rst => i_rst, start => cordic_start,
                  x_in => v_alfa, y_in => v_beta,
                  angle_out => cordic_ang, mag_out => cordic_mag,
                  done => cordic_done);

    fsm : process (i_clk)
        variable prod : signed(63 downto 0);
        variable q_24 : signed(31 downto 0);
        variable q_m  : signed(40 downto 0);
    begin
        if rising_edge(i_clk) then
            trg_z1       <= i_trg;
            clarke_start <= '0';
            pr_en        <= '0';
            cordic_start <= '0';
            ref_en       <= '0';
            listo        <= '0';

            if i_rst = '1' then
                estado   <= ESPERA;
                sat_z1   <= '0';
                sat_reg  <= '0';
                q_reg    <= (others => '0');
                al_o_reg <= (others => '0');
                trg_z1   <= '0';
            else
                case estado is

                    when ESPERA =>
                        -- flanco ascendente de i_trg
                        if i_en = '1' and i_trg = '1' and trg_z1 = '0' then
                            ref_en       <= '1';   -- la referencia avanza primero
                            clarke_start <= '1';
                            estado       <= CLARKE;
                        end if;

                    when CLARKE =>
                        if clarke_val = '1' then
                            estado <= RESTA;
                        end if;

                    when RESTA =>
                        e_alfa <= ref_alfa - signed(i_alfa_slv);
                        e_beta <= ref_beta - signed(i_beta_slv);
                        estado <= PR;

                    when PR =>
                        pr_en  <= '1';
                        estado <= PR_ESPERA;

                    when PR_ESPERA =>
                        -- pr_en esta alto en ESTE ciclo: los PR registran
                        -- v_alfa/v_beta en este flanco. El CORDIC arranca
                        -- ahora y late sus entradas recien en PRE_PROCESS,
                        -- dos ciclos mas tarde, asi que las ve validas.
                        cordic_start <= '1';
                        estado       <= CORDIC_ESPERA;

                    when CORDIC_ESPERA =>
                        if cordic_done = '1' then
                            estado <= NORMALIZA;
                        end if;

                    when NORMALIZA =>
                        -- |v*| (Q8.24) * 1/V_i (Q8.24) = Q16.48 -> Q8.24
                        prod := cordic_mag * signed(i_inv_vi);

                        -- Un desborde del producto se trata como saturacion, no
                        -- como q chico: si q_24 saliera negativo por wrap, la
                        -- comparacion de abajo no entraria, sat quedaria en '0'
                        -- y el anti-windup se apagaria con el integrador
                        -- disparado. Ante un desborde, saturar es lo seguro.
                        if prod(63) = '1' or prod(62 downto 55) /= "00000000" then
                            q_24 := signed(i_q_max);
                        else
                            q_24 := prod(55 downto 24);
                        end if;

                        if q_24 > signed(i_q_max) then
                            q_24    := signed(i_q_max);
                            sat_reg <= '1';
                            sat_z1  <= '1';
                        else
                            sat_reg <= '0';
                            sat_z1  <= '0';
                        end if;

                        if q_24 < 0 then
                            q_reg <= (others => '0');
                        else
                            -- q (Q8.24) -> palabra de i_q_i. FONDO DE ESCALA 255,
                            -- no 512: el modulador normaliza q contra cos_phi, y
                            -- cos_phi es el cos(0) de la LUT, que vale 255. Con
                            -- 512 las duties salen al doble, la suma se pasa de
                            -- 1024 y el tiempo nulo hace underflow (medido).
                            -- 255 = 256-1, asi que el producto es un shift y una
                            -- resta, sin multiplicador.
                            q_m := shift_left(resize(q_24, 41), 8) - resize(q_24, 41);
                            q_reg <= std_logic_vector(q_m(32 downto 24));
                        end if;

                        -- El +1024 que habia aca salio: la inversion de 180
                        -- grados se arreglo en la FUENTE (Modulador.vhd:884,
                        -- el patron de signos de seq0 estaba complementado
                        -- respecto de la regla (-1)^(Kv+Ki) de Casadei).
                        -- Ver Control/INVESTIGACION_MODULADOR.md.
                        al_o_reg <= std_logic_vector(cordic_ang);
                        listo    <= '1';
                        estado   <= ESPERA;

                end case;
            end if;
        end if;
    end process fsm;

end architecture rtl;
