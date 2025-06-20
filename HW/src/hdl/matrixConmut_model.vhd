----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 28.05.2025 22:10:30
-- Design Name: 
-- Module Name: matrixConmut_model - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.declaraciones.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity matrixConmut_model is
    port(
        i_clk: in std_logic;
        i_M: in std_logic_vector(17 downto 0);  -- Coeficientes dados por el algoritmo del modulador
        i_U: in matriz(1 to 3, 1 to 1)(8 downto 0);  -- Vector entrada con la señal trifasica

        o_Y: out matriz(1 to 3, 1 to 1)(8 downto 0)
    );
end matrixConmut_model;

architecture Behavioral of matrixConmut_model is

begin


end Behavioral;
