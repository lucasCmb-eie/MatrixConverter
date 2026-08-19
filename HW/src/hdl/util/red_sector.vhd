----------------------------------------------------------------------------------
-- Company:  FCEIA - UNR
-- Engineer: Sergio Geninatti
--
-- Create Date:    06:57:01 10/03/2022
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

  -- Uncomment the following library declaration if using
  -- arithmetic functions with Signed or Unsigned values
  -- use IEEE.NUMERIC_STD.ALL;
  use ieee.std_logic_unsigned.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

entity red_sector is
  port (
    al_o   : in    std_logic_vector(10 downto 0);
    be_i   : in    std_logic_vector(10 downto 0);
    estado : in    std_logic_vector(10 downto 0);
    clock  : in    std_logic;
    ki     : out   std_logic_vector(2 downto 0);
    kv     : out   std_logic_vector(2 downto 0);
    al_ot  : out   std_logic_vector(10 downto 0);
    be_it  : out   std_logic_vector(10 downto 0)
  );
end entity red_sector;

--
-- La codificaion de los angulos se hace con un numero entero de 11 bits dividiendo el giro completo de 2 PI en 2048 niveles.
--    PI/6 = 00010101011    1/6
--    PI/3 = 00101010101    2/6
--    PI/2 = 01000000000    3/6
--    2PI/3 = 01010101011    4/6
--    5PI/6 = 01101010101    5/6
--    PI    = 10000000000    6/6
--    7PI/6 = 10010101011    7/6
--    4PI/3 = 10101010101    8/6
--    3PI/2 = 11000000000    9/6
--    5PI/3 = 11010101011    10/6
--   11PI/6 = 11101010101    11/6
--

architecture behavioral of red_sector is

  signal op_al_o,   op_be_i   : std_logic_vector(11 downto 0) := "000000000000";
  signal res_al_o,  res_be_i  : std_logic_vector(11 downto 0) := "000000000000";
  signal tmp_al_o,  tmp_be_i  : std_logic_vector(11 downto 0) := "000000000000";
  signal al_ot_tmp, be_it_tmp : std_logic_vector(10 downto 0) := "00000000000";
  signal al_ot_ok,  be_it_ok  : std_logic                     := '0';

