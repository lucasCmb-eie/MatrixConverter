library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity AC_Source is
generic (
    ncoBits : integer := 10; --Cantidad de bits para el contador del NCO
    freqControlBits : integer := 9
); --Cantidad de bits para la palabra de control

port (
    clk_in : in  std_logic;
    rst_in_n : in  std_logic;
    fcw_in : in  std_logic_vector(freqControlBits-1 downto 0);
    nco_out : out std_logic_vector(ncoBits-1 downto 0)
);

end AC_Source;

architecture Behavioral of AC_Source is
    
    signal nco_cnt : unsigned(ncoBits-1 downto 0);

begin

    doNCO: process(clk_in,rst_in_n)
        begin
            if(rst_in_n='0') then
                nco_cnt <= (others=>'0');
            elsif(rising_edge(clk_in)) then
                nco_cnt <= nco_cnt + unsigned(fcw_in);
            end if;

    end process doNCO;

    nco_out <= std_logic_vector(nco_cnt);

end Behavioral;
