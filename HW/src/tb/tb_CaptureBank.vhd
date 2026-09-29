library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--!
-- Testbench de CaptureBank con captura armada y sincronizada al modulador.
--
-- El handshake que se verifica:
--   PS pone i_arm='1'  ->  el banco queda armado, la foto anterior intacta
--   flanco de i_trigger ->  captura en un ciclo, desarma, o_listo='1'
--   PS pone i_arm='0'  ->  o_listo='0', los registros SIGUEN congelados
--   PS barre i_sel y lee, sin limite de tiempo
entity tb_CaptureBank is
end entity tb_CaptureBank;

architecture sim of tb_CaptureBank is
    constant PER2       : time    := 50 ns;   -- 10 MHz
    constant STATUS_IDX : integer := 13;      -- indice del registro de estado

    signal clk, rst, arm, trigger : std_logic := '0';
    signal sel   : std_logic_vector(31 downto 0) := (others => '0');
    signal d     : std_logic_vector(31 downto 0);
    signal listo : std_logic;
    signal done  : boolean := false;

    -- 0..19: las ranuras nuevas del lazo van en 14..19. La 13 existe en el
    -- array pero no se usa, porque ese indice lo ocupa el estado.
    type slv32_t is array (0 to 19) of std_logic_vector(31 downto 0);
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

    procedure check_listo (signal   got : in std_logic;
                           constant exp : in std_logic;
                           constant msg : in string) is
    begin
        assert got = exp
            report msg & ": o_listo esperado " & std_logic'image(exp) &
                   " y vale " & std_logic'image(got)
            severity failure;
    end procedure;