begin

  --
  -- Proceso de estado
  --
  op_al_o <= '0' & al_o;
  -- Sumo PI/6 para usar los mismos limites que al_o para definir los sectores.
  --
  -- LOS PARENTESIS SON OBLIGATORIOS. En VHDL '&' y '+' tienen la MISMA precedencia y
  -- asocian a izquierda, asi que "'0' & be_i + 171" se leia como "('0' & be_i) + 171":
  -- la suma se hacia en 12 bits y NUNCA envolvia modulo 2048. Con be_i de 11 bits
  -- op_be_i llegaba a 2047 + 171 = 2218, y para be_i en [1877, 2047] -- o sea 171 de
  -- 2048 = 8,35 % del periodo de entrada -- la cadena de restas de abajo no encontraba
  -- ningun corte y caia al else final: ki = 6 en vez de 1, con be_it errado en 59,9
  -- grados. Sumando en 11 bits la cuenta envuelve sola.
  --
  -- Medido sobre 0,2 s de simulacion (60 Hz in / 50 Hz out): agrupando el residuo del
  -- tiempo activo por sector, el eje de salida daba plano (+-0,0003) y el de entrada
  -- tenia un solo sector disparado, +0,0672 contra -0,013 de los otros cinco. Modelar
  -- el desborde bajaba el residuo a 60 Hz 9,1 veces y a 120 Hz 8,1 veces.
  --
  -- op_al_o no necesita nada: no suma, asi que nunca pasa de 2047.
  op_be_i <= '0' & (be_i + "00010101011");

  process (clock) is
  begin

    if (clock = '1' and clock'event) then         -- Flanco de descendente

      case estado is

        when "00000000000" =>                     -- Inicio de la reduccion al primer sector.

          res_al_o <= op_al_o - "000101010101";   -- Resta PI/3
          al_ot_ok <= '0';

        when "00000000001" =>                     --

          if (res_al_o (11) = '1') then
            kv        <= "001";                   -- Fija el sector
            al_ot_tmp <= op_al_o(10 downto 0);    -- Retiene valor al primer sector
            al_ot_ok  <= '1';
          else
            tmp_al_o <= res_al_o;
          end if;
          res_al_o <= op_al_o - "001010101011";   -- Resta 2PI/3

        when "00000000010" =>                     --

          if (al_ot_ok = '0') then
            if (res_al_o (11) = '1') then
              kv        <= "010";
              al_ot_tmp <= tmp_al_o(10 downto 0);
              al_ot_ok  <= '1';
            else
              tmp_al_o <= res_al_o;
            end if;
          end if;
          res_al_o <= op_al_o - "010000000000";   -- Resta PI

        when "00000000011" =>                     --

          if (al_ot_ok = '0') then
            if (res_al_o (11) = '1') then
              kv        <= "011";
              al_ot_tmp <= tmp_al_o(10 downto 0);
              al_ot_ok  <= '1';
            else
              tmp_al_o <= res_al_o;
            end if;
          end if;
          res_al_o <= op_al_o - "010101010101";   -- Resta 4PI/3

        when "00000000100" =>                     --

          if (al_ot_ok = '0') then
            if (res_al_o (11) = '1') then
              kv        <= "100";
              al_ot_tmp <= tmp_al_o(10 downto 0);
              al_ot_ok  <= '1';
            else
              tmp_al_o <= res_al_o;
            end if;
          end if;
          res_al_o <= op_al_o - "011010101011";   -- Resta 5PI/3

        when "00000000101" =>                     --

          if (al_ot_ok = '0') then
            if (res_al_o (11) = '1') then
              kv        <= "101";
              al_ot_tmp <= tmp_al_o(10 downto 0);
            else
              kv        <= "110";
              al_ot_tmp <= res_al_o(10 downto 0);
            end if;
          end if;

        when "00000000110" =>                     -- Final de la reduccion al primer sector.

          al_ot <= al_ot_tmp - "00010101011";

        when others =>                            --

      end case;

    end if;

  end process;

  process (clock) is
  begin

    if (clock = '1' and clock'event) then         -- Flanco de descendente

      case estado is

        when "00000000000" =>                     -- Inicio de la reduccion al primer sector.

          res_be_i <= op_be_i - "000101010101";   -- Resta PI/3
          be_it_ok <= '0';

        when "00000000001" =>                     --

          if (res_be_i (11) = '1') then
            ki        <= "001";
            be_it_tmp <= op_be_i(10 downto 0);
            be_it_ok  <= '1';
          else
            tmp_be_i <= res_be_i;
          end if;
          res_be_i <= op_be_i - "001010101011";   -- Resta 2PI/3

        when "00000000010" =>                     --

          if (be_it_ok = '0') then
            if (res_be_i (11) = '1') then
              ki        <= "010";
              be_it_tmp <= tmp_be_i(10 downto 0);
              be_it_ok  <= '1';
            else
              tmp_be_i <= res_be_i;
            end if;
          end if;
          res_be_i <= op_be_i - "010000000000";   -- Resta PI

        when "00000000011" =>                     --

          if (be_it_ok = '0') then
            if (res_be_i (11) = '1') then
              ki        <= "011";
              be_it_tmp <= tmp_be_i(10 downto 0);
              be_it_ok  <= '1';
            else
              tmp_be_i <= res_be_i;
            end if;
          end if;
          res_be_i <= op_be_i - "010101010101";   -- Resta 4PI/3

        when "00000000100" =>                     --

          if (be_it_ok = '0') then
            if (res_be_i (11) = '1') then
              ki        <= "100";
              be_it_tmp <= tmp_be_i(10 downto 0);
              be_it_ok  <= '1';
            else
              tmp_be_i <= res_be_i;
            end if;
          end if;
          res_be_i <= op_be_i - "011010101011";   -- Resta 5PI/3

        when "00000000101" =>                     --

          if (be_it_ok = '0') then
            if (res_be_i (11) = '1') then
              ki        <= "101";
              be_it_tmp <= tmp_be_i(10 downto 0);
            else
              ki        <= "110";
              be_it_tmp <= res_be_i(10 downto 0);
            end if;
          end if;

        when "00000000110" =>                     -- Final de la reduccion al primer sector.

          be_it <= be_it_tmp - "00010101011";

        when others =>                            --

      end case;

    end if;

  end process;

end architecture behavioral;

