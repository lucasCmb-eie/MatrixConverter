library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_SIGNED.all;
use ieee.fixed_pkg.all;

-- Se crean dos tipos de datos (matriz y vector) que son arreglos de tamanio a definir por parametros
-- Los elementos de estos arreglos son de tipo std_logic_vector de tamanio parametrizado
-- Los archivos del proyecto deben ser de tipo VHDL 2008
package Declaraciones is -- Nombre del package
  type vector is array (integer range <>) of std_logic_vector;
  type matriz is array (integer range <>, integer range <>) of std_logic_vector;
  type sfvector is array (integer range <>) of sfixed;
end;

package body declaraciones is

end; --Final de package
