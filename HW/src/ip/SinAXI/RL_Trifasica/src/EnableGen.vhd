library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity EnableGen is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  -- 100 MHz
        TCONV_US    : integer := 16            -- 64 µs o 16 µs según XADC
    );
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;
        o_tick : out std_logic
    );
end entity;

architecture Behavioral of EnableGen is
    constant COUNT_MAX : integer := (CLK_FREQ_HZ / 1_000_000) * TCONV_US - 1;
    signal counter     : integer range 0 to COUNT_MAX := 0;
    signal tick_int    : std_logic := '0';
begin
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            counter  <= 0;
            tick_int <= '0';
        elsif rising_edge(i_clk) then
            if counter = COUNT_MAX then
                counter  <= 0;
                tick_int <= '1';
            else
                counter  <= counter + 1;
                tick_int <= '0';
            end if;
        end if;
    end process;

    o_tick <= tick_int;
end architecture;
