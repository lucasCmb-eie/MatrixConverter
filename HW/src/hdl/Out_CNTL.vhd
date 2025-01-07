----------------------------------------------------------------------------------
-- Create Date:    18:12:30 08/02/2023
-- Design Name:  Sergio Geninatti
-- Project Name:
-- Revision 1.00
-- Additional Comments:
----------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  -- use IEEE.STD_LOGIC_ARITH.ALL;
  use ieee.std_logic_unsigned.all;

library unisim;
  use unisim.vcomponents.all;

entity out_cntl is
  port (
    cnt_trig  : in    std_logic;
    clock     : in    std_logic;
    ir_0      : in    std_logic_vector(8 downto 0); -- Referencia
    ir_1      : in    std_logic_vector(8 downto 0);
    io_u      : in    std_logic_vector(8 downto 0);
    io_v      : in    std_logic_vector(8 downto 0);
    io_w      : in    std_logic_vector(8 downto 0);
    vo_star_0 : inout std_logic_vector(15 downto 0);
    vo_star_1 : inout std_logic_vector(15 downto 0)
  );
end entity out_cntl;

architecture behavioral of out_cntl is

  -- type Iodef is array (1 downto 0) of STD_LOGIC_VECTOR (8 downto 0);

  --  Resolucion de Io trifasica
  --                                 1
  --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
  --    |17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
  --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
  --               |                  | |        |
  --               '------------------------' '---------'
  --                        |            |
  --                        |            '---> Decimales (4 bits)
  --                        '---------> Resolucion de medicion (9 bits)
  --
  --  Resolucion de Vo_star
  --                                     1
  --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
  --    |17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
  --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
  --      |                              | |    |
  --      '--------------------------------------------' '---'
  --                    |                  |
  --                    |                  '---> Decimales (2 bits)
  --                    '-----------------> Resolucion de medicion (16 bits)
  --  Resolucion de X
  --                                             1
  --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
  --    |35|34|33|32|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
  --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
  --                                 1
  --  Resolucion de Io bifasica
  --                                           1
  --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
  --    |35|34|33|32|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
  --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
  --                                 1
  signal x1 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000"; -- X es la variable de estado del observador
  signal x2 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal x3 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal x4 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal x5 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal x6 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";

  signal s_1 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000"; -- X_ es una variable intermedia para el calculo
  signal s_2 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000"; --    del nuevo estado
  signal s_3 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal s_4 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal s_5 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal s_6 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";

  signal y1 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal y2 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal y3 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal y4 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";

  signal prodp01 : std_logic_vector(35 downto 0);
  signal proda01 : std_logic_vector(17 downto 0);
  signal prodb01 : std_logic_vector(17 downto 0);

  signal prodp02 : std_logic_vector(35 downto 0);
  signal proda02 : std_logic_vector(17 downto 0);
  signal prodb02 : std_logic_vector(17 downto 0);

  signal vog_0_long : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal vog_1_long : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";

  signal io_0 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";
  signal io_1 : std_logic_vector(35 downto 0) := "000000000000000000000000000000000000";

  signal sumaprodp01 : std_logic_vector(35 downto 0);
  signal auxi01      : std_logic_vector(35 downto 0);
  signal auxi02      : std_logic_vector(35 downto 0);
  signal auxi03      : std_logic_vector(35 downto 0);
  signal auxi04      : std_logic_vector(35 downto 0);

  signal vog_0, vog_1 : std_logic_vector(8 downto 0);

  signal stat : std_logic_vector(4 downto 0) := "00000";

