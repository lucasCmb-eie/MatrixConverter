library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
--
-- ---------------------------------------------------------------------------
-- POR QUE LOS COEFICIENTES SON GENERIC Y NO PUERTO
--
-- RL_fase hace tres productos Q8.24 x Q8.24 por fase. Con los coeficientes
-- entrando por PUERTO, Vivado no conoce sus valores e infiere multiplicadores
-- 32x32 completos: 4 DSP48E1 cada uno, 12 por fase, 36 en las tres. Eso es el
-- 55% de los 66 DSP del xc7z007s de la Blackboard, y es lo que hacia que el
-- banco de lazo cerrado no entrara (89 DSP pedidos, DRC UTLZ-1 al 134,85%).
--
-- La causa de que no plegara aunque el BD los ataba a xlconstant: las celdas
-- del block design se sintetizan FUERA DE CONTEXTO. En la corrida OOC de este
-- modulo, i_c_a0 era una entrada de valor desconocido.
--
-- Con los coeficientes como generic la constante vive ADENTRO del modulo, asi
-- que la sintesis OOC los ve y los pliega. Y los tres son triviales:
--
--   a0 = a1 = 70        = 64 + 4 + 2            -> tres sumas desplazadas
--   b1 = 16777048       = 2**24 - 168, o sea
--                         I*b1 = I - I*168/2**24, y 168 = 128 + 32 + 8
--
-- o sea CERO DSP si el plegado ocurre.
--
-- Lo que se pierde: los coeficientes ya no se pueden cambiar en runtime, hay
-- que re-sintetizar. No se pierde nada hoy -- el BD ya los ataba a constantes y
-- el PS no los podia tocar -- pero cierra la puerta a barrer cargas en caliente
-- desde el PS con un registro de CtrlRegs. Por eso este cambio vive en la rama
-- implementacion_BlackBoard y no en main.
--
-- Los defaults son R = 1,2 ohm y L = 12 mH con Ts = 204,8 us:
--   a0 = a1 = T/(2L + R*T) = 4,16666e-6 -> 70 en Q8.24
--   b1 = (2L - R*T)/(2L + R*T) = 0,99998999 -> 16777048
-- Regenerar con: python SW/python/ModeloControlPR.py params
-- OJO: el encabezado de RL_fase.vhd dice "- b1*I[n-1]" pero la implementacion
-- (linea 94) suma, asi que b1 va POSITIVO.
-- ---------------------------------------------------------------------------
entity RL_bd is
    generic (
        --! coeficientes en Q8.24, como el entero crudo de 32 bits
        G_C_A0 : integer := 70;
        G_C_A1 : integer := 70;
        G_C_B1 : integer := 16777048
    );
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;

        i_U    : in  std_logic_vector(31 downto 0);
        i_V    : in  std_logic_vector(31 downto 0);
        i_W    : in  std_logic_vector(31 downto 0);

        o_Iu   : out std_logic_vector(31 downto 0);
        o_Iv   : out std_logic_vector(31 downto 0);
        o_Iw   : out std_logic_vector(31 downto 0)
    );
end entity RL_bd;

architecture rtl of RL_bd is

    --! Los genericos pasan a constantes locales, que es lo que la sintesis OOC
    --! necesita ver para plegar los productos a sumas desplazadas.
    constant C_A0 : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(G_C_A0, 32));
    constant C_A1 : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(G_C_A1, 32));
    constant C_B1 : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_signed(G_C_B1, 32));

begin

    nucleo : entity work.RL_wrapper
        generic map (
            INT_BITS  => 8,
            FRAC_BITS => 24
        )
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,

            i_c_a0 => C_A0,
            i_c_a1 => C_A1,
            i_c_b1 => C_B1,

            i_U    => i_U,
            i_V    => i_V,
            i_W    => i_W,

            o_Iu   => o_Iu,
            o_Iv   => o_Iv,
            o_Iw   => o_Iw
        );

end architecture rtl;
