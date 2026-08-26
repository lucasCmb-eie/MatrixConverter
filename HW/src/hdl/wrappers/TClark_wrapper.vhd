library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--!
-- Envoltorio de TransformadaClark para el block design.
--
-- Es un pasamanos: TransformadaClark ya expone puertos escalares y std_logic_vector,
-- asi que este nivel solo existe para que el BD instancie un top VHDL-93 (sin
-- ieee.fixed_pkg ni el tipo 'vector' de Declaraciones.vhd), que es lo que
-- Vivado exige para un module reference (ERROR [filemgmt 56-195]).
entity TClark_wrapper is
    port ( 
        i_clk : in std_logic;
        i_rst : in std_logic;

        --Inicio de calculo
        i_start : in std_logic;

        -- Entradas de tensiones trifasicas (U, V ,W)
        i_U : in std_logic_vector (31 downto 0);
        i_V : in std_logic_vector (31 downto 0);
        i_W : in std_logic_vector (31 downto 0);

        -- Salida Calculo terminado
        o_valido : out std_logic;

        -- Salidas de tensiones en el sistema alfa-beta
        o_alfa : out std_logic_vector(31 downto 0);
        o_beta : out std_logic_vector(31 downto 0)
    );
end TClark_wrapper;

architecture Behavioral of TClark_wrapper is

begin

    -- Instancia del bloque original. Los genericos quedan en su default (8/24).
    tClark_core : entity work.TransformadaClark
        port map (
            i_clk    => i_clk,
            i_rst    => i_rst,
            i_start  => i_start,

            i_U      => i_U,
            i_V      => i_V,
            i_W      => i_W,

            o_valido => o_valido,
            o_alfa   => o_alfa,
            o_beta   => o_beta
        );

end Behavioral;
