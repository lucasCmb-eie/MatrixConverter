----------------------------------------------------------------------------------
-- Create Date:    00:05:30 20/02/2019
-- Design Name:  Sergio Geninatti
-- Project Name:
-- Revision 1.00
-- Additional Comments:
----------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------

--! Este bloque recibe principalmente valores de angulos alpha y beta
--! y genera un vector de conmutaciones correspondientes a lo deseado

library ieee;
  use ieee.std_logic_1164.all;
  -- use IEEE.STD_LOGIC_ARITH.ALL;
  use ieee.std_logic_unsigned.all;

library unisim;
  use unisim.vcomponents.all;

entity modulador is
  port (
    i_reloj  : in    std_logic;                     --! Entrada de 200 MHz
    i_enable : in    std_logic;
    i_al_o   : in    std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
    i_be_i   : in    std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
    i_q_i    : in    std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
    i_phi_i  : in    std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

    o_fin_ciclo    : out   std_logic;                    --! Indica Fin de Ciclo
    o_inicio_ciclo : out   std_logic;                    --! Indica Inicio de Ciclo
    o_fin_calc_ts  : out   std_logic;                    --! Indica que el calculo de las salidas finalizo (Ts)
    o_direcciones  : out   std_logic_vector(17 downto 0) --! Salida con las señales de las conmutaciones
  );
end entity modulador;

architecture behavioral of modulador is

  signal clock100 : std_logic; --! Sin uso

  signal op1_suma,   op2_suma  : std_logic_vector(10 downto 0) := "00000000000"; --! Señales para realizar una suma
  signal resul_suma, acumul    : std_logic_vector(10 downto 0);
  signal mod_profp             : std_logic_vector(35 downto 0);
  signal mod_profa,  mod_profb : std_logic_vector(17 downto 0) := "000000000000000000";
  signal pro_profp             : std_logic_vector(35 downto 0);
  signal pro_profa,  pro_profb : std_logic_vector(17 downto 0) := "000000000000000000";
  signal procos00              : std_logic_vector(17 downto 0) := "000000000000000000";
  signal procos01              : std_logic_vector(17 downto 0) := "000000000000000000";
  signal procos02              : std_logic_vector(17 downto 0) := "000000000000000000";
  signal procos03              : std_logic_vector(17 downto 0) := "000000000000000000";
  signal contador_pwm          : std_logic_vector(9 downto 0)  := "0000001000";
  signal ciclo_cnt             : std_logic_vector(10 downto 0) := "00001000000"; --! Sin uso
  signal ciclo_end             : std_logic                     := '0';           --! Sin Uso - Afecta a auxi00
  signal ciclo_ini             : std_logic                     := '0';           --! Sin Uso - Afecta a auxi01
  signal calculo_end           : std_logic                     := '0';           --! Afecta a auxi02
  signal hi_bits               : std_logic                     := '0';

  signal sw_puntero    : std_logic_vector(4 downto 0) := "00000";
  signal switch_matrix : std_logic_vector(8 downto 0) := "000000000";
  signal seq0          : std_logic_vector(3 downto 0) := "0000";
  signal ddabs01       : std_logic_vector(3 downto 0) := "0000";
  signal ddabs02       : std_logic_vector(3 downto 0) := "0000";
  signal ddabs03       : std_logic_vector(3 downto 0) := "0000";
  signal ddabs04       : std_logic_vector(3 downto 0) := "0000";

  signal swseq01             : std_logic_vector(8 downto 0) := "001001001";
  signal swseq02,    swseq03 : std_logic_vector(8 downto 0) := "001001001";
  signal swseq04             : std_logic_vector(8 downto 0) := "010010010";
  signal swseq05,    swseq06 : std_logic_vector(8 downto 0) := "100100100";
  signal swseq07             : std_logic_vector(8 downto 0) := "100100100";
  signal swseq08,    swseq09 : std_logic_vector(8 downto 0) := "100100100";
  signal swseq10             : std_logic_vector(8 downto 0) := "010010010";
  signal swseq11,    swseq12 : std_logic_vector(8 downto 0) := "001001001";
  signal swseq13             : std_logic_vector(8 downto 0) := "001001001";
  signal sw_sel              : std_logic_vector(8 downto 0);

  signal dela01             : std_logic_vector(9 downto 0) := "0000000000";
  signal dela02,     dela03 : std_logic_vector(9 downto 0) := "0000000000";
  signal dela04             : std_logic_vector(9 downto 0) := "0000000000";
  signal dela05,     dela06 : std_logic_vector(9 downto 0) := "0000000000";
  signal dela07             : std_logic_vector(9 downto 0) := "0000000000";
  signal dela08,     dela09 : std_logic_vector(9 downto 0) := "0000000000";
  signal dela10             : std_logic_vector(9 downto 0) := "0000000000";
  signal dela11,     dela12 : std_logic_vector(9 downto 0) := "0000000000";
  signal dela13             : std_logic_vector(9 downto 0) := "0000000000";
  signal dela_sel           : std_logic_vector(9 downto 0);

  signal vector_ptr : std_logic_vector(3 downto 0) := "0000";
  signal salida_sw  : std_logic_vector(8 downto 0) := "100100100";
  signal pwm_new    : std_logic                    := '0';

  signal ram_dir  : std_logic_vector(10 downto 0) := "00000000000";
  signal ram_data : std_logic_vector(8 downto 0);

  signal estado : std_logic_vector(10 downto 0) := "11111110000";
  signal trig   : std_logic;
  signal n_norm : std_logic_vector(2 downto 0);
  --
  -- Las señales que expresan angulos tienen una resolucion de 12 bits para 2 PI
  --  PI / 3 =  "001010101011"
  --
  -- signal al_o : STD_LOGIC_VECTOR (10 downto 0) := "00100011110";
  -- signal be_i : STD_LOGIC_VECTOR (10 downto 0) := "00000101101";
  signal ki,         kv     : std_logic_vector(2 downto 0) := "000";
  signal ki_sel,     kv_sel : std_logic_vector(1 downto 0) := "00";
  signal kvi_sel            : std_logic_vector(3 downto 0);
  signal ksum               : std_logic_vector(2 downto 0);

  signal al_ot,      be_it : std_logic_vector(10 downto 0) := "00000000000";
  -- signal phi_i : STD_LOGIC_VECTOR (10 downto 0) := "00000000000";
  signal cos00                 : std_logic_vector(8 downto 0) := "000000000";
  signal cos01                 : std_logic_vector(8 downto 0) := "000000000";
  signal cos02                 : std_logic_vector(8 downto 0) := "000000000";
  signal cos03                 : std_logic_vector(8 downto 0) := "000000000";
  signal aux_div,    cos_phi   : std_logic_vector(8 downto 0) := "000000000";
  signal q                     : std_logic_vector(8 downto 0) := "001000000";  -- q es positivo < 1 ==> q(8) = '0' ==> q(7) = 1
  signal res_div               : std_logic_vector(9 downto 0) := "0000000000";
  signal q0                    : std_logic_vector(9 downto 0) := "0000000000";
  signal q1                    : std_logic_vector(9 downto 0) := "0000000000"; -- res_div(9) tiene el peso de 1 = 2^0
  signal a                     : std_logic_vector(9 downto 0) := "0000000000";
  signal d                     : std_logic_vector(9 downto 0) := "0000000000";
  signal z                     : std_logic_vector(9 downto 0) := "0000000000";
  signal a0,         a1        : std_logic_vector(9 downto 0) := "0000000000";
  signal signo_phi,  lavel_div : std_logic;
  signal amp_parcial           : std_logic_vector(17 downto 0);

  component red_sector is
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
  end component red_sector;

  component mem_ram_2048x9 is
    port (
      clka  : in    std_logic;
      wea   : in    std_logic_vector(0 downto 0);
      addra : in    std_logic_vector(15 downto 0);
      dina  : in    std_logic_vector(255 downto 0);
      douta : out   std_logic_vector(7 downto 0)
    );
  end component mem_ram_2048x9;

