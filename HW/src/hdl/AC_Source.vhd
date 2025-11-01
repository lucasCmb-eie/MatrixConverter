library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

use work.declaraciones.all;
use work.sine_lut_pkg.all;

--!
-- Fuente trifasica de señal senoidal
entity AC_Source is
port (
    i_clk : in  std_logic; --! Entrada de Clock : 100KHz
    i_rst : in  std_logic; --! Reset

    o_triV : out vector(1 to 3)(SINE_DATA_WIDTH - 1 downto 0) --! Salida de tensiones trifasicas (U, V ,W)
);
end AC_Source;

architecture Behavioral of AC_Source is

    -- Constantes para las fases
    constant PHASE_0   : unsigned(31 downto 0) := x"00000000";
    constant PHASE_120 : unsigned(31 downto 0) := x"55555555";  -- 120°
    constant PHASE_240 : unsigned(31 downto 0) := x"AAAAAAA9";  -- 240° (≈ 2863311530)

    --Declaración de componenete padre
    component sine_generator is
        generic (
            PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
        );
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            sine_out : out signed(SINE_DATA_WIDTH - 1 downto 0)
        );
    end component;

    signal w_lineaU : SIGNED(SINE_DATA_WIDTH - 1 downto 0);
    signal w_lineaV : SIGNED(SINE_DATA_WIDTH - 1 downto 0);
    signal w_lineaW : SIGNED(SINE_DATA_WIDTH - 1 downto 0);
    

begin

    --Declaracion de cada una de las tensiones de linea

    Linea_U: sine_generator
        generic map (
            PHASE_INITIAL => PHASE_0
        )
        port map (
            clk   => i_clk,
            reset => i_rst,
            
            sine_out => w_lineaU
        );

    Linea_V: sine_generator
        generic map (
            PHASE_INITIAL => PHASE_120
        )
        port map (
            clk   => i_clk,
            reset => i_rst,
            
            sine_out => w_lineaV
        );

    Linea_W: sine_generator
        generic map (
            PHASE_INITIAL => PHASE_240
        )
        port map (
            clk   => i_clk,
            reset => i_rst,
            
            sine_out => w_lineaW
        );

    --Asignacion de salidas
    o_triV(1) <= std_logic_vector(w_lineaU);
    o_triV(2) <= std_logic_vector(w_lineaV);
    o_triV(3) <= std_logic_vector(w_lineaW);

end Behavioral;
