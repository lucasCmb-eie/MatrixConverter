library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Banco de set points del PS para el lazo de corriente.
--!
--! El PS escribe por un PUERTO INDEXADO montado sobre los AXI GPIO que ya
--! existen, sin agregar un tercero:
--!
--!   ctrl/ch1  bit0 rst | bit1 enable | bit2 arm | bit3 wr_stb | bits 7..4 wr_idx
--!   ctrl/ch2  wr_data (32 b)
--!
--! Escribir un set point son tres transacciones AXI: dato -> idx+stb=1 ->
--! stb=0. El registro se carga en el flanco de wr_stb, con wr_data ya estable,
--! asi que la no-atomicidad entre las dos escrituras del PS no puede romper
--! nada. A 4,88 kHz el lazo ni se entera.
--!
--! SHADOW + COMMIT: las escrituras van a un banco shadow y el indice 15 las
--! transfiere al activo EN EL PROXIMO i_trg, nunca en el medio de un calculo.
--! Cambiar f_o toca dos registros que deben moverse juntos (paso_ref y k): si
--! el lazo viera uno actualizado y el otro no, el resonante quedaria
--! sintonizado a otra frecuencia que la referencia durante ese Ts.
--!
--! CLAMPEO: dos registros tienen limites duros que el RTL no puede absorber.
--! Se clampean y se deja rastro sticky en o_clamp, que el PS puede leer por
--! CaptureBank.
--!
--! VHDL-93 + numeric_std a proposito: asi lo puede simular GHDL 0.29.
entity CtrlRegs is
    port (
        i_clk : in  std_logic;
        i_rst : in  std_logic;
        i_trg : in  std_logic;                       --! o_trg_calculo del SVM

        i_wr_data : in std_logic_vector(31 downto 0);
        i_wr_idx  : in std_logic_vector(3 downto 0);
        i_wr_stb  : in std_logic;

        o_frec_in  : out std_logic_vector(31 downto 0);  --! idx 0
        o_paso_ref : out std_logic_vector(31 downto 0);  --! idx 1
        o_amp_ref  : out std_logic_vector(31 downto 0);  --! idx 2, Q8.24
        o_k        : out std_logic_vector(24 downto 0);  --! idx 3, Q1.24
        o_kp       : out std_logic_vector(31 downto 0);  --! idx 4, Q8.24
        o_b        : out std_logic_vector(31 downto 0);  --! idx 5, Q8.24
        o_phi_i    : out std_logic_vector(10 downto 0);  --! idx 6
        o_q_max    : out std_logic_vector(31 downto 0);  --! idx 7, Q8.24
        o_inv_vi   : out std_logic_vector(31 downto 0);  --! idx 8, Q8.24
        o_freeze   : out std_logic;                      --! idx 9
        o_clamp    : out std_logic_vector(15 downto 0)   --! sticky, por registro
    );
end entity CtrlRegs;

architecture rtl of CtrlRegs is

    constant N : integer := 16;
    constant IDX_COMMIT : integer := 15;

    --! El maximo representable en Q1.24 y en la parte util de Q8.24 que el
    --! resto del lazo trata como fraccion menor que 1.
    constant UNO_Q24 : unsigned(31 downto 0) := x"01000000";
    constant MAX_Q24 : std_logic_vector(31 downto 0) := x"00FFFFFF";

    type banco_t is array (0 to N - 1) of std_logic_vector(31 downto 0);

    --! Defaults: el lazo arranca INERTE. amp_ref = Kp = b = 0 significa
    --! referencia nula, v* = 0, q = 0. El PS carga la sintonia y recien
    --! despues sube amp_ref. Un conversor de potencia que arranca con las
    --! ganancias en cero es la unica opcion defendible.
    constant DEFAULTS : banco_t := (
        0  => x"000053E3",   -- frec_in  : 50 Hz
        1  => x"029F0800",   -- paso_ref : 50 Hz por Ts (21475 * 2048)
        2  => x"00000000",   -- amp_ref  : 0
        3  => x"001077D9",   -- k        : 2*sin(pi*50*Ts) en Q1.24
        4  => x"00000000",   -- Kp       : 0
        5  => x"00000000",   -- b        : 0
        6  => x"00000000",   -- phi_i    : 0, factor de potencia unitario
        7  => x"00DDB3D7",   -- q_max    : sqrt(3)/2 en Q8.24
        8  => x"01EE0F3B",   -- inv_vi   : 1/0,5179 en Q8.24
        9  => x"00000001",   -- freeze   : anti-windup activo
        others => x"00000000"
    );

    signal shadow : banco_t := DEFAULTS;
    signal activo : banco_t := DEFAULTS;
    signal clamp  : std_logic_vector(15 downto 0) := (others => '0');

    signal stb_z1    : std_logic := '0';
    signal trg_z1    : std_logic := '0';
    signal pendiente : std_logic := '0';

begin

    o_frec_in  <= activo(0);
    o_paso_ref <= activo(1);
    o_amp_ref  <= activo(2);
    o_k        <= activo(3)(24 downto 0);
    o_kp       <= activo(4);
    o_b        <= activo(5);
    o_phi_i    <= activo(6)(10 downto 0);
    o_q_max    <= activo(7);
    o_inv_vi   <= activo(8);
    o_freeze   <= activo(9)(0);
    o_clamp    <= clamp;

    proceso : process (i_clk)
        variable idx : integer range 0 to N - 1;
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                shadow    <= DEFAULTS;
                activo    <= DEFAULTS;
                clamp     <= (others => '0');
                stb_z1    <= '0';
                trg_z1    <= '0';
                pendiente <= '0';
            else
                stb_z1 <= i_wr_stb;
                trg_z1 <= i_trg;

                -- flanco ascendente del strobe: wr_data ya esta estable
                if i_wr_stb = '1' and stb_z1 = '0' then
                    idx := to_integer(unsigned(i_wr_idx));

                    if idx = IDX_COMMIT then
                        pendiente <= '1';

                    -- k (Q1.24): en 25 bits, 2**24 tiene el bit de signo
                    -- puesto, y el resonante sintonizaria la secuencia
                    -- conjugada sin avisar. f_o maximo = 1/(6*Ts) = 813,8 Hz.
                    elsif idx = 3 then
                        if unsigned(i_wr_data) >= UNO_Q24 then
                            shadow(3) <= MAX_Q24;
                            clamp(3)  <= '1';
                        else
                            shadow(3) <= i_wr_data;
                        end if;

                    -- q_max (Q8.24): arriba de 1,0 la conversion a la palabra
                    -- de i_q_i envolveria en vez de clampear, y q saldria
                    -- chico en vez de maximo.
                    elsif idx = 7 then
                        if unsigned(i_wr_data) >= UNO_Q24 then
                            shadow(7) <= MAX_Q24;
                            clamp(7)  <= '1';
                        else
                            shadow(7) <= i_wr_data;
                        end if;

                    -- Los indices 10 a 14 no estan asignados: una escritura
                    -- ahi no toca nada.
                    elsif idx <= 9 then
                        shadow(idx) <= i_wr_data;
                    end if;
                end if;

                -- El commit se materializa en el flanco de i_trg, o sea en el
                -- mismo instante en que el lazo toma su muestra.
                if pendiente = '1' and i_trg = '1' and trg_z1 = '0' then
                    activo    <= shadow;
                    pendiente <= '0';
                end if;
            end if;
        end if;
    end process proceso;

end architecture rtl;
