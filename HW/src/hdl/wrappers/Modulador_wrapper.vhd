library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Modulador_wrapper is
    port (
        i_clk    : in std_logic; --! Reloj de sistema
        i_enable : in std_logic; --! Habilitacion del modulador
        i_al_o   : in std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
        i_be_i   : in std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
        i_q_i    : in std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
        i_phi_i  : in std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz
        
        o_direcciones : out std_logic_vector(17 downto 0); 
        o_fin_ciclo    : out std_logic;                    
        o_inicio_ciclo : out std_logic;                    
        o_fin_calc_ts  : out std_logic;
     );
end Modulador_wrapper;

architecture Behavioral of Modulador_wrapper is

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
            o_direcciones  => o_direcciones
        );

end Behavioral;
