library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

use work.sine_lut_pkg.all;

--!
-- Fuente trifasica de señal senoidal
entity AC_Source is
port (
    i_clk : in  std_logic; --! Entrada de Clock : 100KHz
    i_rst : in  std_logic; --! Reset

    o_U : out std_logic_vector(31 downto 0); --! Salida de tensión de linea U
    o_V : out std_logic_vector(31 downto 0); --! Salida de tensión de linea V
    o_W : out std_logic_vector(31 downto 0) --! Salida de tensión de linea W
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
            sine_out : out signed(31 downto 0)
        );
    end component;

    signal w_lineaU : SIGNED(31 downto 0);
    signal w_lineaV : SIGNED(31 downto 0);
    signal w_lineaW : SIGNED(31 downto 0);
    

begin

    --Declaracion de cada una de las tensiones de linea

    Linea_U: entity work.sine_generator
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

        o_U <= std_logic_vector(w_lineaU);
        o_V <= std_logic_vector(w_lineaV);
        o_W <= std_logic_vector(w_lineaW);

end Behavioral;
