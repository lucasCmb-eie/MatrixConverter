library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--!
-- Envoltorio VHDL-93 de RL_wrapper para poder instanciarlo en el block design.
--
-- RL_wrapper llama to_sfixed() sobre std_logic_vector, que solo resuelve en
-- VHDL-2008: en VHDL-93 std_logic_vector y std_ulogic_vector son tipos
-- distintos, no hay overload que matchee y Vivado cae en el de INTEGER
-- (ERROR [Synth 8-11234] type error near 'i_c_a0'; expected type 'integer').
-- O sea que RL_wrapper.vhd tiene que compilarse como VHDL 2008.
--
-- Pero Vivado no acepta un archivo VHDL-2008 como top de un module reference
-- (ERROR [filemgmt 56-195]). Las *dependencias* si pueden serlo: solo el
-- archivo top de la referencia tiene que ser VHDL-93. De ahi este nivel.
--
-- Fija los genericos en Q8.24, el formato que usa el resto del datapath.
entity RL_bd is
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;

        i_c_a0 : in  std_logic_vector(31 downto 0);
        i_c_a1 : in  std_logic_vector(31 downto 0);
        i_c_b1 : in  std_logic_vector(31 downto 0);

        i_U    : in  std_logic_vector(31 downto 0);
        i_V    : in  std_logic_vector(31 downto 0);
        i_W    : in  std_logic_vector(31 downto 0);

        o_Iu   : out std_logic_vector(31 downto 0);
        o_Iv   : out std_logic_vector(31 downto 0);
        o_Iw   : out std_logic_vector(31 downto 0)
    );
end entity RL_bd;

architecture rtl of RL_bd is
begin

    nucleo : entity work.RL_wrapper
        generic map (
            INT_BITS  => 8,
            FRAC_BITS => 24
        )
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,

            i_c_a0 => i_c_a0,
            i_c_a1 => i_c_a1,
            i_c_b1 => i_c_b1,

            i_U    => i_U,
            i_V    => i_V,
            i_W    => i_W,

            o_Iu   => o_Iu,
            o_Iv   => o_Iv,
            o_Iw   => o_Iw
        );

end architecture rtl;
