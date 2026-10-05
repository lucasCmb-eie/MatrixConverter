library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--!
-- Banco de captura para el puente PS<->PL, con captura ARMADA y sincronizada
-- al modulador.
--
-- El PS decide CUANDO quiere una muestra, pero el modulador decide EN QUE
-- INSTANTE del periodo de conmutacion se toma. Asi la foto cae siempre en el
-- mismo punto de la ventana de PWM (el pulso de o_trg_calculo del SVM_wrapper,
-- offset fijo dentro del vector nulo de borde) en vez de en una fase al azar.
--
-- Handshake:
--
--   i_arm='1'            -> queda armado; la foto anterior sigue intacta
--   flanco de i_trigger  -> captura las 19 entradas EN UN CICLO, desarma
--                           y pone o_listo='1'
--   i_arm='0'            -> o_listo='0'; los registros SIGUEN congelados
--
-- Una sola captura por armado: aunque i_arm quede alto, los triggers
-- siguientes no repisan la foto. Eso es lo que permite que el PS barra i_sel
-- por las 20 ranuras sin correr contra el Ts de 204,8 us del modulador.
--
-- o_listo es NIVEL, no pulso: sirve tanto para polear por GPIO como para
-- manejar IRQ_F2P del PS7, que el GIC toma sensible a nivel alto. Al desarmar
-- se limpia solo, o sea que el ack es el propio i_arm='0'.
--
-- VHDL-93 a proposito: es el archivo top de un module reference del block
-- design y Vivado rechaza tops en VHDL-2008 (ERROR [filemgmt 56-195]).
entity CaptureBank is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_arm     : in  std_logic;                      --! nivel, del PS: pide una muestra
        i_trigger : in  std_logic;                      --! pulso de TrgRetardo (o_trg_calculo retardado)
        i_sel     : in  std_logic_vector(31 downto 0);  --! ranura a leer (0..19), 13 = estado

        --! Lo que cablea create_bd.tcl en cada ranura. La entidad no depende de
        --! esto, pero el software del PS y los scripts de Python si: si se
        --! recablea el BD, actualizar aca.
        i_d00, i_d01, i_d02 : in std_logic_vector(31 downto 0);  --! Vi_U, Vi_V, Vi_W (AC_Source)
        i_d03               : in std_logic_vector(31 downto 0);  --! o_clamp de CtrlRegs, bits 15..0
        i_d04, i_d05        : in std_logic_vector(31 downto 0);  --! Vo_U, Vo_V (SVM_wrapper)
        i_d06, i_d07, i_d08 : in std_logic_vector(31 downto 0);  --! Io_U, Io_V, Io_W (planta; 0 sin planta)
        i_d09, i_d10        : in std_logic_vector(31 downto 0);  --! i_alfa, i_beta medidas (ControlLazo)
        i_d11               : in std_logic_vector(31 downto 0);  --! Vo_W (SVM_wrapper)
        i_d12               : in std_logic_vector(31 downto 0);  --! o_direcciones, 18 bits

        --! Ranuras del lazo de corriente. Van en 14..19 y NO en 13, para que
        --! STATUS_IDX se quede donde esta y el software del PS que ya barre
        --! 0..13 siga funcionando sin recompilar.
        i_d14, i_d15        : in std_logic_vector(31 downto 0);  --! ref_alfa, ref_beta
        i_d16, i_d17        : in std_logic_vector(31 downto 0);  --! v*alfa, v*beta (salida del PR)
        i_d18               : in std_logic_vector(31 downto 0);  --! q (8..0), al_o (19..9), o_sat (20)
        i_d19               : in std_logic_vector(31 downto 0);  --! x1_alfa, 32 bits bajos de Q8.40

        o_data    : out std_logic_vector(31 downto 0);
        o_listo   : out std_logic                       --! nivel: hay foto lista para leer
    );
end entity CaptureBank;

architecture rtl of CaptureBank is

    constant N_REGS     : integer := 20;
    -- El estado NO ocupa una ranura de datos: el indice 12 esta reservado para
    -- 'direcciones' en el mapa del spec. Va en el 13, que antes era fuera de rango.
    constant STATUS_IDX : integer := 13;

    type reg_array_t is array (0 to N_REGS - 1) of std_logic_vector(31 downto 0);

    signal regs   : reg_array_t := (others => (others => '0'));
    signal armado : std_logic := '0';
    signal listo  : std_logic := '0';
    signal trg_z1 : std_logic := '0';

begin

    o_listo <= listo;

    captura : process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                regs   <= (others => (others => '0'));
                armado <= '0';
                listo  <= '0';
                trg_z1 <= '0';
            else
                trg_z1 <= i_trigger;

                if i_arm = '0' then
                    -- Desarmado / ack del PS. Los registros NO se tocan: la foto
                    -- tiene que sobrevivir todo el barrido.
                    armado <= '0';
                    listo  <= '0';

                elsif listo = '0' then
                    -- Armado y todavia sin foto. Se arma y se espera al modulador.
                    armado <= '1';

                    -- o_trg_calculo ya es un pulso de un ciclo, pero se detecta el
                    -- flanco igual: hace al modulo inmune a que le cableen un nivel.
                    if armado = '1' and i_trigger = '1' and trg_z1 = '0' then
                        regs(0)  <= i_d00;  regs(1)  <= i_d01;  regs(2)  <= i_d02;
                        regs(3)  <= i_d03;  regs(4)  <= i_d04;  regs(5)  <= i_d05;
                        regs(6)  <= i_d06;  regs(7)  <= i_d07;  regs(8)  <= i_d08;
                        regs(9)  <= i_d09;  regs(10) <= i_d10;
                        regs(11) <= i_d11;  regs(12) <= i_d12;
                        -- La 13 no se usa: ese indice lo ocupa el estado.
                        regs(13) <= (others => '0');
                        regs(14) <= i_d14;  regs(15) <= i_d15;
                        regs(16) <= i_d16;  regs(17) <= i_d17;
                        regs(18) <= i_d18;  regs(19) <= i_d19;
                        armado <= '0';
                        listo  <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process captura;

    -- Se compara como unsigned y recien despues se indexa: convertir un i_sel
    -- de 32 bits a integer desbordaria con el bit 31 en 1.
    --
    -- El slice es de CINCO bits, no cuatro. Con cuatro, el indice 16 devolvia
    -- la ranura 0, el 17 la 1, y asi: las ranuras 14..19 eran inalcanzables y
    -- el error no daba ninguna senal.
    seleccion : process (i_sel, regs, listo)
    begin
        if unsigned(i_sel) = STATUS_IDX then
            o_data <= (0 => listo, others => '0');
        elsif unsigned(i_sel) < N_REGS then
            o_data <= regs(to_integer(unsigned(i_sel(4 downto 0))));
        else
            o_data <= (others => '0');
        end if;
    end process seleccion;

end architecture rtl;
