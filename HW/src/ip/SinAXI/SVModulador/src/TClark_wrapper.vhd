library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.declaraciones.all;

entity TClark_wrapper is
    port ( 
        -- Entradas trifásicas separadas
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);

        -- Salidas alfa-beta separadas
        o_alfa : out std_logic_vector(31 downto 0);
        o_beta : out std_logic_vector(31 downto 0)
    );
end TClark_wrapper;

architecture Behavioral of TClark_wrapper is

    -- Señales internas para conectar con el core
    signal w_uvw       : vector(1 to 3)(31 downto 0);
    signal w_alfa_beta : vector(1 to 2)(31 downto 0);

begin

    -- Instancia del bloque original
    tClark_core : entity work.TransformadaClark
        port map (
            i_uvw       => w_uvw,
            o_alfa_beta => w_alfa_beta
        );

    -- Mapear entradas
    w_uvw(1) <= i_U;
    w_uvw(2) <= i_V;
    w_uvw(3) <= i_W;

    -- Mapear salidas
    o_alfa <= w_alfa_beta(1);
    o_beta <= w_alfa_beta(2);


end Behavioral;
