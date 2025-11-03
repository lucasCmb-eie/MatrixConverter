library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

use work.declaraciones.all;

entity RL_wrapper is
    port (
        -- Señales de control
        i_clk     : in  std_logic;
        i_rst   : in  std_logic; -- Reset asíncrono activo a nivel bajo

        -- Coeficientes del filtro (entradas configurables)
        i_c_a0    : in  std_logic_vector(31 downto 0);
        i_c_a1    : in  std_logic_vector(31 downto 0);
        i_c_b1    : in  std_logic_vector(31 downto 0);

        -- Puertos de datos
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0)
     );
end RL_wrapper;

architecture Behavioral of RL_wrapper is

    signal tick_enable : std_logic;
    signal s_Ol : vector(1 to 3)(31 downto 0);
    signal s_Iv : vector(1 to 3)(31 downto 0);

begin

    -- Generador de enable cada 64 µs
    U_EnableGen : entity work.EnableGen
        generic map (
            CLK_FREQ_HZ => 100000000,
            TCONV_US    => 16     -- Tconv = 16 µs
        )
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,
            o_tick => tick_enable
        );

    RL_core : entity work.RL
        generic map (
            INT_BITS  => 8,
            FRAC_BITS => 24
        )
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_enable => tick_enable,
            i_c_a0  => to_sfixed(i_c_a0, 7, -24),
            i_c_a1  => to_sfixed(i_c_a1, 7, -24),
            i_c_b1  => to_sfixed(i_c_b1, 7, -24),
            i_Vi    => s_Iv,
            o_IL    => s_Ol
        );

    --Asignacion de salidas
    o_U <= s_Ol(1);
    o_V <= s_Ol(2);
    o_W <= s_Ol(3);

    --Asignacion de entradas
    s_Iv(1) <= i_U;
    s_Iv(2) <= i_V;
    s_Iv(3) <= i_W;

end Behavioral;
