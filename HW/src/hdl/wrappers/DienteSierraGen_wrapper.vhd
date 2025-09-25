library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity DienteSierraGen_wrapper is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_k       : in  std_logic_vector(11 downto 0); -- factor K (1..2000 aprox)

        o_saw     : out std_logic_vector(31 downto 0)   -- salida Q8.24
     );
end DienteSierraGen_wrapper;

architecture Behavioral of DienteSierraGen_wrapper is
    
    signal w_uk : unsigned(11 downto 0);
    signal w_out : sfixed(7 downto -24);

begin

    DienteSierraGen_core : entity work.DienteSierraGen
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_k => w_uk,

            o_saw => w_out
        );

    w_uk <= unsigned(i_k);
    o_saw <= to_slv(w_out);

end Behavioral;
