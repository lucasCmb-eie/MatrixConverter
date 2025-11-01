library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.declaraciones.all;


entity SVM_wrapper is
    port (
        i_clk    : in std_logic; --! Reloj de sistema
        i_enable : in std_logic; --! Habilitacion del modulador
        i_al_o   : in std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
        i_be_i   : in std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
        i_q_i    : in std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
        i_phi_i  : in std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

        o_fin_ciclo    : out std_logic;                    
        o_inicio_ciclo : out std_logic;                    
        o_fin_calc_ts  : out std_logic;

        --Tensiones 
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0)
     );
end SVM_wrapper;

architecture Behavioral of SVM_wrapper is

    signal w_direcciones : std_logic_vector(17 downto 0); --Coeficientes de la matriz de conmutacion
    signal w_o_V : vector(1 to 3)(31 downto 0);
    signal w_i_V : vector(1 to 3)(31 downto 0);

begin

    modulador_core : entity work.modulador
        port map (
            i_reloj        => i_clk,
            i_enable       => i_enable,
            i_al_o         => i_al_o,
            i_be_i         => i_be_i,
            i_q_i          => i_q_i,
            i_phi_i        => i_phi_i, 
            o_fin_ciclo    => o_fin_ciclo,
            o_inicio_ciclo => o_inicio_ciclo,
            o_fin_calc_ts  => o_fin_calc_ts,
            o_direcciones  => w_direcciones
        );

    matrixConmut_core : entity work.matrixConmut
        port map (
            i_clk => i_clk,
            i_M   => w_direcciones,
            i_V   => w_i_V,
            o_V   => w_o_V
        );

    --Entradas de Tension
    w_i_V(1) <= i_U;
    w_i_V(2) <= i_V;
    w_i_V(3) <= i_W;

    --Salidas de Tension
    o_U <= w_o_V(1);
    o_V <= w_o_V(2);
    o_W <= w_o_V(3);

end Behavioral;
