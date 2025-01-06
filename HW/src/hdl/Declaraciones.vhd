----------------------------------------------------------------------------------
-- Company: DSI/FCEIA/UNR
-- Engineer: Curso SoC
-- 
-- Create Date: 02.12.2021 16:43:56
-- Design Name: 
-- Module Name: Declaraciones - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: Paquete en el que se definen los tipos de datos que se utilizaran
-- para describir la red neuronal
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;

-- Se crean dos tipos de datos (matriz y vector) que son arreglos de tamanio a definir por parametros
-- Los elementos de estos arreglos son de tipo std_logic_vector de tamanio parametrizado
-- Los archivos del proyecto deben ser de tipo VHDL 2008
package Declaraciones is -- Nombre del package
  type vector is array (integer range <>) of std_logic_vector;
  type matriz is array (integer range <>, integer range <>) of std_logic_vector;
end;

package body declaraciones is

end; --Final de package
