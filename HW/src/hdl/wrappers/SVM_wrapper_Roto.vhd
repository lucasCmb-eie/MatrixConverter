library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity SVM_wrapper_Roto is
    port (
        i_clk    : in std_logic; --! Reloj de sistema
        i_enable : in std_logic; --! Habilitacion del modulador
        i_al_o   : in std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
        i_be_i   : in std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
        i_q_i    : in std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
        i_phi_i  : in std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

        o_trg_calculo    : out std_logic;

        --Tensiones 
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0)
     );
end SVM_wrapper_Roto;

architecture Behavioral of SVM_wrapper_Roto is

    signal w_direcciones : std_logic_vector(17 downto 0); --Coeficientes de la matriz de conmutacion
    signal fin_calc_ts : std_logic; 
    signal fin_calc_ts_prev : std_logic;
    signal fin_calc_ts_falling : std_logic;

begin

    modulador_core : entity work.modulador_roto
        port map (
            i_reloj        => i_clk,
            i_enable       => i_enable,
            i_al_o         => i_al_o,
            i_be_i         => i_be_i,
            i_q_i          => i_q_i,
            i_phi_i        => i_phi_i, 
            o_fin_ciclo    => open,
            o_inicio_ciclo => open,
            o_fin_calc_ts  => fin_calc_ts,
            o_direcciones  => w_direcciones
        );

    matrixConmut_core : entity work.matrixConmut
        port map (
            i_clk => i_clk,
            i_M   => w_direcciones,
            i_U => i_U,
            i_V => i_V,
            i_W => i_W,

            o_U => o_U,
            o_V => o_V,
            o_W => o_W
        );

    EDGE_DETECTOR_PROC : process(i_clk)
        begin
            if rising_edge(i_clk) then

                fin_calc_ts_prev <= fin_calc_ts;
                fin_calc_ts_falling <=  (NOT fin_calc_ts) AND (fin_calc_ts_prev);

            end if;
        end process;

    o_trg_calculo <= fin_calc_ts_falling;
    
end Behavioral;
