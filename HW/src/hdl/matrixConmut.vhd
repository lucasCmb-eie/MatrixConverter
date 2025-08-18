library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.declaraciones.all;

entity matrixConmut is
    port(
        i_clk: in std_logic;
        i_M: in std_logic_vector(17 downto 0);  -- Coeficientes dados por el algoritmo del modulador
        i_V: in matriz(1 to 3, 1 to 1)(8 downto 0);  -- Vector entrada con la señal trifasica

        o_V: out matriz(1 to 3, 1 to 1)(9 downto 0)
    );
end matrixConmut;

architecture Behavioral of matrixConmut is

    signal s_matrix: matriz(1 to 3, 1 to 3)(0 downto 0);

    begin

        gen_input_mapping: for i in 0 to 2 generate
            gen_matrix_cols: for j in 1 to 3 generate
                s_matrix(i + 1, j) <= i_M((i * 3) + j);
            end generate;
        end generate;

        process (i_clk)
        variable v_sum: signed(9 downto 0);
        begin
            if rising_edge(i_clk) then
                for i in 1 to 3 loop
                    v_sum := (others => '0');

                    for j in 1 to 3 loop
                        if(s_matrix(i, j) = '1') then
                            v_sum := v_sum + signed(i_V(i, 1));
                        end if;
                    end loop; -- Coeficientes Matrices
                
                    o_V(i,1) <= STD_LOGIC_VECTOR(v_sum);
                end loop; -- Entrada
            end if;
        end process;
end Behavioral;
