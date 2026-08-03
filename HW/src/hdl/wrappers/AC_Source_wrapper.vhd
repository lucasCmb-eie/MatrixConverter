library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.sine_lut_pkg.all;

entity AC_Source_wrapper is
    port (
        i_clk : in  std_logic; --! Entrada de Clock : 100KHz
        i_rst : in  std_logic; --! Reset
        i_frec : in  std_logic_vector(1 downto 0); --! Entrada de frecuencia de salida

        o_U : out std_logic_vector(31 downto 0); --! Salida de la tensión de linea U
        o_V : out std_logic_vector(31 downto 0); --! Salida de la tensión de linea V
        o_W : out std_logic_vector(31 downto 0)  --! Salida de la tensión de linea W
     );
end AC_Source_wrapper;

architecture Behavioral of AC_Source_wrapper is
begin

    triV_core : entity work.AC_Source
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_frec => i_frec,
            
            o_U => o_U,
            o_V => o_V,            
            o_W => o_W
        );
end Behavioral;
