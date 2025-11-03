library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity PhaseSawGen_wrapper is
    port (
        i_clk    : in  std_logic;
        i_rst    : in  std_logic;
        i_sin    : in  std_logic_vector(31 downto 0);
        o_angle  : out std_logic_vector(10 downto 0)
     );
end PhaseSawGen_wrapper;

architecture Behavioral of PhaseSawGen_wrapper is

begin

    PhaseSawGen_core: entity work.PhaseSawGen
     generic map(
        G_CLK_FREQ => 1.0e8,
        G_F_SINE => 50
    )
     port map(
        i_clk => i_clk,
        i_rst => i_rst,
        i_sin => to_sfixed(i_sin, 7, -24),
        o_angle => o_angle
    );

end Behavioral;
