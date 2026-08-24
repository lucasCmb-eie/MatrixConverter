library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--!
-- Banco de captura para el puente PS<->PL.
--
-- Al flanco ascendente de i_capture congela las 13 entradas en registros, todas
-- del mismo ciclo de reloj. Despues el PS barre i_sel y lee o_data, con la
-- garantia de que las 13 muestras son coherentes entre si.
--
-- VHDL-93 a proposito: es el archivo top de un module reference del block design
-- y Vivado rechaza tops en VHDL-2008 (ERROR [filemgmt 56-195]).
entity CaptureBank is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_capture : in  std_logic;                      --! nivel; se detecta el flanco ascendente
        i_sel     : in  std_logic_vector(31 downto 0);  --! indice de registro (0..12)

        i_d00, i_d01, i_d02 : in std_logic_vector(31 downto 0);  --! v_U, v_V, v_W
        i_d03, i_d04, i_d05 : in std_logic_vector(31 downto 0);  --! vsw_U, vsw_V, vsw_W
        i_d06, i_d07, i_d08 : in std_logic_vector(31 downto 0);  --! i_U, i_V, i_W
        i_d09, i_d10        : in std_logic_vector(31 downto 0);  --! alfa, beta
        i_d11, i_d12        : in std_logic_vector(31 downto 0);  --! theta_vi, direcciones

        o_data    : out std_logic_vector(31 downto 0)
    );
end entity CaptureBank;

architecture rtl of CaptureBank is

    constant N_REGS : integer := 13;
    type reg_array_t is array (0 to N_REGS - 1) of std_logic_vector(31 downto 0);

    signal regs   : reg_array_t := (others => (others => '0'));
    signal cap_z1 : std_logic := '0';

begin

    captura : process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                regs   <= (others => (others => '0'));
                cap_z1 <= '0';
            else
                cap_z1 <= i_capture;
                if i_capture = '1' and cap_z1 = '0' then
                    regs(0)  <= i_d00;  regs(1)  <= i_d01;  regs(2)  <= i_d02;
                    regs(3)  <= i_d03;  regs(4)  <= i_d04;  regs(5)  <= i_d05;
                    regs(6)  <= i_d06;  regs(7)  <= i_d07;  regs(8)  <= i_d08;
                    regs(9)  <= i_d09;  regs(10) <= i_d10;
                    regs(11) <= i_d11;  regs(12) <= i_d12;
                end if;
            end if;
        end if;
    end process captura;

    -- Se compara como unsigned y recien despues se indexa con los 4 bits bajos:
    -- convertir i_sel entero de 32 bits a integer desbordaria con el bit 31 en 1.
    seleccion : process (i_sel, regs)
    begin
        if unsigned(i_sel) < N_REGS then
            o_data <= regs(to_integer(unsigned(i_sel(3 downto 0))));
        else
            o_data <= (others => '0');
        end if;
    end process seleccion;

end architecture rtl;
