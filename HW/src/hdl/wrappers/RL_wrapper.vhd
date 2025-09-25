library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

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

    

begin

    RL_core : entity work.RL
        generic map (
            INT_BITS  => 8,
            FRAC_BITS => 24
        )
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_c_a0  => to_sfixed(i_c_a0, 7, -24),
            i_c_a1  => to_sfixed(i_c_a1, 7, -24),
            i_c_b1  => to_sfixed(i_c_b1, 7, -24),
            i_Vi    => (1 => i_U, 2 => i_V, 3 => i_W),
            o_IL    => (1 => o_U, 2 => o_V, 3 => o_W)
        );

end Behavioral;
