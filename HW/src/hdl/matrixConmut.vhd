library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.declaraciones.all;

entity matrixConmut is
    port(
        i_clk: in std_logic;
        i_M: in std_logic_vector(17 downto 0);  -- Coeficientes dados por el algoritmo del modulador
        i_V: in vector(1 to 3)(8 downto 0);  -- Vector entrada con la señal trifasica

        o_V: out vector(1 to 3)(11 downto 0)
    );
end matrixConmut;

architecture Behavioral of matrixConmut is
    type vec9 is array (natural range <>) of signed(11 downto 0); 
    type matN is array (natural range <>, natural range <>) of std_logic;

    signal R_reg : vec9(0 to 2);    
    signal M: matN(0 to 2, 0 to 2);

    begin
        
    M <= (
        0 => (0 => i_M(0), 1 => i_M(1), 2 => i_M(2)),
        1 => (0 => i_M(3), 1 => i_M(4), 2 => i_M(5)),
        2 => (0 => i_M(6), 1 => i_M(7), 2 => i_M(8))
    );
    

    process (i_clk)
        variable acc : signed(11 downto 0);  -- 9 bits + 3 por las sumas
    begin
        if rising_edge(i_clk) then
            for j in 0 to 2 loop
            acc := (others => '0');
                for i in 0 to 2 loop
                    if M(i,j) = '1' then
                        acc := acc + resize(signed(i_V(i+1)), acc'length);
                    end if;
                end loop;
            R_reg(j) <= acc;
            end loop;
        end if;
    end process;

    o_V(1) <= std_logic_vector(R_reg(0));
    o_V(2) <= std_logic_vector(R_reg(1));
    o_V(3) <= std_logic_vector(R_reg(2));
end Behavioral;
