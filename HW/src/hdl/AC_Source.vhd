library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

use work.sine_lut_pkg.all;

--!
-- Fuente trifasica de señal senoidal
--
-- Las tres fases comparten el mismo step de NCO, asi que la frecuencia de salida
-- se varia en tiempo de ejecucion escribiendo 'i_frec' (ver la formula abajo).
entity AC_Source is
port (
    i_clk : in  std_logic; --! Entrada de Clock : 10 MHz
    i_rst : in  std_logic; --! Reset
    --! Step del NCO que fija la frecuencia de salida de las tres fases:
    --!     i_frec = round(f_out * 2**32 / f_clk)
    --! Con f_clk = 10 MHz -> i_frec = round(f_out * 429.4967296), o sea
    --!     50 Hz -> 21475 (x"000053E3")      60 Hz -> 25770 (x"000064AA")
    --! Por defecto 50 Hz.
    i_frec : in  std_logic_vector(31 downto 0) := x"000053E3";

    o_U : out std_logic_vector(31 downto 0); --! Salida de tensión de linea U
    o_V : out std_logic_vector(31 downto 0); --! Salida de tensión de linea V
    o_W : out std_logic_vector(31 downto 0) --! Salida de tensión de linea W
);
end AC_Source;

architecture Behavioral of AC_Source is

    -- Constantes para las fases.
    -- Secuencia POSITIVA (U -> V -> W): con una tabla de SENOS y la transformada de Clark
    -- del proyecto (alfa = 2/3*(U - (V+W)/2), beta = 1/sqrt(3)*(V - W)) hace falta
    --      U = sin(t),  V = sin(t - 120°),  W = sin(t + 120°)
    -- que da alfa = sin(t), beta = -cos(t), o sea un vector e^j(t - PI/2) que gira en
    -- sentido directo. Si se asigna V = +120° y W = +240° el vector gira al reves
    -- (secuencia negativa), que es lo que tenia este bloque antes.
    constant PHASE_0    : unsigned(31 downto 0) := x"00000000";
    constant PHASE_N120 : unsigned(31 downto 0) := x"AAAAAAA9";  -- -120° (= 240°)
    constant PHASE_P120 : unsigned(31 downto 0) := x"55555555";  -- +120°

    --Declaración de componenete padre
    component sine_generator is
        generic (
            PHASE_INITIAL : unsigned(31 downto 0) := (others => '0')
        );
        port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            frec_inp : in  std_logic_vector(31 downto 0);

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
            frec_inp => i_frec,

            sine_out => w_lineaU
        );

    Linea_V: sine_generator
        generic map (
            PHASE_INITIAL => PHASE_N120
        )
        port map (
            clk   => i_clk,
            reset => i_rst,
            frec_inp => i_frec,

            sine_out => w_lineaV
        );

    Linea_W: sine_generator
        generic map (
            PHASE_INITIAL => PHASE_P120
        )
        port map (
            clk   => i_clk,
            reset => i_rst,
            frec_inp => i_frec,

            sine_out => w_lineaW
        );

        o_U <= std_logic_vector(w_lineaU);
        o_V <= std_logic_vector(w_lineaV);
        o_W <= std_logic_vector(w_lineaW);

end Behavioral;
