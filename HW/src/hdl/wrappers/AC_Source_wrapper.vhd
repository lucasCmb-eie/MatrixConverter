library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.sine_lut_pkg.all;
use work.declaraciones.all;

entity AC_Source_wrapper is
    port (
        i_clk : in  std_logic; --! Entrada de Clock : 100KHz
        i_rst : in  std_logic; --! Reset

        o_U : out std_logic_vector(SINE_DATA_WIDTH - 1 downto 0); --! Salida de la tensión de linea U
        o_V : out std_logic_vector(SINE_DATA_WIDTH - 1 downto 0); --! Salida de la tensión de linea V
        o_W : out std_logic_vector(SINE_DATA_WIDTH - 1 downto 0)  --! Salida de la tensión de linea W
     );
end AC_Source_wrapper;

architecture Behavioral of AC_Source_wrapper is
    
    signal w_triV : vector(1 to 3)(SINE_DATA_WIDTH - 1 downto 0);

begin

    triV_core : entity work.AC_Source
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            
            o_triV => w_triV
        );

    -- Mapeo de salidas a puertos
    o_U <= w_triV(1);
    o_V <= w_triV(2);
    o_W <= w_triV(3);

end Behavioral;