begin
    clk <= not clk after PER2 when not done else '0';

    uut : entity work.CaptureBank
        port map (i_clk => clk, i_rst => rst,
                  i_arm => arm, i_trigger => trigger, i_sel => sel,
                  i_d00 => src(0),  i_d01 => src(1),  i_d02 => src(2),
                  i_d03 => src(3),  i_d04 => src(4),  i_d05 => src(5),
                  i_d06 => src(6),  i_d07 => src(7),  i_d08 => src(8),
                  i_d09 => src(9),  i_d10 => src(10),
                  i_d11 => src(11), i_d12 => src(12),
                  i_d14 => src(14), i_d15 => src(15),
                  i_d16 => src(16), i_d17 => src(17),
                  i_d18 => src(18), i_d19 => src(19),
                  o_data => d, o_listo => listo);

    estimulo : process

        -- carga las 13 fuentes con base+k
        procedure poner_fuentes (constant base : in integer) is
        begin
            for k in 0 to 19 loop
                -- la 13 se saltea: ese indice lo ocupa el estado
                if k /= 13 then
                    src(k) <= std_logic_vector(to_unsigned(base + k, 32));
                end if;
            end loop;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- 1) reset: registros en cero y sin listo
        ------------------------------------------------------------------
        rst <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);
        rst <= '0';
        wait for 1 ns;
        check(d, x"00000000", "tras reset, sel=0");
        check_listo(listo, '0', "tras reset");
        report "RESET OK";

        ------------------------------------------------------------------
        -- 2) SIN ARMAR un trigger no captura nada
        ------------------------------------------------------------------
        poner_fuentes(16#A0#);
        wait until rising_edge(clk);
        trigger <= '1';
        wait until rising_edge(clk);
        trigger <= '0';
        wait until rising_edge(clk);
        check_listo(listo, '0', "trigger sin armar");
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, x"00000000", "sin armar sel=" & integer'image(k));
        end loop;
        report "SIN ARMAR OK: el trigger solo no captura";

        ------------------------------------------------------------------
        -- 3) ARMADO: espera al trigger, no captura al armarse
        ------------------------------------------------------------------
        arm <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);
        check_listo(listo, '0', "armado sin trigger todavia");
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, x"00000000", "armado sin trigger sel=" & integer'image(k));
        end loop;
        report "ARMADO OK: armar por si solo no captura";

        ------------------------------------------------------------------
        -- 4) el trigger captura, en un ciclo, y levanta listo
        ------------------------------------------------------------------
        wait until rising_edge(clk);
        trigger <= '1';
        wait until rising_edge(clk);
        trigger <= '0';
        wait until rising_edge(clk);
        check_listo(listo, '1', "tras capturar");
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)),
                  "capturado sel=" & integer'image(k));
        end loop;
        report "CAPTURA OK: el trigger captura los 13 registros y avisa";

        ------------------------------------------------------------------
        -- 5) EL CASO QUE MOTIVA TODO: ya capturado y con arm todavia en alto,
        --    llegan mas triggers del modulador. NO deben pisar la foto.
        ------------------------------------------------------------------
        poner_fuentes(16#B0#);
        for t in 1 to 3 loop
            wait until rising_edge(clk);
            trigger <= '1';
            wait until rising_edge(clk);
            trigger <= '0';
            wait until rising_edge(clk);
        end loop;
        check_listo(listo, '1', "tras triggers extra");
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)),
                  "sin repisar sel=" & integer'image(k));
        end loop;
        report "SIN REPISAR OK: una sola captura por armado";

        ------------------------------------------------------------------
        -- 6) desarmar baja listo pero NO toca los registros; el barrido
        --    puede tardar lo que quiera
        ------------------------------------------------------------------
        arm <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        check_listo(listo, '0', "tras desarmar");
        poner_fuentes(16#5000#);
        for t in 1 to 3 loop
            wait until rising_edge(clk);
            trigger <= '1';
            wait until rising_edge(clk);
            trigger <= '0';
            wait until rising_edge(clk);
        end loop;
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)),
                  "coherencia sel=" & integer'image(k));
        end loop;
        report "COHERENCIA OK: desarmado, los registros no siguen a la entrada";

        ------------------------------------------------------------------
        -- 7) registro de estado en el indice 13, y fuera de rango
        ------------------------------------------------------------------
        sel <= std_logic_vector(to_unsigned(STATUS_IDX, 32));
        wait for 1 ns;
        check(d, x"00000000", "estado con listo bajo");

        arm <= '1';
        wait until rising_edge(clk);
        trigger <= '1';
        wait until rising_edge(clk);
        trigger <= '0';
        wait until rising_edge(clk);
        sel <= std_logic_vector(to_unsigned(STATUS_IDX, 32));
        wait for 1 ns;
        check(d, x"00000001", "estado con listo alto");
        report "ESTADO OK: el indice 13 refleja o_listo";

        -- la segunda captura si tomo el patron nuevo (0x5000)
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#5000# + k, 32)),
                  "rearmado sel=" & integer'image(k));
        end loop;
        report "REARMADO OK: un nuevo armado captura de nuevo";

        for v in 0 to 2 loop
            case v is
                -- 14 ya NO esta fuera de rango: con N_REGS = 20 es una
                -- ranura valida. El primero que sigue afuera es el 20.
                when 0      => sel <= std_logic_vector(to_unsigned(20, 32));
                when 1      => sel <= std_logic_vector(to_unsigned(100, 32));
                when others => sel <= x"FFFFFFFF";
            end case;
            wait for 1 ns;
            check(d, x"00000000", "fuera de rango");
        end loop;
        report "FUERA DE RANGO OK";

        ------------------------------------------------------------------
        -- 9) ranuras nuevas 14..19, y el indice de 5 bits
        ------------------------------------------------------------------
        -- Con el slice de 4 bits que habia antes, el indice 16 devolvia la
        -- ranura 0, el 17 la 1, y asi: las ranuras nuevas eran inalcanzables
        -- y el error no daba ninguna senal.
        poner_fuentes(16#5A00#);
        -- Hay que DESARMAR primero: despues del test anterior o_listo quedo
        -- en '1', y con listo='1' el banco no vuelve a capturar aunque se le
        -- ponga i_arm. Es el handshake de una sola captura por armado, y el
        -- ack es el propio i_arm='0'.
        arm <= '0';
        wait until rising_edge(clk);
        arm <= '1';
        wait until rising_edge(clk);
        trigger <= '1';
        wait until rising_edge(clk);
        trigger <= '0';
        wait until rising_edge(clk);

        for k in 14 to 19 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#5A00# + k, 32)),
                  "ranura nueva " & integer'image(k));
        end loop;
        report "RANURAS NUEVAS OK: el indice llega a 5 bits";

        -- El estado tiene que seguir en 13: el software del PS que ya existe
        -- barre 0..13 y lo lee ahi.
        sel <= std_logic_vector(to_unsigned(13, 32));
        wait for 1 ns;
        check_listo(listo, '1', "el estado sigue en 13");

        -- i_sel con el bit 31 puesto. El PS escribe 32 bits; si se indexara
        -- sin comparar antes como unsigned, el to_integer desbordaria.
        sel <= x"80000010";
        wait for 1 ns;
        check(d, x"00000000", "i_sel con el bit 31 puesto");
        report "INDICE ANCHO OK";

        report "TODAS LAS VERIFICACIONES OK";
        done <= true;
        wait;
    end process;
end architecture sim;
