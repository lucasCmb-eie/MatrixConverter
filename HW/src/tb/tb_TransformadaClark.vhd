library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_TransformadaClark is
end tb_TransformadaClark;

architecture Behavioral of tb_TransformadaClark is

    constant PER2 : time := (10 ns /2); --periodo/2 (el test será hecho con un test_clk_in de 100 KHz) Se alcanza una señal seno de 48.8Hz
    signal test_clk_in : std_logic;
    signal test_rst_in : std_logic;
    
    signal w_test_U : std_logic_vector(31 downto 0);
    signal w_test_V : std_logic_vector(31 downto 0);
    signal w_test_W : std_logic_vector(31 downto 0);

    signal w_test_alfa : std_logic_vector(31 downto 0);
    signal w_test_beta : std_logic_vector(31 downto 0);
    
begin

    --TransformadaClark
    UUT: entity work.TransformadaClark
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        i_start => '1',
        i_U => w_test_U,
        i_V => w_test_V,
        i_W => w_test_W,

        o_valido => open,
        -- Salidas de tensiones en el sistema alfa-beta
        o_alfa => w_test_alfa,
        o_beta => w_test_beta
        );

    DoClock: process
    begin
        test_clk_in <= '1';
        wait for PER2;
        test_clk_in <= '0';
        wait for PER2;
        
    end process DoClock;
    
    AC: entity work.AC_Source
    port map(
        i_clk => test_clk_in,
        i_rst => test_rst_in,
        
        o_U => w_test_U,
        o_V => w_test_V,
        o_W => w_test_W
        );
        
    --Init
    InitTest: process
    begin
            --Starting Test
            report "ncoLUT_tb start...";
            report "Reset";   
            test_rst_in <= '1';
            wait for (2*PER2);
            report "Begin";
            test_rst_in <= '0';
            wait;
    end process InitTest;
    
end Behavioral;