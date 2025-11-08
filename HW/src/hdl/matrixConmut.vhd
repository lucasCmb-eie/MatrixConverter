library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use ieee.fixed_pkg.all;

entity matrixConmut is
    port(
        i_clk: in std_logic;
        i_M: in std_logic_vector(17 downto 0);  -- Coeficientes dados por el algoritmo del modulador

        -- Tensiones de entrada trifasicas
        i_U: in std_logic_vector(31 downto 0);
        i_V: in std_logic_vector(31 downto 0);
        i_W: in std_logic_vector(31 downto 0);

        -- Tensiones de salida trifasicas conmutadas
        o_U: out std_logic_vector(31 downto 0);
        o_V: out std_logic_vector(31 downto 0);
        o_W: out std_logic_vector(31 downto 0)
    );
end matrixConmut;

 architecture Behavioral of matrixConmut is
    type vec_sfixed is array (natural range <>) of sfixed(7 downto -24); 			--Estas declaracionesde tipo solos se utilizan en este archivo
    type vector is array (natural range <>) of std_logic_vector(31 downto 0);
    type matN is array (natural range <>, natural range <>) of std_logic;	--es por eso que no se agregaron a declaraciones.vhd


    signal R_reg : vec_sfixed(0 to 2);    
    signal M: matN(0 to 2, 0 to 2);
    signal w_Vtrif : vector(1 to 3);


    begin
        
		--Creamos la Matriz a partir del vector de coeficientes de entrada
    M <= (
        0 => (0 => i_M(0), 1 => i_M(1), 2 => i_M(2)),
        1 => (0 => i_M(3), 1 => i_M(4), 2 => i_M(5)),
        2 => (0 => i_M(6), 1 => i_M(7), 2 => i_M(8))
    );

    w_Vtrif <= (
        1 => i_U,
        2 => i_V,
        3 => i_W
    );
    

    process (i_clk)
        variable acc : sfixed(9 downto -24) := to_sfixed(0.0, 9, -24);  -- Q8.24
        variable v_in : sfixed(7 downto -24) := to_sfixed(0.0, 7, -24);
    begin
        if rising_edge(i_clk) then
            for j in 0 to 2 loop
            acc := to_sfixed(0.0, 9, -24);
                for i in 0 to 2 loop
                    v_in := to_sfixed(w_Vtrif(i+1), 7, -24);
                    if M(i,j) = '1' then
                        acc := resize(acc + v_in, 9, -24);
                    end if;
                end loop;
            R_reg(j) <= resize(acc, 7, -24);
            end loop;
        end if;
    end process;

    o_U <= to_slv(R_reg(0));
    o_V <= to_slv(R_reg(1));
    o_W <= to_slv(R_reg(2));
end Behavioral;