begin

  --
  --    Control de maquina de estados
  --
  process (clock) is
  begin

    if (clock = '1' and clock'event) then    -- Flanco de ascendente
      if (stat = "11000") then
        if (cnt_trig = '1') then
          stat <= "00000";
        end if;
      else
        stat <= stat + "00001";
      end if;
    end if;

  end process;

  --
  process (clock) is
  begin

    if (clock = '1' and clock'event) then     -- Flanco de ascendente
      --
      --    Avance de estado disparado por el TIC de muestreo de la Matriz (41 uS)
      --
      ----------------------------------------------------------------------------------
      -- Ao= [      0.6325    0.0044    0        0        0        0
      --          -9.3689    0.9987    -0.0502    0        0        0
      --             3.6770    0.0502    0.9987    0        0        0
      --              0        0        0        0.6325    0.0044    0
      --              0        0        0        -9.3689    0.9987    -0.0502
      --              0        0        0        3.6770    0.0502    0.9987  ]
      --
      ----------------------------------------------------------------------------------
      -- Bo= [      0.0044    0        0.3453    0
      --          0        0        9.3689    0
      --          0        0        -3.6770    0
      --          0        0.0044    0        0.3453
      --          0        0        0        9.3689
      --          0        0        0        -3.6770  ]
      --
      --  V_io = [   Vo_star_0  Vo_star_1  Io_0      Io_1  ]
      --
      --
      --  Resolucion de las constantes de la matriz (maximo valor entero -> +/- 15,xxxxxx
      -- (las constantes se multiplican por 8.192)
      --              1
      --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
      --    |17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
      --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
      --     |          | |                          |
      --     '------------' '------------------------------------'
      --          |                  |
      --          |                  '---> Decimales (13 bits)
      --          '---------> Resolucion de enteros (5 bits)
      --
      --  Resolucion de X reducido
      --                                  1
      --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
      --    |17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
      --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
      --     |                              | |      |
      --     '------------------------------------------' '------'
      --                      |                |
      --                      |                '---> Decimales (3 bits)
      --                      '---------> Resolucion de enteros (15 bits)
      -----------------------------------------------------------------------------------------
      --  Organizacion de calculo de estado: X(k+1) = A * X(K) + B * V_io
      --    En el calculo de A * X(K) se acumulan los resultados en un vector de suma temporal
      --    llamado S_, para evitar alterar X(K) hasta que ya no se necesite, esto ocurre entre
      --    los estados "00000" y "10100".
      --    Luego a partir del estado "10101" la acumulacion del producto B * V_io se hace
      --    directamente en X para generar el X(k+1) porque ya no se necesita X(K).
      --    En el estado "11010" se completa el calculo de la transicion de estado X(k+1).
      -----------------------------------------------------------------------------------------
      -- Ajuste de resolucion de los multiplicadores:
      --    Los términos de X tienen 36 bits de resolucion y los operandos de multiplicacion
      --    tienen 18 bit, para maximisar el rendimiento de los rangos numericos se recorta X
      --    desplazando las constantes que multiplican en cada operacion.
      --    La ubicacion del punto decimal del resultado de las multiplicaciones debe ser fijo
      --    para que puedan acumularse en el producto matricial.
      --
      --
      --
      case stat is

        when "00000" =>                       -- Termino A11*X1

          proda01 <= x1(30 downto 13);
          prodb01 <= "000001010000111101";    --   A11 = 0.6325 * 8.192

        when "00001" =>                       -- Termino A21*X1

          s_1     <= prodp01;                 -- Almacena A11*X1
          prodb01 <= "101101010000110010";    --   A21 = -9.3689 * 8.192

        when "00010" =>                       -- Termino A31*X1

          s_2     <= prodp01;                 -- Almacena A21*X1
          prodb01 <= "000111010110101010";    --   A31 = 3.6770 * 8.192

        when "00011" =>                       -- Termino A12*X2

          s_3     <= prodp01;                 -- Almacena A31*X1
          proda01 <= x2(30 downto 13);
          prodb01 <= "000000000000100100";    --   A12 = 0.0044 * 8.192

        when "00100" =>                       -- Termino A22*X2

          auxi01  <= prodp01;                 -- Desocupa el multiplicador (A12*X2)
          prodb01 <= "000001111111110101";    --   A22 = 0.9987 * 8.192

        when "00101" =>                       -- Termino A32*X2

          s_1     <= s_1 + auxi01;            -- Suma A11*X1 + A12*X2
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (A22*X2)
          prodb01 <= "000000000110011011";    --   A32 = 0.0502 * 8.192

        when "00111" =>                       -- Termino A23*X3

          s_2     <= s_2 + auxi02;            -- Suma A21*X1 + A22*X2
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (A32*X2)
          proda01 <= x3(30 downto 13);
          prodb01 <= "111111111001100101";    --   A23 = -0.0502 * 8.192

        when "01000" =>                       -- Termino A33*X3

          s_3     <= s_3 + auxi01;            -- Suma A31*X1 + A32*X2
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (A23*X3)
          prodb01 <= "000001111111110101";    --   A33 = 0.9987 * 8.192

        when "01001" =>                       -- Termino A44*X4

          s_2     <= s_2 + auxi02;            -- Suma A21*X1 + A22*X2 + A23*X3
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (A33*X3)
          proda01 <= x4(30 downto 13);
          prodb01 <= "000001010000111101";    --   A44 = 0.6325 * 8.192

        when "01010" =>                       -- Termino A54*X4

          s_3     <= s_3 + auxi01;            -- Suma A31*X1 + A32*X2 + A33*X3
          s_4     <= prodp01;                 -- Almacena A44*X4
          prodb01 <= "101101010000110010";    --   A54 = -9.3689 * 8.192

        when "01011" =>                       -- Termino A64*X4

          s_5     <= prodp01;                 -- Almacena A54*X4
          prodb01 <= "000111010110101010";    --   A64 = 3.6770 * 8.192

        when "01100" =>                       -- Termino A45*X5

          s_6     <= prodp01;                 -- Almacena A64*X4
          proda01 <= x5(30 downto 13);
          prodb01 <= "000000000000100100";    --   A45 = 0.0044 * 8.192

        when "01101" =>                       -- Termino A55*X5

          auxi01  <= prodp01;                 -- Desocupa el multiplicador (A45*X5)
          prodb01 <= "000001111111110101";    --   A55 = 0.9987 * 8.192

        when "01110" =>                       -- Termino A65*X5

          s_4     <= s_4 + auxi01;            -- Suma A44*X4 + A45*X5
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (A55*X5)
          prodb01 <= "000000000110011011";    --   A65 = 0.0502 * 8.192

        when "01111" =>                       -- Termino A56*X6

          s_5     <= s_5 + auxi02;            -- Suma A54*X4 + A55*X5
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (A65*X5)
          proda01 <= x6(30 downto 13);
          prodb01 <= "111111111001100101";    --   A56 = -0.0502 * 8.192

        when "10000" =>                       -- Termino A66*X6

          s_6     <= s_6 + auxi01;            -- Suma A64*X4 + A65*X5
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (A56*X6)
          prodb01 <= "000001111111110101";    --   A66 = 0.9987 * 8.192

        when "10001" =>                       -- Termino B11*Vo_star_0

          s_5    <= s_5 + auxi02;             -- Suma A54*X4 + A55*X5 + A56*X6
          auxi01 <= prodp01;                  -- Desocupa el multiplicador (A66*X6)
          if (vo_star_0(8) = '0') then
            proda01 <= vo_star_0 & "00";
          else
            proda01 <= vo_star_0 & "00";
          end if;
          prodb01 <= "000000000000100100";    --   B11 = 0.0044 * 8.192

        when "10010" =>                       -- Termino B42*Vo_star_1

          s_6    <= s_6 + auxi01;             -- Suma A64*X4 + A65*X5 + A66*X6
          auxi02 <= prodp01;                  -- Desocupa el multiplicador (B11*Vo_star_0)
          if (vo_star_1(8) = '0') then
            proda01 <= vo_star_1 & "00";
          else
            proda01 <= vo_star_1 & "00";
          end if;

        when "10011" =>                       -- Termino B13*Io_0

          s_1     <= s_1 + auxi02;            -- Suma A11*X1 + A12*X2 + B11*Vo_star_0
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (B42*Vo_star_1)
          proda01 <= io_0(30 downto 13);
          prodb01 <= "000000101100001101";    --   B13 = 0.3453 * 8.192

        when "10100" =>                       -- Termino B23*Io_0

          s_4     <= s_4 + auxi01;            -- Suma A44*X4 + A45*X5 + B42*Vo_star_1
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (B13*Io_0)
          prodb01 <= "010010101111001110";    --   B23 = 9.3689 * 8.192

        when "10101" =>                       -- Termino B33*Io_0

          x1      <= s_1 + auxi02;            -- Suma A11*X1 + A12*X2 + B11*Vo_star_0 + B13*Io_0
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (B23*Io_0)
          prodb01 <= "111000101001010110";    --   B33 = -3.6770 * 8.192
          y1      <= x1;                      -- Y_o(k) = C_o * X_o(k)

        when "10110" =>                       -- Termino B44*Io_1

          x2      <= s_2 + auxi01;            -- Suma A21*X1 + A22*X2 + A23*X3 + B23*Io_0
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (B33*Io_0)
          proda01 <= io_1(30 downto 13);
          prodb01 <= "000000101100001101";    --   B44 = 0.3453 * 8.192

        when "10111" =>                       -- Termino B54*Io_1

          x3      <= s_3 + auxi02;            -- Suma A31*X1 + A32*X2 + A33*X3 + B33*Io_0
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (B44*Io_1)
          prodb01 <= "010010101111001110";    --   B54 = 9.3689 * 8.192
          y3      <= x2;                      -- Y_o(k) = C_o * X_o(k)

        when "11000" =>                       -- Termino B64*Io_1

          x4      <= s_4 + auxi01;            -- Suma A44*X4 + A45*X5 + B42*Vo_star_1 + B44*Io_1
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (B54*Io_1)
          prodb01 <= "111000101001010110";    --   B64 = -3.6770 * 8.192
          y2      <= x4;                      -- Y_o(k) = C_o * X_o(k)

        --
        -- A partir de aqui comienza el calculo de V_og(k)
        --      Se superpone un poco con el cambio de estado X(k) --> X(k+1)
        --
        when "11001" =>                       -- Termino Ko11*Y1

          x5      <= s_5 + auxi02;            -- Suma A54*X4 + A55*X5 + A56*X6 + B54*Io_1
          auxi01  <= prodp01;                 -- Desocupa el multiplicador (B64*Io_1)
          proda01 <= y1(30 downto 13);
          prodb01 <= "110011111100100110";    --   -Ko11 = -6.0265 * 8.192

        when "11010" =>                       -- Termino Ko22*Y2

          x6      <= s_6 + auxi01;            -- Suma A64*X4 + A65*X5 + A66*X6 + B64*Io_1
          auxi02  <= prodp01;                 -- Desocupa el multiplicador (-Ko11*Y1)
          proda01 <= y2(30 downto 13);
          y4      <= x5;

        --
        -- Con la disponibilidad de Y cuntinua el calculo de Vog
        --
        when "11011" =>

          vog_0_long <= vog_0_long + auxi02;  -- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1 - Ko11*Y1
          auxi01     <= prodp01;              -- Desocupa el multiplicador (Ko22*Y2)

        when "11100" =>

          vog_1_long <= vog_1_long + auxi01;  -- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1 - Ko22*Y2

        when "11101" =>

          vog_0_long <= vog_0_long - y3;      -- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1 - Y3 - Ko11*Y1

        when "11110" =>

          vog_1_long <= vog_1_long - y4;      -- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1 - Y4 - Ko22*Y2

        when others =>

          null;                               --

      end case;

    end if;

  end process;

  process (clock) is
  begin

    if (clock = '1' and clock'event) then       -- Flanco de ascendente
      --
      -- Primer tramo del calculo de V_og(k)
      --    Es posible porque el termino (Gv + Ko) * i_r (k) no necesita ni de X ni de Y
      --
      --  Resolucion de i_r
      --                                 1
      --    .--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
      --    |17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
      --    ´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
      --               |                  | |        |
      --               '------------------------' '---------'
      --                        |            |
      --                        |            '---> Decimales (4 bits)
      --                        '---------> Resolucion de medicion (9 bits)
      case stat is

        when "00000" =>                         -- Termino (GV+Ko)11*Ir_0

          if (ir_0(8) = '0') then               -- Carga extension numerica de Ir_0
            proda02 <= "00000" & ir_0 & "0000";
          else
            proda02 <= "11111" & ir_0 & "0000";
          end if;
          prodb02 <= "010101011110111100";      --   (GV+Ko)11 = 10.7417 * 8.192

        when "00001" =>                         -- Termino (GV+Ko)21*Ir_0

          vog_0_long <= prodp02;                -- Almacena (GV+Ko)11*Ir_0
          prodb02    <= "010110101010010100";   --   (GV+Ko)21 = 11.3306 * 8.192

        when "00010" =>                         -- Termino (GV+Ko)12*Ir_1

          vog_1_long <= prodp02;                -- Almacena (GV+Ko)21*Ir_0
          if (ir_1(8) = '0') then               -- Carga extension numerica de Ir_1
            proda02 <= "00000" & ir_1 & "0000";
          else
            proda02 <= "11111" & ir_1 & "0000";
          end if;
          prodb02 <= "101010100001000011";      --   (GV+Ko)12 = -11.3306 * 8.192

        when "00011" =>                         -- Termino (GV+Ko)22*Ir_1

          auxi03  <= prodp02;                   -- Desocupa el multiplicador ((GV+Ko)12*Ir_1)
          prodb02 <= "010101011110111100";      --   (GV+Ko)22 = 10.7417 * 8.192

        --
        --  A partir de aqui comienza la transformacion de trifasica a bifasica de la corriente de salida,
        --  a la vez que completa el calculo del primer tramo de V_og(k) vaciando el pipeline (2 terminos).
        --
        when "00100" =>                         -- Termino KaBI11*Io_u

          auxi04     <= prodp02;                -- Desocupa el multiplicador ((GV+Ko)22*Ir_1)
          vog_0_long <= vog_0_long + auxi03;    -- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1
          if (io_u(8) = '0') then               -- Carga extension numerica de Io_u
            proda02 <= "00000" & io_u & "0000";
          else
            proda02 <= "11111" & io_u & "0000";
          end if;
          prodb02 <= "000001010101010101";      --   KaBI11 = 0.6667 * 8.192

        when "00101" =>                         -- Termino KaBI12*Io_v

          io_0       <= prodp02;                -- Almacena KaBI11*Io_u
          vog_1_long <= vog_1_long + auxi04;    -- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1
          if (io_v(8) = '0') then               -- Carga extension numerica de Io_v
            proda02 <= "00000" & io_v & "0000";
          else
            proda02 <= "11111" & io_v & "0000";
          end if;
          prodb02 <= "111111010101010101";      --   KaBI12 = -0.3333 * 8.192

        when "00110" =>                         -- Termino KaBI22*Io_v

          auxi03  <= prodp02;                   -- Desocupa el multiplicador (KaBI12*Io_v)
          prodb02 <= "000001001001111001";      --   KaBI22 = 0.5774 * 8.192

        when "00111" =>                         -- Termino KaBI13*Io_w

          io_1 <= prodp02;                      -- Almacena KaBI22*Io_v
          io_0 <= io_0 + auxi03;                -- Suma KaBI11*Io_u + KaBI12*Io_v
          if (io_w(8) = '0') then               -- Carga extension numerica de Io_w
            proda02 <= "00000" & io_w & "0000";
          else
            proda02 <= "11111" & io_w & "0000";
          end if;
          prodb02 <= "111111010101010101";      --   KaBI12 = -0.3333 * 8.192

        when "01000" =>                         -- Termino KaBI23*Io_w

          auxi03  <= prodp02;                   -- Desocupa el multiplicador (KaBI13*Io_w)
          prodb02 <= "111110110110000110";      --   KaBI22 = -0.5774 * 8.192

        when "01001" =>                         -- Termino

          io_0   <= io_0 + auxi03;              -- Suma KaBI11*Io_u + KaBI12*Io_v + KaBI13*Io_w
          auxi04 <= prodp02;                    -- Desocupa el multiplicador (KaBI23*Io_w)

        when "01010" =>                         -- Termino

          io_1 <= io_1 + auxi04;                -- Suma KaBI22*Io_v + KaBI23*Io_w

        when others =>

          null;                                 --

      end case;

    end if;

  end process;

  multi01 : component mult18x18
    port map (
      p => prodp01,
      a => proda01,
      b => prodb01
    );

  multi02 : component mult18x18
    port map (
      p => prodp02,
      a => proda02,
      b => prodb02
    );

end architecture behavioral;

