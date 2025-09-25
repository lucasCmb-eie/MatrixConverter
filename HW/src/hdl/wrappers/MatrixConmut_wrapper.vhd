library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.declaraciones.all;

entity MatrixConmut_wrapper is
    port (
        i_clk : in std_logic;
        i_M   : in std_logic_vector(17 downto 0);

        --Tensiones
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0)
     );
end MatrixConmut_wrapper;

architecture Behavioral of MatrixConmut_wrapper is

    signal w_Vi : vector(1 to 3)(31 downto 0);
    signal w_Vo : vector(1 to 3)(31 downto 0);

begin

    matrixConmut_core : entity work.matrixConmut
        port map (
            i_clk => i_clk,
            i_M   => w_direcciones,
            i_V   => w_Vi,
            o_V   => w_Vi
        );

    --Entradas de Tension
    w_Vi(1) <= i_U;
    w_Vi(2) <= i_V;
    w_Vi(3) <= i_W;

    --Salidas de Tension
    o_U <= w_Vo(1);
    o_V <= w_Vo(2);
    o_W <= w_Vo(3);

end Behavioral;
