library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.declaraciones.all;

entity AC_Source is
port (
    clk_in : in  std_logic;
    rst_in_n : in  std_logic;
    fcw_in  : in  std_logic_vector(3 downto 0);
    voltage_out : out matriz(1 to 3, 1 to 1)(8 downto 0)
);
end AC_Source;

architecture Behavioral of AC_Source is
    
    signal nco_a_cnt : unsigned(10 downto 0);
    signal nco_b_cnt : unsigned(10 downto 0);
    signal nco_c_cnt : unsigned(10 downto 0);

    component Seno_LT is
        port ( 
	        Address : in  std_logic_vector (10 downto 0);
	        Data : out  std_logic_vector (8 downto 0)
        );
    end component Seno_LT;

begin

    nco_a: process(clk_in,rst_in_n)
        begin
            if(rst_in_n='0') then
                nco_a_cnt <= (others=>'0');
            elsif(rising_edge(clk_in)) then
                nco_a_cnt <= nco_a_cnt + unsigned(fcw_in);
            end if;

    end process nco_a;

    nco_b: process(clk_in,rst_in_n)   
        begin
            if(rst_in_n='0') then
                nco_b_cnt <= to_unsigned(682, 11);
            elsif(rising_edge(clk_in)) then
                nco_b_cnt <= nco_b_cnt + unsigned(fcw_in);
            end if;

    end process nco_b;

    nco_c: process(clk_in,rst_in_n)
        begin
            if(rst_in_n='0') then
                nco_c_cnt <= to_unsigned(1365, 11);
            elsif(rising_edge(clk_in)) then
                nco_c_cnt <= nco_c_cnt + unsigned(fcw_in);
            end if;

    end process nco_c;

    seno_lt_a_inst: Seno_LT
     port map(
        Address => std_logic_vector(nco_a_cnt),
        Data => voltage_out(1,1)
    );

    seno_lt_b_inst: Seno_LT
     port map(
        Address => std_logic_vector(nco_b_cnt),
        Data => voltage_out(2,1)
    );

    seno_lt_c_inst: Seno_LT
     port map(
        Address => std_logic_vector(nco_c_cnt),
        Data => voltage_out(3,1)
    );

end Behavioral;
