----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 24.05.2025 16:52:45
-- Design Name: 
-- Module Name: matrix_model - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity matrix_model is
    Port ( 
            i_clk   : in std_logic;
            i_coeficientes : in STD_LOGIC_VECTOR (8 downto 0);
            
            o_tension_trif : out STD_LOGIC_VECTOR (2 downto 0)
        );
end matrix_model;

architecture Behavioral of matrix_model is

begin

--NCO+seno o alguna forma de simular trifasica a la entrada

--Producto entre la trifasica de entrada y los coef para obtener la salida


end Behavioral;