begin

  o_direcciones(17 downto 9) <= "000000000";
  o_direcciones(8 downto 0)  <= salida_sw;
  -- Se podria reemplazar con DIRECCIONES <= "000000000" & Salida_SW

  o_fin_ciclo    <= ciclo_end;
  o_inicio_ciclo <= ciclo_ini;
  o_fin_calc_ts  <= calculo_end;

  ------------------------------------------------------------------------------------
  --
  -- Control de maquina de estados de calculo de matriz de conmutacion.
  --
  process (i_reloj, i_enable) is
  begin
    if(i_enable = '0') then
      estado <= "11111110000";
    elsif (rising_edge(i_reloj)) then    -- Flanco de ascendente
      estado <= estado + "00000000001";
    end if;

  end process;

  --
  -- Control de PWM.
  --
  process (i_reloj) is
  begin
    
    if (rising_edge(i_reloj)) then                            -- Flanco de ascendente
      if (calculo_end = '1') then
        vector_ptr   <= "0000";                               -- Reinicia ciclo Ts
        contador_pwm <= "0000000111";
        pwm_new      <= '0';
      else

        case contador_pwm is

          when "0000001000" =>                                -- Primer intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (dela_sel(9 downto 3) = "0000000") then        -- Si el tiempo actual es mayor que un minimo lo pone
              if (vector_ptr = "1110") then
                pwm_new <= '1';
              else
                vector_ptr <= vector_ptr + "0001";
              end if;
            else
              pwm_new <= '1';
            end if;

          when "0000000111" =>                                -- Segundo intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (pwm_new = '0') then
              if (dela_sel(9 downto 3) = "0000000") then      -- Si el tiempo actual es mayor que un minimo lo pone
                if (vector_ptr = "1110") then
                  pwm_new <= '1';
                else
                  vector_ptr <= vector_ptr + "0001";
                end if;
              else
                pwm_new <= '1';
              end if;
            end if;

          when "0000000110" =>                                -- Tercer intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (pwm_new = '0') then
              if (dela_sel(9 downto 3) = "0000000") then      -- Si el tiempo actual es mayor que un minimo lo pone
                if (vector_ptr = "1110") then
                  pwm_new <= '1';
                else
                  vector_ptr <= vector_ptr + "0001";
                end if;
              else
                pwm_new <= '1';
              end if;
            end if;

          when "0000000101" =>                                -- Cuarto intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (pwm_new = '0') then
              if (dela_sel(9 downto 3) = "0000000") then      -- Si el tiempo actual es mayor que un minimo lo pone
                if (vector_ptr = "1110") then
                  pwm_new <= '1';
                else
                  vector_ptr <= vector_ptr + "0001";
                end if;
              else
                pwm_new <= '1';
              end if;
            end if;

          when "0000000100" =>                                -- Quinto intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (pwm_new = '0') then
              if (dela_sel(9 downto 3) = "0000000") then      -- Si el tiempo actual es mayor que un minimo lo pone
                if (vector_ptr = "1110") then
                  pwm_new <= '1';
                else
                  vector_ptr <= vector_ptr + "0001";
                end if;
              else
                pwm_new <= '1';
              end if;
            end if;

          when "0000000011" =>                                -- Quinto intento de lectura de parametros PWM

            contador_pwm <= contador_pwm + "1111111111";
            if (pwm_new = '0') then
              if (dela_sel(9 downto 3) = "0000000") then      -- Si el tiempo actual es mayor que un minimo lo pone
                if (vector_ptr = "1110") then
                  pwm_new <= '1';
                else
                  vector_ptr <= vector_ptr + "0001";
                end if;
              else
                pwm_new <= '1';
              end if;
            end if;

          when "0000000010" =>                                -- Quinto intento de lectura de parametros PWM

            salida_sw    <= sw_sel;
            contador_pwm <= dela_sel;
            pwm_new      <= '0';
            if (vector_ptr /= "1110") then
              vector_ptr <= vector_ptr + "0001";
            end if;

          when others =>                                      --

            contador_pwm <= contador_pwm + "1111111111";

        end case;

      end if;
    end if;

  end process;

  --
  -- Sumador concurrente
  --
  resul_suma <= op1_suma + op2_suma;
  -- resul_resta <= op1_resta - op2_resta;

  mod_profp <= mod_profa * mod_profb; --  MUL3
  hi_bits   <= '0' when mod_profp (35 downto 25) = "00000000000" else
               '1';

  --
  -- Calculo de tiempos de aplicacion de vectores no nulos
  --
  --    Prepara las diferencias de "al_ot" y "be_it" con PI/3 para calcular los cosenos.
  --
  process (i_reloj) is
  begin

    if (rising_edge(i_reloj)) then                        -- Flanco de descendente

      case estado is

        when "00000000000" =>                             --

          ram_dir <= i_phi_i;

        when "00000000111" =>                             --

          op1_suma <= "11010101011";                      -- Carga -PI / 3 en op1_suma
          op2_suma <= al_ot;

        when "00000001000" =>                             --

          ram_dir  <= resul_suma;                         -- Carga direccion al_ot-PI/3
          op2_suma <= be_it;

        when "00000001001" =>                             --

          ram_dir  <= resul_suma;                         -- Carga direccion be_it-PI/3
          op1_suma <= "00101010101";                      -- Carga PI / 3 en op1_suma

        when "00000001010" =>                             --

          cos00    <= ram_data;                           -- Lee de la memoria cos(al_ot-PI/3)
          ram_dir  <= resul_suma;                         -- Carga direccion be_it+PI/3
          op2_suma <= al_ot;

        when "00000001011" =>                             --

          cos01   <= ram_data;                            -- Lee de la memoria cos(be_it-PI/3)
          ram_dir <= resul_suma;                          -- Carga direccion al_ot+PI/3

        when "00000001100" =>                             --

          cos02 <= ram_data;                              -- Lee de la memoria cos(be_it+PI/3)

        when "00000001101" =>                             --

          cos03 <= ram_data;                              -- Lee de la memoria cos(al_ot+PI/3)

        when "00000010111" =>                             --

          calculo_end <= '1';                             -- Fuerza el cambio de Ts y evita que se mezclen los vectores
          acumul      <= mod_profp (26 downto 16);        -- Suma el primer TON

        when "00000011000" =>                             --

          acumul <= acumul + mod_profp (26 downto 16);    -- Suma el segundo TON

        when "00000011001" =>                             --

          acumul <= acumul + mod_profp (26 downto 16);    -- Suma el tercer TON

        when "00000011010" =>                             --

          acumul <= acumul + mod_profp (26 downto 16);    -- Suma el cuarto TON

        when "00000011011" =>                             --

          acumul <= "01000000000" - acumul;

        when "00000011100" =>                             --

          if (acumul(10 downto 9) = "00") then
            dela01 <= "00" & acumul(8 downto 1);          -- Toma el tiempo de los vectores nulos
            dela13 <= "00" & acumul(8 downto 1);          -- Toma el tiempo de los vectores nulos
            dela04 <= '0' & acumul(8 downto 0);           -- Toma el tiempo de los vectores nulos
            dela07 <= '0' & acumul(8 downto 0);           -- Toma el tiempo de los vectores nulos
            dela10 <= '0' & acumul(8 downto 0);           -- Toma el tiempo de los vectores nulos
          else
            dela01 <= "0000000000";                       -- Toma el tiempo de los vectores nulos
            dela13 <= "0000000000";                       -- Toma el tiempo de los vectores nulos
            dela04 <= "0000000000";                       -- Toma el tiempo de los vectores nulos
            dela07 <= "0000000000";                       -- Toma el tiempo de los vectores nulos
            dela10 <= "0000000000";                       -- Toma el tiempo de los vectores nulos
          end if;

        when "00000011101" =>                             --

          calculo_end <= '0';                             --  Habilita inicio de Ts

        when others =>

          null;                                           --

      end case;

    end if;

  end process;

  --
  --    Hace el producto de los cosenos.
  --
  process (i_reloj) is
  begin

    if (rising_edge(i_reloj)) then                                                                                               -- Flanco de descendente

      case estado is

        when "00000001100" =>                                                                                                    -- Aqui ya esta disponible cos(al_ot-PI/3) y cos(be_it-PI/3)

          mod_profa <= cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00;
          mod_profb <= cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01;

        when "00000001101" =>                                                                                                    -- Ya esta disponible cos(be_it+PI/3)

          procos00  <= mod_profp (17 downto 0);
          mod_profb <= cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02;

        when "00000001110" =>                                                                                                    -- Ya esta disponible cos(al_ot+PI/3)

          procos01  <= mod_profp (17 downto 0);
          mod_profa <= cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03;

        when "00000001111" =>                                                                                                    -- Ya esta disponible cos(al_ot+PI/3)

          procos03  <= mod_profp (17 downto 0);
          mod_profb <= cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01;

        when "00000010000" =>                                                                                                    -- Ya esta disponible cos(al_ot+PI/3)

          procos02 <= mod_profp (17 downto 0);

        when "00000010101" =>                                                                                                    -- Division ajuste del resultado

          mod_profa <= amp_parcial;
          mod_profb <= "000000001001001111";                                                                                     -- 2/sqrt(3) = 1,15470053837  bit(9) tiene el peso de 1 = 2^0

        when "00000010110" =>                                                                                                    -- a partir de aqui se aplica a los tiempos de ON

          mod_profa <= mod_profp (26 downto 9);
          mod_profb <= procos00;

        when "00000010111" =>                                                                                                    --

          if (hi_bits = '0') then
            dela02 <= mod_profp (24 downto 15);                                                                                  -- Toma el primer TON
            dela12 <= mod_profp (24 downto 15);                                                                                  -- Espeja el primer TON
          else
            dela02 <= "1111111111";                                                                                              -- Toma el primer TON
            dela12 <= "1111111111";                                                                                              -- Espeja el primer TON
          end if;
          mod_profb <= procos01;

        when "00000011000" =>                                                                                                    --

          if (hi_bits = '0') then
            dela03 <= mod_profp (24 downto 15);                                                                                  -- Toma el segundo TON
            dela11 <= mod_profp (24 downto 15);                                                                                  -- Espeja el segundo TON
          else
            dela03 <= "1111111111";                                                                                              -- Toma el segundo TON
            dela11 <= "1111111111";                                                                                              -- Espeja el segundo TON
          end if;
          mod_profb <= procos02;

        when "00000011001" =>                                                                                                    --

          if (hi_bits = '0') then
            dela05 <= mod_profp (24 downto 15);                                                                                  -- Toma el tercer TON
            dela09 <= mod_profp (24 downto 15);                                                                                  -- Espeja el tercer TON
          else
            dela05 <= "1111111111";                                                                                              -- Toma el tercer TON
            dela09 <= "1111111111";                                                                                              -- Espeja el tercer TON
          end if;
          mod_profb <= procos03;

        when "00000011010" =>                                                                                                    --

          if (hi_bits = '0') then
            dela06 <= mod_profp (24 downto 15);                                                                                  -- Toma el cuarto TON
            dela08 <= mod_profp (24 downto 15);                                                                                  -- Espeja el cuarto TON
          else
            dela06 <= "1111111111";                                                                                              -- Toma el cuarto TON
            dela08 <= "1111111111";                                                                                              -- Espeja el cuarto TON
          end if;

        when others =>

          null;                                                                                                                  --

      end case;

    end if;

  end process;

  --
  -- Calculo del cociente Q/ASB(COS(PHI_I))
  --
  -- q <= i_q_i;

  aux_div <= i_q_i - cos_phi;

  z <= a(8 downto 0) & '0' - d;

  a0 <= a(8 downto 0) & '0';
  q0 <= res_div(8 downto 0) & '0';
  a1 <= z;
  q1 <= res_div(8 downto 0) & '1';

  amp_parcial <= "00000000" & res_div when n_norm = "000" else
                 "0000000" & res_div & '0' when n_norm = "001" else
                 "000000" & res_div & "00" when n_norm = "010" else
                 "00000" & res_div & "000" when n_norm = "011" else
                 "0000" & res_div & "0000" when n_norm = "100" else
                 "000" & res_div & "00000" when n_norm = "101" else
                 "00" & res_div & "000000" when n_norm = "110" else
                 "0" & res_div & "0000000" when n_norm = "111" else
                 "000000000000000000";

  process (i_reloj) is
  begin

    if (rising_edge(i_reloj)) then                      -- Flanco de descendente

      case estado is

        when "00000000010" =>                           -- En el algoritmo de division que usaremos el resultado debe ser < 1 (q < cos_ohi)

          n_norm <= "000";
          if (ram_data(8) = '0') then
            cos_phi   <= ram_data;                      -- Saca valor absoluto y separa el signo del coseno
            signo_phi <= '0';
          else
            cos_phi   <= "000000000" - ram_data;
            signo_phi <= '1';
          end if;

        when "00000000011" =>                           -- testeo division 1

          if (aux_div(8) = '0') then
            n_norm <= "001";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000000100" =>                           -- testeo division 2

          if (aux_div(8) = '0') then
            n_norm <= "010";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000000101" =>                           -- testeo division 3

          if (aux_div(8) = '0') then
            n_norm <= "011";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000000110" =>                           -- testeo division 4

          if (aux_div(8) = '0') then
            n_norm <= "100";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000000111" =>                           -- testeo division 5

          if (aux_div(8) = '0') then
            n_norm <= "101";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000001000" =>                           -- testeo division 6

          if (aux_div(8) = '0') then
            n_norm <= "110";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000001001" =>                           -- testeo division 7

          if (aux_div(8) = '0') then
            n_norm <= "111";
            if (q(7) = '1') then
              cos_phi <= cos_phi (7 downto 0) & '0';    -- Multiplica por dos el denominador
            else
              q <= '0' & q(8 downto 1);                 -- Divide por dos el numerador
            end if;
          end if;

        when "00000001010" =>                           -- inicio division

          a       <= '0' & q;
          d       <= '0' & cos_phi;
          res_div <= "0000000000";

        when "00000001011" =>                           -- Division paso 1

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000001100" =>                           -- Division paso 2

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000001101" =>                           -- Division paso 3

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000001110" =>                           -- Division paso 4

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000001111" =>                           -- Division paso 5

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000010000" =>                           -- Division paso 6

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000010001" =>                           -- Division paso 7

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000010010" =>                           -- Division paso 8

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000010011" =>                           -- Division paso 9

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when "00000010100" =>                           -- Division paso 10

          if (z(9) = '1') then
            a       <= a0;
            res_div <= q0;
          else
            a       <= a1;
            res_div <= q1;
          end if;

        when others =>

          null;                                         --

      end case;

    end if;

  end process;

  --
  --  Instancia del Bloque de RAM que contienen funcion coseno, entrega valores enteros de 9 bits
  --      Rango: 255 (1 - BIN = "011111111") y -255 (-1 "100000001")
  --

  --! Bloque de RAM que contienen funcion coseno, entrega valores enteros de 9 bits Rango: 255 (1 - BIN = "011111111") y -255 (-1 "100000001")
  modu_2048x9 : component ramb16_s9
    generic map (
      init       => X"000",
      srval      => X"000",
      write_mode => "WRITE_FIRST",
      -- The following INIT_xx declarations specify the initial contents of the RAM
      -- Address 0 to 511
      init_00 => X"FEFEFEFEFEFEFEFEFEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      init_01 => X"FAFAFBFBFBFBFBFBFBFCFCFCFCFCFCFCFCFCFDFDFDFDFDFDFDFDFDFDFEFEFEFE",
      init_02 => X"F4F4F5F5F5F5F6F6F6F6F6F7F7F7F7F7F8F8F8F8F8F8F9F9F9F9F9F9FAFAFAFA",
      init_03 => X"ECECECEDEDEDEEEEEEEEEFEFEFF0F0F0F0F1F1F1F1F2F2F2F2F3F3F3F3F4F4F4",
      init_04 => X"E1E2E2E2E3E3E3E4E4E4E5E5E6E6E6E7E7E7E8E8E8E8E9E9E9EAEAEAEBEBEBEC",
      init_05 => X"D4D5D5D6D6D7D7D7D8D8D9D9DADADADBDBDCDCDCDDDDDDDEDEDFDFDFE0E0E1E1",
      init_06 => X"C6C6C7C7C8C8C9C9CACACACBCBCCCCCDCDCECECFCFD0D0D0D1D1D2D2D3D3D4D4",
      init_07 => X"B5B5B6B7B7B8B8B9B9BABABBBBBCBCBDBDBEBFBFC0C0C1C1C2C2C3C3C4C4C5C5",
      init_08 => X"A2A3A4A4A5A5A6A7A7A8A8A9AAAAABABACACADAEAEAFAFB0B0B1B2B2B3B3B4B4",
      init_09 => X"8E8F909091929293939495959697979899999A9A9B9C9C9D9E9E9F9FA0A1A1A2",
      init_0a => X"797A7A7B7C7C7D7E7E7F8080818282838484858686878888898A8A8B8C8C8D8E",
      init_0b => X"62636464656667676869696A6B6C6C6D6E6E6F70717172737374757576777878",
      init_0c => X"4B4C4C4D4E4F4F505151525354545556575758595A5A5B5C5D5D5E5F5F606162",
      init_0d => X"333334353636373839393A3B3C3C3D3E3F3F404142434344454646474849494A",
      init_0e => X"1A1B1B1C1D1E1E1F202122222324252526272829292A2B2C2C2D2E2F2F303132",
      init_0f => X"0102020304050506070809090A0B0C0D0D0E0F10101112131414151617171819",
      -- Address 512 to 1023
      init_10 => X"E8E9E9EAEBECECEDEEEFF0F0F1F2F3F3F4F5F6F7F7F8F9FAFBFBFCFDFEFEFF00",
      init_11 => X"CFD0D1D1D2D3D4D4D5D6D7D7D8D9DADBDBDCDDDEDEDFE0E1E2E2E3E4E5E5E6E7",
      init_12 => X"B7B7B8B9BABABBBCBDBDBEBFC0C1C1C2C3C4C4C5C6C7C7C8C9CACACBCCCDCDCE",
      init_13 => X"9FA0A1A1A2A3A3A4A5A6A6A7A8A9A9AAABACACADAEAFAFB0B1B1B2B3B4B4B5B6",
      init_14 => X"88898A8B8B8C8D8D8E8F8F90919292939494959697979899999A9B9C9C9D9E9E",
      init_15 => X"737474757676777878797A7A7B7C7C7D7E7E7F80808182828384848586868788",
      init_16 => X"5F5F606161626263646465666667676869696A6B6B6C6D6D6E6E6F7070717272",
      init_17 => X"4C4D4D4E4E4F5050515152525354545555565657585859595A5B5B5C5C5D5E5E",
      init_18 => X"3B3C3C3D3D3E3E3F3F404041414243434444454546464747484849494A4B4B4C",
      init_19 => X"2C2D2D2E2E2F2F303030313132323333343435353636363737383839393A3A3B",
      init_1a => X"1F202021212122222323232424242525262626272728282929292A2A2B2B2C2C",
      init_1b => X"151515161616171717181818181919191A1A1A1B1B1C1C1C1D1D1D1E1E1E1F1F",
      init_1c => X"0C0C0D0D0D0D0E0E0E0E0F0F0F0F101010101111111212121213131314141414",
      init_1d => X"06060607070707070708080808080809090909090A0A0A0A0A0B0B0B0B0C0C0C",
      init_1e => X"0202020303030303030303030304040404040404040405050505050505060606",
      init_1f => X"0101010101010101010101010101010101010101020202020202020202020202",
      -- Address 1024 to 1535
      init_20 => X"0202020202020202020202010101010101010101010101010101010101010101",
      init_21 => X"0606050505050505050404040404040404040303030303030303030302020202",
      init_22 => X"0C0C0B0B0B0B0A0A0A0A0A090909090908080808080807070707070706060606",
      init_23 => X"14141413131312121212111111101010100F0F0F0F0E0E0E0E0D0D0D0D0C0C0C",
      init_24 => X"1F1E1E1E1D1D1D1C1C1C1B1B1A1A1A1919191818181817171716161615151514",
      init_25 => X"2C2B2B2A2A292929282827272626262525242424232323222221212120201F1F",
      init_26 => X"3A3A393938383737363636353534343333323231313030302F2F2E2E2D2D2C2C",
      init_27 => X"4B4B4A494948484747464645454444434342414140403F3F3E3E3D3D3C3C3B3B",
      init_28 => X"5E5D5C5C5B5B5A5959585857565655555454535252515150504F4E4E4D4D4C4C",
      init_29 => X"727170706F6E6E6D6D6C6B6B6A696968676766666564646362626161605F5F5E",
      init_2a => X"8786868584848382828180807F7E7E7D7C7C7B7A7A7978787776767574747372",
      init_2b => X"9E9D9C9C9B9A99999897979695949493929291908F8F8E8D8D8C8B8B8A898888",
      init_2c => X"B5B4B4B3B2B1B1B0AFAFAEADACACABAAA9A9A8A7A6A6A5A4A3A3A2A1A1A09F9E",
      init_2d => X"CDCDCCCBCACAC9C8C7C7C6C5C4C4C3C2C1C1C0BFBEBDBDBCBBBABAB9B8B7B7B6",
      init_2e => X"E6E5E5E4E3E2E2E1E0DFDEDEDDDCDBDBDAD9D8D7D7D6D5D4D4D3D2D1D1D0CFCE",
      init_2f => X"FFFEFEFDFCFBFBFAF9F8F7F7F6F5F4F3F3F2F1F0F0EFEEEDECECEBEAE9E9E8E7",
      -- Address 1536 to 2047
      init_30 => X"1817171615141413121110100F0E0D0D0C0B0A09090807060505040302020100",
      init_31 => X"31302F2F2E2D2C2C2B2A292928272625252423222221201F1E1E1D1C1B1B1A19",
      init_32 => X"494948474646454443434241403F3F3E3D3C3C3B3A3939383736363534333332",
      init_33 => X"61605F5F5E5D5D5C5B5A5A595857575655545453525151504F4F4E4D4C4C4B4A",
      init_34 => X"7877767575747373727171706F6E6E6D6C6C6B6A696968676766656464636262",
      init_35 => X"8D8C8C8B8A8A8988888786868584848382828180807F7E7E7D7C7C7B7A7A7978",
      init_36 => X"A1A1A09F9F9E9E9D9C9C9B9A9A999998979796959594939392929190908F8E8E",
      init_37 => X"B4B3B3B2B2B1B0B0AFAFAEAEADACACABABAAAAA9A8A8A7A7A6A5A5A4A4A3A2A2",
      init_38 => X"C5C4C4C3C3C2C2C1C1C0C0BFBFBEBDBDBCBCBBBBBABAB9B9B8B8B7B7B6B5B5B4",
      init_39 => X"D4D3D3D2D2D1D1D0D0D0CFCFCECECDCDCCCCCBCBCACACAC9C9C8C8C7C7C6C6C5",
      init_3a => X"E1E0E0DFDFDFDEDEDDDDDDDCDCDCDBDBDADADAD9D9D8D8D7D7D7D6D6D5D5D4D4",
      init_3b => X"EBEBEBEAEAEAE9E9E9E8E8E8E8E7E7E7E6E6E6E5E5E4E4E4E3E3E3E2E2E2E1E1",
      init_3c => X"F4F4F3F3F3F3F2F2F2F2F1F1F1F1F0F0F0F0EFEFEFEEEEEEEEEDEDEDECECECEC",
      init_3d => X"FAFAFAF9F9F9F9F9F9F8F8F8F8F8F8F7F7F7F7F7F6F6F6F6F6F5F5F5F5F4F4F4",
      init_3e => X"FEFEFEFDFDFDFDFDFDFDFDFDFDFCFCFCFCFCFCFCFCFCFBFBFBFBFBFBFBFAFAFA",
      init_3f => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFEFEFEFEFEFEFEFEFEFE",
      -- The next set of INITP_xx are for the parity bits
      -- Address 0 to 511
      initp_00 => X"0000000000000000000000000000000000000000000000000000000000000000",
      initp_01 => X"0000000000000000000000000000000000000000000000000000000000000000",
      -- Address 512 to 1023
      initp_02 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE",
      initp_03 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      -- Address 1024 to 1535
      initp_04 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      initp_05 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      -- Address 1536 to 2047
      initp_06 => X"0000000000000000000000000000000000000000000000000000000000000000",
      initp_07 => X"0000000000000000000000000000000000000000000000000000000000000000"
    )
    port map (
      do   => ram_data(7 downto 0),
      dop  => ram_data(8 downto 8),
      addr => ram_dir,
      clk  => i_reloj,
      di   => "00000000",
      dip  => "0",
      en   => '1',
      ssr  => '0',
      we   => '0'
    );

  red_sector_inst00 : component red_sector
    port map (
      al_o   => i_al_o,
      be_i   => i_be_i,
      estado => estado,
      clock  => i_reloj,
      ki     => ki,
      kv     => kv,
      al_ot  => al_ot,
      be_it  => be_it
    );

  --
  --    Calcula secuencia de vectores. signo_phi
  --      En estado = "00110" ya estan disponibles Kv y Ki
  --
  process (i_reloj) is
  begin

    if (rising_edge(i_reloj)) then                                                                                                 -- Flanco de descendente

      case estado is

        when "00000000110" =>                                                                                                      -- Aqui ya esta disponible Kv y Ki

          seq0 <= (not(ksum(0) xor signo_phi)) & (ksum(0) xor signo_phi) & (ksum(0) xor signo_phi) & (not(ksum(0) xor signo_phi));

        when "00000000111" =>                                                                                                      --

          sw_puntero <= ddabs01 & seq0(3);                                                                                         -- coloca puntero de seq1

        when "00000001000" =>                                                                                                      --

          swseq02    <= switch_matrix;                                                                                             -- Lee seq1
          swseq12    <= switch_matrix;                                                                                             -- Lee seq1
          sw_puntero <= ddabs02 & seq0(2);                                                                                         -- coloca puntero de seq2

        when "00000001001" =>                                                                                                      --

          swseq03    <= switch_matrix;                                                                                             -- Lee seq2
          swseq11    <= switch_matrix;                                                                                             -- Lee seq2
          sw_puntero <= ddabs03 & seq0(1);                                                                                         -- coloca puntero de seq3

        when "00000001010" =>                                                                                                      --

          swseq05    <= switch_matrix;                                                                                             -- Lee seq3
          swseq09    <= switch_matrix;                                                                                             -- Lee seq3
          sw_puntero <= ddabs04 & seq0(0);                                                                                         -- coloca puntero de seq4

        when "00000001011" =>                                                                                                      --

          swseq06 <= switch_matrix;                                                                                                -- Lee seq4
          swseq08 <= switch_matrix;                                                                                                -- Lee seq4

        when others =>

          null;                                                                                                                    --

      end case;

    end if;

  end process;

  ksum <= kv + ki;

  kv_sel <= "01" when kv = "001" else
            "10" when kv = "010" else
            "11" when kv = "011" else
            "01" when kv = "100" else
            "10" when kv = "101" else
            "11" when kv = "110" else
            "00";

  ki_sel <= "01" when ki = "001" else
            "10" when ki = "010" else
            "11" when ki = "011" else
            "01" when ki = "100" else
            "10" when ki = "101" else
            "11" when ki = "110" else
            "00";

  kvi_sel <= kv_sel & ki_sel;

  ddabs01 <= "1001" when kvi_sel = "0101" else
             "1000" when kvi_sel = "0110" else
             "0111" when kvi_sel = "0111" else
             "0110" when kvi_sel = "1001" else
             "0101" when kvi_sel = "1010" else
             "0100" when kvi_sel = "1011" else
             "0011" when kvi_sel = "1101" else
             "0010" when kvi_sel = "1110" else
             "0001" when kvi_sel = "1111" else
             "0000"; -- Nunca debería darse

  ddabs02 <= "0111" when kvi_sel = "0101" else
             "1001" when kvi_sel = "0110" else
             "1000" when kvi_sel = "0111" else
             "0100" when kvi_sel = "1001" else
             "0110" when kvi_sel = "1010" else
             "0101" when kvi_sel = "1011" else
             "0001" when kvi_sel = "1101" else
             "0011" when kvi_sel = "1110" else
             "0010" when kvi_sel = "1111" else
             "0000"; -- Nunca debería darse

  ddabs03 <= "0011" when kvi_sel = "0101" else
             "0010" when kvi_sel = "0110" else
             "0001" when kvi_sel = "0111" else
             "1001" when kvi_sel = "1001" else
             "1000" when kvi_sel = "1010" else
             "0111" when kvi_sel = "1011" else
             "0110" when kvi_sel = "1101" else
             "0101" when kvi_sel = "1110" else
             "0100" when kvi_sel = "1111" else
             "0000"; -- Nunca debería darse

  ddabs04 <= "0001" when kvi_sel = "0101" else
             "0011" when kvi_sel = "0110" else
             "0010" when kvi_sel = "0111" else
             "0111" when kvi_sel = "1001" else
             "1001" when kvi_sel = "1010" else
             "1000" when kvi_sel = "1011" else
             "0100" when kvi_sel = "1101" else
             "0110" when kvi_sel = "1110" else
             "0101" when kvi_sel = "1111" else
             "0000"; -- Nunca debería darse

  switch_matrix <= "100100100" when sw_puntero = "00000" else -- 19  no debería darse
                   "100100100" when sw_puntero = "00001" else -- 19  no debería darse
                   "100010010" when sw_puntero = "00010" else -- +1
                   "010100100" when sw_puntero = "00011" else -- -1
                   "010001001" when sw_puntero = "00100" else -- +2
                   "001010010" when sw_puntero = "00101" else -- -2
                   "001100100" when sw_puntero = "00110" else -- +3
                   "100001001" when sw_puntero = "00111" else -- -3
                   "010100010" when sw_puntero = "01000" else -- +4
                   "100010100" when sw_puntero = "01001" else -- -4
                   "001010001" when sw_puntero = "01010" else -- +5
                   "010001010" when sw_puntero = "01011" else -- -5
                   "100001100" when sw_puntero = "01100" else -- +6
                   "001100001" when sw_puntero = "01101" else -- -6
                   "010010100" when sw_puntero = "01110" else -- +7
                   "100100010" when sw_puntero = "01111" else -- -7
                   "001001010" when sw_puntero = "10000" else -- +8
                   "010010001" when sw_puntero = "10001" else -- -8
                   "100100001" when sw_puntero = "10010" else -- +9
                   "001001100" when sw_puntero = "10011" else -- -9
                   "100100100" when sw_puntero = "10100" else -- 19
                   "010010010" when sw_puntero = "10101" else -- 20
                   "001001001" when sw_puntero = "10110" else -- 21
                   "100100100";                               -- igual al vector nulo 19 (nunca deberia darse)

  sw_sel <= swseq01 when vector_ptr = "0000" else
            swseq02 when vector_ptr = "0001" else
            swseq03 when vector_ptr = "0010" else
            swseq04 when vector_ptr = "0011" else
            swseq05 when vector_ptr = "0100" else
            swseq06 when vector_ptr = "0101" else
            swseq07 when vector_ptr = "0110" else
            swseq08 when vector_ptr = "0111" else
            swseq09 when vector_ptr = "1000" else
            swseq10 when vector_ptr = "1001" else
            swseq11 when vector_ptr = "1010" else
            swseq12 when vector_ptr = "1011" else
            swseq13 when vector_ptr = "1100" else
            "100100100"; -- Aplica vector nulo, pero no debería darse

  dela_sel <= dela01 when vector_ptr = "0000" else
              dela02 when vector_ptr = "0001" else
              dela03 when vector_ptr = "0010" else
              dela04 when vector_ptr = "0011" else
              dela05 when vector_ptr = "0100" else
              dela06 when vector_ptr = "0101" else
              dela07 when vector_ptr = "0110" else
              dela08 when vector_ptr = "0111" else
              dela09 when vector_ptr = "1000" else
              dela10 when vector_ptr = "1001" else
              dela11 when vector_ptr = "1010" else
              dela12 when vector_ptr = "1011" else
              dela13 when vector_ptr = "1100" else
              "0010000000"; -- Pone un tiempo cualquiera para vector nulo que no debería darse,
-- el reenganche viene con calculo_END = '1'

end architecture behavioral;
