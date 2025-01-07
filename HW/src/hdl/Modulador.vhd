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
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;

entity Modulador is
   port (
--
--	Pines exteriores de la FPGA
--
			PUL_DOWN	: in		std_logic; 
			PUL_UP		: in		std_logic; 
			REG_DOWN	: in		std_logic; 
			REG_UP		: in		std_logic; 
			RELOJ		: in		std_logic; 
			SELECTOR	: in		std_logic_vector (7 downto 0);
			AL_O        : in        std_logic_vector(10 downto 0);
			BE_I        : in        std_logic_vector  (10 downto 0);
			Q_I         : in        std_logic_vector (8 downto 0);
			PHI_I       : in        std_logic_vector (10 downto 0);
			
			RELOJ00		: out		std_logic; 
			AUXI00		: out		std_logic; 
			AUXI01		: out		std_logic; 
			AUXI02		: out		std_logic; 
			AUXI03		: out		std_logic; 
			AUXI04		: out		std_logic;
			DIGITO      : out		std_logic_vector (3 downto 0); 
			SEGMENTO    : out		std_logic_vector (7 downto 0); 
			LED         : out		std_logic_vector (7 downto 0); 
			CE1			: out		std_logic; 
			CE2			: out		std_logic; 
			LB1			: out		std_logic; 
			LB2         : out		std_logic; 
			UB1         : out		std_logic; 
			UB2         : out		std_logic; 
			OE          : out		std_logic; 
			WE			: out		std_logic; 
			DIRECCIONES : out		std_logic_vector (17 downto 0); 
			
			DATOS		: inout	    std_logic_vector (31 downto 0));
end Modulador;

architecture Behavioral of Modulador is
-- Senales de reloj (sincronizacin)
signal clock50 : std_logic;
-- Senales clockv : std_logic;
signal clock100_sb, clock100 : std_logic;
signal clock200_sb, clock200 : std_logic;

signal op1_suma, op2_suma : STD_LOGIC_VECTOR (10 downto 0) := "00000000000";
signal resul_suma, acumul : STD_LOGIC_VECTOR (10 downto 0);
signal Mod_profP : STD_LOGIC_VECTOR (35 downto 0);
signal Mod_profA, Mod_profB : STD_LOGIC_VECTOR (17 downto 0) := "000000000000000000";
signal Pro_profP : STD_LOGIC_VECTOR (35 downto 0);
signal Pro_profA, Pro_profB : STD_LOGIC_VECTOR (17 downto 0) := "000000000000000000";
signal Procos00, Procos01, Procos02, Procos03 : STD_LOGIC_VECTOR (17 downto 0) := "000000000000000000";
signal contador_PWM : STD_LOGIC_VECTOR (9 downto 0) := "0000001000";
signal ciclo_CNT : STD_LOGIC_VECTOR (10 downto 0) := "00001000000";
signal ciclo_END, ciclo_INI, calculo_END : std_logic := '0';
signal hi_bits : std_logic := '0';


signal sw_puntero : STD_LOGIC_VECTOR (4 downto 0) := "00000";
signal switch_matrix : STD_LOGIC_VECTOR (8 downto 0) :="000000000";
signal Seq0  : STD_LOGIC_VECTOR (3 downto 0) := "0000";
signal DDabs01, DDabs02, DDabs03, DDabs04 : STD_LOGIC_VECTOR (3 downto 0) := "0000";

signal Swseq01 : STD_LOGIC_VECTOR (8 downto 0) :="001001001";
signal Swseq02, Swseq03 : STD_LOGIC_VECTOR (8 downto 0) :="001001001";
signal Swseq04 : STD_LOGIC_VECTOR (8 downto 0) :="010010010";
signal Swseq05, Swseq06 : STD_LOGIC_VECTOR (8 downto 0) :="100100100";
signal Swseq07 : STD_LOGIC_VECTOR (8 downto 0) :="100100100";
signal Swseq08, Swseq09 : STD_LOGIC_VECTOR (8 downto 0) :="100100100";
signal Swseq10 : STD_LOGIC_VECTOR (8 downto 0) :="010010010";
signal Swseq11, Swseq12 : STD_LOGIC_VECTOR (8 downto 0) :="001001001";
signal Swseq13 : STD_LOGIC_VECTOR (8 downto 0) :="001001001";
signal Sw_sel : STD_LOGIC_VECTOR (8 downto 0);

signal Dela01 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela02, Dela03 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela04 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela05, Dela06 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela07 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela08, Dela09 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela10 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela11, Dela12 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela13 : STD_LOGIC_VECTOR (9 downto 0) := "0000000000";
signal Dela_sel : STD_LOGIC_VECTOR (9 downto 0);

signal vector_PTR : STD_LOGIC_VECTOR (3 downto 0) := "0000";
signal Salida_SW : STD_LOGIC_VECTOR (8 downto 0) :="100100100";
signal PWM_new : std_logic := '0';

signal RAM_DIR : std_logic_vector (10 downto 0) := "00000000000";
signal RAM_DATA : std_logic_vector (8 downto 0);

signal estado : std_logic_vector (10 downto 0) := "11111110000";
signal trig : std_logic;
signal n_norm : std_logic_vector (2 downto 0);
--
-- Las señales que expresan angulos tienen una resolucion de 12 bits para 2 PI
--	PI / 3 =  "001010101011"
--
--signal al_o : STD_LOGIC_VECTOR (10 downto 0) := "00100011110";
--signal be_i : STD_LOGIC_VECTOR (10 downto 0) := "00000101101";
signal Ki, Kv : STD_LOGIC_VECTOR (2 downto 0) := "000";
signal Ki_sel, Kv_sel : STD_LOGIC_VECTOR (1 downto 0) := "00";
signal Kvi_sel : STD_LOGIC_VECTOR (3 downto 0);
signal Ksum : STD_LOGIC_VECTOR (2 downto 0);

signal al_ot, be_it : STD_LOGIC_VECTOR (10 downto 0) := "00000000000";
--signal phi_i : STD_LOGIC_VECTOR (10 downto 0) := "00000000000";
signal cos00, cos01, cos02, cos03 : STD_LOGIC_VECTOR (8 downto 0) :="000000000";
signal aux_div, cos_phi : std_logic_vector (8 downto 0) :="000000000";
signal q : std_logic_vector (8 downto 0) :="001000000";		-- q es positivo < 1 ==> q(8) = '0' ==> q(7) = 1
signal res_div, q0, q1 : std_logic_vector (9 downto 0) := "0000000000";		-- res_div(9) tiene el peso de 1 = 2^0
signal a, d, z : std_logic_vector (9 downto 0) := "0000000000";
signal a0, a1 : std_logic_vector (9 downto 0) := "0000000000";
signal signo_phi, lavel_div : std_logic;
signal amp_parcial : std_logic_vector (17 downto 0);

component red_sector is
    Port ( al_o : in  STD_LOGIC_VECTOR (10 downto 0);
           be_i : in  STD_LOGIC_VECTOR (10 downto 0);
			  estado : in std_logic_vector (10 downto 0);
           clock : in  STD_LOGIC;
           Ki : out  STD_LOGIC_VECTOR (2 downto 0);
           Kv : out  STD_LOGIC_VECTOR (2 downto 0);
           al_ot : out  STD_LOGIC_VECTOR (10 downto 0);
           be_it : out  STD_LOGIC_VECTOR (10 downto 0));
end component;

COMPONENT MEM_RAM_2048x9
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(255 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) 
  );
END COMPONENT;

component clk_wiz_0
port
 (-- Clock in ports
  -- Clock out ports
  CLOCK_100          : out    std_logic;
  CLOCK_200          : out    std_logic;
  -- Status and control signals
  reset             : in     std_logic;
  locked            : out    std_logic;
  RELOJ           : in     std_logic
 );
end component;

begin

--
-- Definiciones para la interface de memoria externa
--
SEGMENTO <= "11111111";
DIGITO <= "1111";
LED <= "00000000";
WE <= '1';
OE <= '1';

DIRECCIONES(17 downto 9) <= "000000000";
DIRECCIONES(8 downto 0) <= Salida_SW;
DATOS	<=	"ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";


CE1 <= '1';
CE2 <= '1';
LB1 <= '0';
LB2 <= '0';
UB1 <= '0';
UB2 <= '0';
AUXI00 <= ciclo_END;
AUXI01 <= ciclo_INI;
AUXI02 <= calculo_END;
AUXI03 <= '0';
AUXI04 <= '0';

DATOS	<=	"ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";

RELOJ00 <= clock200;
------------------------------------------------------------------------------------
IBUF_Clk50 : IBUF
generic map (
   IOSTANDARD => "DEFAULT")
port map (
   O => clock50,		-- Buffer output
   I => RELOJ			-- Buffer input (connect directly to top-level port)
);
--
-- Buffer de reloj internos
-- 
BUFG_Clk200 : BUFG
port map (
   O => clock200,
   I => clock100_sb
);

BUFG_Clk100 : BUFG
port map (
   O => clock100,
   I => clock100_sb
);

--
-- Instancia de PLL, funciona como base de tiempo general.
--
   PLL_RELOJ : clk_wiz_0
   port map ( 
  -- Clock out ports  
   CLOCK_100 => clock100_sb,
   CLOCK_200 => clock200_sb,
  -- Status and control signals                
   reset => '0',
   locked => open,
   -- Clock in ports
   RELOJ => clock50
 );
--
-- Control de maquina de estados de calculo de matriz de conmutacion.
--
process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de ascendente
		estado <= estado + "00000000001";
end if;
end process;
--
-- Control de PWM.
--
process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de ascendente
	if calculo_END = '1' then
		vector_PTR <= "0000";		-- Reinicia ciclo Ts
		contador_PWM <= "0000000111";
		PWM_new <= '0';
	else
		case contador_PWM is
			when "0000001000" =>					-- Primer intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
					if vector_PTR = "1110" then
						PWM_new <= '1';
					else
						vector_PTR <= vector_PTR + "0001";
					end if;
				else
					PWM_new <= '1';
				end if;
				
			when "0000000111" =>					-- Segundo intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if PWM_new = '0' then
					if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
						if vector_PTR = "1110" then
							PWM_new <= '1';
						else
							vector_PTR <= vector_PTR + "0001";
						end if;
					else
						PWM_new <= '1';
					end if;
				end if;
				
			when "0000000110" =>					-- Tercer intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if PWM_new = '0' then
					if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
						if vector_PTR = "1110" then
							PWM_new <= '1';
						else
							vector_PTR <= vector_PTR + "0001";
						end if;
					else
						PWM_new <= '1';
					end if;
				end if;

			when "0000000101" =>					-- Cuarto intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if PWM_new = '0' then
					if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
						if vector_PTR = "1110" then
							PWM_new <= '1';
						else
							vector_PTR <= vector_PTR + "0001";
						end if;
					else
						PWM_new <= '1';
					end if;
				end if;

			when "0000000100" =>					-- Quinto intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if PWM_new = '0' then
					if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
						if vector_PTR = "1110" then
							PWM_new <= '1';
						else
							vector_PTR <= vector_PTR + "0001";
						end if;
					else
						PWM_new <= '1';
					end if;
				end if;

			when "0000000011" =>					-- Quinto intento de lectura de parametros PWM
				contador_PWM <= contador_PWM + "1111111111";
				if PWM_new = '0' then
					if Dela_sel(9 downto 3) = "0000000" then			-- Si el tiempo actual es mayor que un minimo lo pone
						if vector_PTR = "1110" then
							PWM_new <= '1';
						else
							vector_PTR <= vector_PTR + "0001";
						end if;
					else
						PWM_new <= '1';
					end if;
				end if;

			when "0000000010" =>					-- Quinto intento de lectura de parametros PWM
				Salida_SW <= Sw_sel;
				contador_PWM <= Dela_sel;
				PWM_new <= '0';
				if vector_PTR /= "1110" then
					vector_PTR <= vector_PTR + "0001";
				end if;

			when others =>		--
				contador_PWM <= contador_PWM + "1111111111";

		end case;
	end if;
end if;
end process;
--
-- Sumador concurrente
--
resul_suma <= op1_suma + op2_suma;
-- resul_resta <= op1_resta - op2_resta;

Mod_profP <= Mod_profA * Mod_profB;		--	MUL3
hi_bits <= '0' when Mod_profP (35 downto 25) = "00000000000" else '1';

--
-- Calculo de tiempos de aplicacion de vectores no nulos
--
--		Prepara las diferencias de "al_ot" y "be_it" con PI/3 para calcular los cosenos.
--
process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de descendente
	case estado is
		when "00000000000" =>		-- 
			RAM_DIR<= phi_i;

		when "00000000111" =>		-- 
			op1_suma <= "11010101011";		-- Carga -PI / 3 en op1_suma     
			op2_suma <= al_ot;

		when "00000001000" =>		-- 
			RAM_DIR<= resul_suma;				-- Carga direccion al_ot-PI/3
			op2_suma <= be_it;

		when "00000001001" =>		-- 
			RAM_DIR<= resul_suma;				-- Carga direccion be_it-PI/3
			op1_suma <= "00101010101";		-- Carga PI / 3 en op1_suma     

		when "00000001010" =>		-- 
			cos00 <= RAM_DATA;				-- Lee de la memoria cos(al_ot-PI/3)
			RAM_DIR<= resul_suma;				-- Carga direccion be_it+PI/3
			op2_suma <= al_ot;

		when "00000001011" =>		-- 
			cos01 <= RAM_DATA;				-- Lee de la memoria cos(be_it-PI/3)
			RAM_DIR<= resul_suma;				-- Carga direccion al_ot+PI/3

		when "00000001100" =>		-- 
			cos02 <= RAM_DATA;				-- Lee de la memoria cos(be_it+PI/3)

		when "00000001101" =>		-- 
			cos03 <= RAM_DATA;				-- Lee de la memoria cos(al_ot+PI/3)

		when "00000010111" =>		-- 
			calculo_END <= '1';		-- Fuerza el cambio de Ts y evita que se mezclen los vectores
			acumul <=  Mod_profP (26 downto 16);				-- Suma el primer TON

		when "00000011000" =>		-- 
			acumul <=  acumul + Mod_profP (26 downto 16);	-- Suma el segundo TON

		when "00000011001" =>		-- 
			acumul <=  acumul + Mod_profP (26 downto 16);	-- Suma el tercer TON

		when "00000011010" =>		-- 
			acumul <=  acumul + Mod_profP (26 downto 16);	-- Suma el cuarto TON

		when "00000011011" =>		-- 
			acumul <=  "01000000000" - acumul;

		when "00000011100" =>		--
			if acumul(10 downto 9) = "00" then
				Dela01 <= "00" & acumul(8 downto 1);			-- Toma el tiempo de los vectores nulos 
				Dela13 <= "00" & acumul(8 downto 1);			-- Toma el tiempo de los vectores nulos 
				Dela04 <= '0' & acumul(8 downto 0);				-- Toma el tiempo de los vectores nulos 
				Dela07 <= '0' & acumul(8 downto 0);				-- Toma el tiempo de los vectores nulos 
				Dela10 <= '0' & acumul(8 downto 0);				-- Toma el tiempo de los vectores nulos
			else
				Dela01 <= "0000000000";								-- Toma el tiempo de los vectores nulos 
				Dela13 <= "0000000000";								-- Toma el tiempo de los vectores nulos
				Dela04 <= "0000000000";								-- Toma el tiempo de los vectores nulos
				Dela07 <= "0000000000";								-- Toma el tiempo de los vectores nulos
				Dela10 <= "0000000000";								-- Toma el tiempo de los vectores nulos
			end if;

		when "00000011101" =>		--  
			calculo_END <= '0';		--  Habilita inicio de Ts

		when others =>	null;	-- 

	end case;
end if;
end process;
--
--		Hace el producto de los cosenos.
--
process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de descendente
	case estado is
		when "00000001100" =>		-- Aqui ya esta disponible cos(al_ot-PI/3) y cos(be_it-PI/3)
			Mod_profA <= cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00(8) & cos00;
			Mod_profB <= cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01;

		when "00000001101" =>		-- Ya esta disponible cos(be_it+PI/3)
			Procos00 <= Mod_profP (17 downto 0);
			Mod_profB <= cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02(8) & cos02;

		when "00000001110" =>		-- Ya esta disponible cos(al_ot+PI/3)
			Procos01 <= Mod_profP (17 downto 0);
			Mod_profA <= cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03(8) & cos03;

		when "00000001111" =>		-- Ya esta disponible cos(al_ot+PI/3)
			Procos03 <= Mod_profP (17 downto 0);
			Mod_profB <= cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01(8) & cos01;

		when "00000010000" =>		-- Ya esta disponible cos(al_ot+PI/3)
			Procos02 <= Mod_profP (17 downto 0);

		when "00000010101" =>		-- Division ajuste del resultado
			Mod_profA <= amp_parcial;
			Mod_profB <= "000000001001001111";		-- 2/sqrt(3) = 1,15470053837  bit(9) tiene el peso de 1 = 2^0

		when "00000010110" =>		-- a partir de aqui se aplica a los tiempos de ON
			Mod_profA <= Mod_profP (26 downto 9);
			Mod_profB <= Procos00;

		when "00000010111" =>		--
			if hi_bits = '0' then
				Dela02 <= Mod_profP (24 downto 15);		-- Toma el primer TON 
				Dela12 <= Mod_profP (24 downto 15);		-- Espeja el primer TON
			else
				Dela02 <= "1111111111";						-- Toma el primer TON 
				Dela12 <= "1111111111";						-- Espeja el primer TON
			end if;
			Mod_profB <= Procos01;

		when "00000011000" =>		-- 
			if hi_bits = '0' then
				Dela03 <= Mod_profP (24 downto 15);			-- Toma el segundo TON 
				Dela11 <= Mod_profP (24 downto 15);			-- Espeja el segundo TON 
			else
				Dela03 <= "1111111111";						-- Toma el segundo TON 
				Dela11 <= "1111111111";						-- Espeja el segundo TON
			end if;
			Mod_profB <= Procos02;

		when "00000011001" =>		-- 
			if hi_bits = '0' then
				Dela05 <= Mod_profP (24 downto 15);			-- Toma el tercer TON 
				Dela09 <= Mod_profP (24 downto 15);			-- Espeja el tercer TON 
			else
				Dela05 <= "1111111111";						-- Toma el tercer TON 
				Dela09 <= "1111111111";						-- Espeja el tercer TON
			end if;
			Mod_profB <= Procos03;

		when "00000011010" =>		-- 
			if hi_bits = '0' then
				Dela06 <= Mod_profP (24 downto 15);			-- Toma el cuarto TON 
				Dela08 <= Mod_profP (24 downto 15);			-- Espeja el cuarto TON 
			else
				Dela06 <= "1111111111";						-- Toma el cuarto TON 
				Dela08 <= "1111111111";						-- Espeja el cuarto TON
			end if;

		when others =>	null;	-- 

	end case;
end if;
end process;
--
-- Calculo del cociente Q/ASB(COS(PHI_I))
--
q <= Q_I;

aux_div <= q - cos_phi;

z <= a(8 downto 0) & '0' - d;

a0 <= a(8 downto 0) & '0';
q0 <= res_div(8 downto 0) & '0';
a1 <= z;
q1 <= res_div(8 downto 0) & '1';

amp_parcial <= "00000000" & res_div 	  when n_norm = "000" else
					"0000000" & res_div & '0' when n_norm = "001" else
					"000000" & res_div & "00" when n_norm = "010" else
					"00000" & res_div & "000" when n_norm = "011" else
					"0000" & res_div & "0000" when n_norm = "100" else
					"000" & res_div & "00000" when n_norm = "101" else
					"00" & res_div & "000000" when n_norm = "110" else
					"0" & res_div & "0000000" when n_norm = "111";

process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de descendente
	case estado is
		when "00000000010" =>		-- En el algoritmo de division que usaremos el resultado debe ser < 1 (q < cos_ohi)
			n_norm <= "000";
			if RAM_DATA(8) = '0' then
				cos_phi <= RAM_DATA;				-- Saca valor absoluto y separa el signo del coseno
				signo_phi <= '0';
			else
				cos_phi <= "000000000"-RAM_DATA;
				signo_phi <= '1';
			end if;

		when "00000000011" =>		-- testeo division 1
			if aux_div(8) = '0' then
				n_norm <= "001";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000000100" =>		-- testeo division 2
			if aux_div(8) = '0' then
				n_norm <= "010";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000000101" =>		-- testeo division 3
			if aux_div(8) = '0' then
				n_norm <= "011";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000000110" =>		-- testeo division 4
			if aux_div(8) = '0' then
				n_norm <= "100";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000000111" =>		-- testeo division 5
			if aux_div(8) = '0' then
				n_norm <= "101";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000001000" =>		-- testeo division 6
			if aux_div(8) = '0' then
				n_norm <= "110";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000001001" =>		-- testeo division 7
			if aux_div(8) = '0' then
				n_norm <= "111";
				if q(7) = '1' then
					cos_phi <= cos_phi (7 downto 0) & '0';		-- Multiplica por dos el denominador
				else
					q <= '0' & q(8 downto 1);						-- Divide por dos el numerador
				end if;
			end if;

		when "00000001010" =>		-- inicio division
			a <= '0' & q;
			d <= '0' & cos_phi;
			res_div <= "0000000000";

		when "00000001011" =>		-- Division paso 1
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000001100" =>		-- Division paso 2
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000001101" =>		-- Division paso 3
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000001110" =>		-- Division paso 4
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000001111" =>		-- Division paso 5
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000010000" =>		-- Division paso 6
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000010001" =>		-- Division paso 7
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000010010" =>		-- Division paso 8
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000010011" =>		-- Division paso 9
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when "00000010100" =>		-- Division paso 10
			if z(9) = '1' then
				a <= a0;
				res_div <= q0;
			else
				a <= a1;
				res_div <= q1;
			end if;

		when others =>	null;	-- 

	end case;
end if;
end process;

--
--  Instancia del Bloque de RAM que contienen funcion coseno, entrega valores enteros de 9 bits
--			Rango: 255 (1 - BIN = "011111111") y -255 (-1 "100000001")
--
  
MODU_2048x9: RAMB16_S9
   generic map (
      INIT => X"000", --  Value of output RAM registers at startup
      SRVAL => X"000", --  Output value upon SSR assertion
      WRITE_MODE => "WRITE_FIRST", --  WRITE_FIRST, READ_FIRST or NO_CHANGE
      -- The following INIT_xx declarations specify the initial contents of the RAM
      -- Address 0 to 511
		INIT_00 => X"FEFEFEFEFEFEFEFEFEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
		INIT_01 => X"FAFAFBFBFBFBFBFBFBFCFCFCFCFCFCFCFCFCFDFDFDFDFDFDFDFDFDFDFEFEFEFE",
		INIT_02 => X"F4F4F5F5F5F5F6F6F6F6F6F7F7F7F7F7F8F8F8F8F8F8F9F9F9F9F9F9FAFAFAFA",
		INIT_03 => X"ECECECEDEDEDEEEEEEEEEFEFEFF0F0F0F0F1F1F1F1F2F2F2F2F3F3F3F3F4F4F4",
		INIT_04 => X"E1E2E2E2E3E3E3E4E4E4E5E5E6E6E6E7E7E7E8E8E8E8E9E9E9EAEAEAEBEBEBEC",
		INIT_05 => X"D4D5D5D6D6D7D7D7D8D8D9D9DADADADBDBDCDCDCDDDDDDDEDEDFDFDFE0E0E1E1",
		INIT_06 => X"C6C6C7C7C8C8C9C9CACACACBCBCCCCCDCDCECECFCFD0D0D0D1D1D2D2D3D3D4D4",
		INIT_07 => X"B5B5B6B7B7B8B8B9B9BABABBBBBCBCBDBDBEBFBFC0C0C1C1C2C2C3C3C4C4C5C5",
		INIT_08 => X"A2A3A4A4A5A5A6A7A7A8A8A9AAAAABABACACADAEAEAFAFB0B0B1B2B2B3B3B4B4",
		INIT_09 => X"8E8F909091929293939495959697979899999A9A9B9C9C9D9E9E9F9FA0A1A1A2",
		INIT_0A => X"797A7A7B7C7C7D7E7E7F8080818282838484858686878888898A8A8B8C8C8D8E",
		INIT_0B => X"62636464656667676869696A6B6C6C6D6E6E6F70717172737374757576777878",
		INIT_0C => X"4B4C4C4D4E4F4F505151525354545556575758595A5A5B5C5D5D5E5F5F606162",
		INIT_0D => X"333334353636373839393A3B3C3C3D3E3F3F404142434344454646474849494A",
		INIT_0E => X"1A1B1B1C1D1E1E1F202122222324252526272829292A2B2C2C2D2E2F2F303132",
		INIT_0F => X"0102020304050506070809090A0B0C0D0D0E0F10101112131414151617171819",
      -- Address 512 to 1023
		INIT_10 => X"E8E9E9EAEBECECEDEEEFF0F0F1F2F3F3F4F5F6F7F7F8F9FAFBFBFCFDFEFEFF00",
		INIT_11 => X"CFD0D1D1D2D3D4D4D5D6D7D7D8D9DADBDBDCDDDEDEDFE0E1E2E2E3E4E5E5E6E7",
		INIT_12 => X"B7B7B8B9BABABBBCBDBDBEBFC0C1C1C2C3C4C4C5C6C7C7C8C9CACACBCCCDCDCE",
		INIT_13 => X"9FA0A1A1A2A3A3A4A5A6A6A7A8A9A9AAABACACADAEAFAFB0B1B1B2B3B4B4B5B6",
		INIT_14 => X"88898A8B8B8C8D8D8E8F8F90919292939494959697979899999A9B9C9C9D9E9E",
		INIT_15 => X"737474757676777878797A7A7B7C7C7D7E7E7F80808182828384848586868788",
		INIT_16 => X"5F5F606161626263646465666667676869696A6B6B6C6D6D6E6E6F7070717272",
		INIT_17 => X"4C4D4D4E4E4F5050515152525354545555565657585859595A5B5B5C5C5D5E5E",
		INIT_18 => X"3B3C3C3D3D3E3E3F3F404041414243434444454546464747484849494A4B4B4C",
		INIT_19 => X"2C2D2D2E2E2F2F303030313132323333343435353636363737383839393A3A3B",
		INIT_1A => X"1F202021212122222323232424242525262626272728282929292A2A2B2B2C2C",
		INIT_1B => X"151515161616171717181818181919191A1A1A1B1B1C1C1C1D1D1D1E1E1E1F1F",
		INIT_1C => X"0C0C0D0D0D0D0E0E0E0E0F0F0F0F101010101111111212121213131314141414",
		INIT_1D => X"06060607070707070708080808080809090909090A0A0A0A0A0B0B0B0B0C0C0C",
		INIT_1E => X"0202020303030303030303030304040404040404040405050505050505060606",
		INIT_1F => X"0101010101010101010101010101010101010101020202020202020202020202",
      -- Address 1024 to 1535
		INIT_20 => X"0202020202020202020202010101010101010101010101010101010101010101",
		INIT_21 => X"0606050505050505050404040404040404040303030303030303030302020202",
		INIT_22 => X"0C0C0B0B0B0B0A0A0A0A0A090909090908080808080807070707070706060606",
		INIT_23 => X"14141413131312121212111111101010100F0F0F0F0E0E0E0E0D0D0D0D0C0C0C",
		INIT_24 => X"1F1E1E1E1D1D1D1C1C1C1B1B1A1A1A1919191818181817171716161615151514",
		INIT_25 => X"2C2B2B2A2A292929282827272626262525242424232323222221212120201F1F",
		INIT_26 => X"3A3A393938383737363636353534343333323231313030302F2F2E2E2D2D2C2C",
		INIT_27 => X"4B4B4A494948484747464645454444434342414140403F3F3E3E3D3D3C3C3B3B",
		INIT_28 => X"5E5D5C5C5B5B5A5959585857565655555454535252515150504F4E4E4D4D4C4C",
		INIT_29 => X"727170706F6E6E6D6D6C6B6B6A696968676766666564646362626161605F5F5E",
		INIT_2A => X"8786868584848382828180807F7E7E7D7C7C7B7A7A7978787776767574747372",
		INIT_2B => X"9E9D9C9C9B9A99999897979695949493929291908F8F8E8D8D8C8B8B8A898888",
		INIT_2C => X"B5B4B4B3B2B1B1B0AFAFAEADACACABAAA9A9A8A7A6A6A5A4A3A3A2A1A1A09F9E",
		INIT_2D => X"CDCDCCCBCACAC9C8C7C7C6C5C4C4C3C2C1C1C0BFBEBDBDBCBBBABAB9B8B7B7B6",
		INIT_2E => X"E6E5E5E4E3E2E2E1E0DFDEDEDDDCDBDBDAD9D8D7D7D6D5D4D4D3D2D1D1D0CFCE",
		INIT_2F => X"FFFEFEFDFCFBFBFAF9F8F7F7F6F5F4F3F3F2F1F0F0EFEEEDECECEBEAE9E9E8E7",
      -- Address 1536 to 2047
		INIT_30 => X"1817171615141413121110100F0E0D0D0C0B0A09090807060505040302020100",
		INIT_31 => X"31302F2F2E2D2C2C2B2A292928272625252423222221201F1E1E1D1C1B1B1A19",
		INIT_32 => X"494948474646454443434241403F3F3E3D3C3C3B3A3939383736363534333332",
		INIT_33 => X"61605F5F5E5D5D5C5B5A5A595857575655545453525151504F4F4E4D4C4C4B4A",
		INIT_34 => X"7877767575747373727171706F6E6E6D6C6C6B6A696968676766656464636262",
		INIT_35 => X"8D8C8C8B8A8A8988888786868584848382828180807F7E7E7D7C7C7B7A7A7978",
		INIT_36 => X"A1A1A09F9F9E9E9D9C9C9B9A9A999998979796959594939392929190908F8E8E",
		INIT_37 => X"B4B3B3B2B2B1B0B0AFAFAEAEADACACABABAAAAA9A8A8A7A7A6A5A5A4A4A3A2A2",
		INIT_38 => X"C5C4C4C3C3C2C2C1C1C0C0BFBFBEBDBDBCBCBBBBBABAB9B9B8B8B7B7B6B5B5B4",
		INIT_39 => X"D4D3D3D2D2D1D1D0D0D0CFCFCECECDCDCCCCCBCBCACACAC9C9C8C8C7C7C6C6C5",
		INIT_3A => X"E1E0E0DFDFDFDEDEDDDDDDDCDCDCDBDBDADADAD9D9D8D8D7D7D7D6D6D5D5D4D4",
		INIT_3B => X"EBEBEBEAEAEAE9E9E9E8E8E8E8E7E7E7E6E6E6E5E5E4E4E4E3E3E3E2E2E2E1E1",
		INIT_3C => X"F4F4F3F3F3F3F2F2F2F2F1F1F1F1F0F0F0F0EFEFEFEEEEEEEEEDEDEDECECECEC",
		INIT_3D => X"FAFAFAF9F9F9F9F9F9F8F8F8F8F8F8F7F7F7F7F7F6F6F6F6F6F5F5F5F5F4F4F4",
		INIT_3E => X"FEFEFEFDFDFDFDFDFDFDFDFDFDFCFCFCFCFCFCFCFCFCFBFBFBFBFBFBFBFAFAFA",
		INIT_3F => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFEFEFEFEFEFEFEFEFEFE",
      -- The next set of INITP_xx are for the parity bits
      -- Address 0 to 511
      INITP_00 => X"0000000000000000000000000000000000000000000000000000000000000000",
      INITP_01 => X"0000000000000000000000000000000000000000000000000000000000000000",
      -- Address 512 to 1023
      INITP_02 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE",
      INITP_03 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      -- Address 1024 to 1535
      INITP_04 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      INITP_05 => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      -- Address 1536 to 2047
      INITP_06 => X"0000000000000000000000000000000000000000000000000000000000000000",
      INITP_07 => X"0000000000000000000000000000000000000000000000000000000000000000")
   port map (
      DO => RAM_DATA(7 downto 0),		-- 8-bit Data Output
      DOP => RAM_DATA(8 downto 8),	-- 1-bit parity Output
      ADDR => RAM_DIR,					-- 11-bit Address Input
      CLK => clock200,						-- Clock
      DI => "00000000",						-- 8-bit Data Input
      DIP => "0",								-- 1-bit parity Input
      EN => '1',								-- RAM Enable Input
      SSR => '0',								-- Synchronous Set/Reset Input
      WE => '0'								-- Write Enable Input
   );



red_sector_inst00:
red_sector Port map (
			  al_o => al_o,
           be_i => be_i,
			  estado => estado,
           clock => clock200,
           Ki => Ki,
           Kv => Kv,
           al_ot => al_ot,
           be_it => be_it
			  );

--
--		Calcula secuencia de vectores. signo_phi
--			En estado = "00110" ya estan disponibles Kv y Ki
--
process (clock200)
begin
if (rising_edge(clock200)) then		-- Flanco de descendente
	case estado is
		when "00000000110" =>	-- Aqui ya esta disponible Kv y Ki
			seq0 <= (not(Ksum(0)xor signo_phi))	& (Ksum(0)xor signo_phi) & (Ksum(0)xor signo_phi)  & (not(Ksum(0)xor signo_phi));

		when "00000000111" =>	-- 
			sw_puntero <= DDabs01 & seq0(3); -- coloca puntero de seq1

		when "00000001000" =>	-- 
			Swseq02 <= switch_matrix;			-- Lee seq1
			Swseq12 <= switch_matrix;			-- Lee seq1
			sw_puntero <= DDabs02 & seq0(2); -- coloca puntero de seq2

		when "00000001001" =>	-- 
			Swseq03 <= switch_matrix;			-- Lee seq2
			Swseq11 <= switch_matrix;			-- Lee seq2
			sw_puntero <= DDabs03 & seq0(1); -- coloca puntero de seq3

		when "00000001010" =>	-- 
			Swseq05 <= switch_matrix;			-- Lee seq3
			Swseq09 <= switch_matrix;			-- Lee seq3
			sw_puntero <= DDabs04 & seq0(0); -- coloca puntero de seq4

		when "00000001011" =>	-- 
			Swseq06 <= switch_matrix;			-- Lee seq4
			Swseq08 <= switch_matrix;			-- Lee seq4
		
		when others =>	null;	-- 

	end case;
end if;
end process;

Ksum <= Kv + Ki;

Kv_sel <= "01" when Kv = "001" else
			 "10" when Kv = "010" else
			 "11" when Kv = "011" else
			 "01" when Kv = "100" else
			 "10" when Kv = "101" else
			 "11" when Kv = "110" else
			 "00";

Ki_sel <= "01" when Ki = "001" else
			 "10" when Ki = "010" else
			 "11" when Ki = "011" else
			 "01" when Ki = "100" else
			 "10" when Ki = "101" else
			 "11" when Ki = "110" else
			 "00";

Kvi_sel <= Kv_sel & Ki_sel;

DDabs01 <=	"1001" when Kvi_sel = "0101" else
				"1000" when Kvi_sel = "0110" else
				"0111" when Kvi_sel = "0111" else
				"0110" when Kvi_sel = "1001" else
				"0101" when Kvi_sel = "1010" else
				"0100" when Kvi_sel = "1011" else
				"0011" when Kvi_sel = "1101" else
				"0010" when Kvi_sel = "1110" else
				"0001" when Kvi_sel = "1111" else
				"0000";  -- Nunca debería darse

DDabs02 <=	"0111" when Kvi_sel = "0101" else
				"1001" when Kvi_sel = "0110" else
				"1000" when Kvi_sel = "0111" else
				"0100" when Kvi_sel = "1001" else
				"0110" when Kvi_sel = "1010" else
				"0101" when Kvi_sel = "1011" else
				"0001" when Kvi_sel = "1101" else
				"0011" when Kvi_sel = "1110" else
				"0010" when Kvi_sel = "1111" else
				"0000";  -- Nunca debería darse

DDabs03 <=	"0011" when Kvi_sel = "0101" else
				"0010" when Kvi_sel = "0110" else
				"0001" when Kvi_sel = "0111" else
				"1001" when Kvi_sel = "1001" else
				"1000" when Kvi_sel = "1010" else
				"0111" when Kvi_sel = "1011" else
				"0110" when Kvi_sel = "1101" else
				"0101" when Kvi_sel = "1110" else
				"0100" when Kvi_sel = "1111" else
				"0000";  -- Nunca debería darse

DDabs04 <=	"0001" when Kvi_sel = "0101" else
				"0011" when Kvi_sel = "0110" else
				"0010" when Kvi_sel = "0111" else
				"0111" when Kvi_sel = "1001" else
				"1001" when Kvi_sel = "1010" else
				"1000" when Kvi_sel = "1011" else
				"0100" when Kvi_sel = "1101" else
				"0110" when Kvi_sel = "1110" else
				"0101" when Kvi_sel = "1111" else
				"0000";  -- Nunca debería darse

switch_matrix <=	"100100100" when sw_puntero = "00000" else      -- 19	no debería darse
						"100100100" when sw_puntero = "00001" else      -- 19	no debería darse
						"100010010" when sw_puntero = "00010" else      -- +1
						"010100100" when sw_puntero = "00011" else      -- -1
						"010001001" when sw_puntero = "00100" else      -- +2
						"001010010" when sw_puntero = "00101" else      -- -2
						"001100100" when sw_puntero = "00110" else      -- +3
						"100001001" when sw_puntero = "00111" else      -- -3
						"010100010" when sw_puntero = "01000" else      -- +4
						"100010100" when sw_puntero = "01001" else      -- -4
						"001010001" when sw_puntero = "01010" else      -- +5
						"010001010" when sw_puntero = "01011" else      -- -5
						"100001100" when sw_puntero = "01100" else      -- +6
						"001100001" when sw_puntero = "01101" else      -- -6
						"010010100" when sw_puntero = "01110" else      -- +7
						"100100010" when sw_puntero = "01111" else      -- -7
						"001001010" when sw_puntero = "10000" else      -- +8
						"010010001" when sw_puntero = "10001" else      -- -8
						"100100001" when sw_puntero = "10010" else      -- +9
						"001001100" when sw_puntero = "10011" else      -- -9
						"100100100" when sw_puntero = "10100" else      -- 19
						"010010010" when sw_puntero = "10101" else      -- 20
						"001001001" when sw_puntero = "10110" else      -- 21
						"100100100";		-- igual al vector nulo 19 (nunca deberia darse)

Sw_sel <= 	Swseq01 when vector_PTR = "0000" else
				Swseq02 when vector_PTR = "0001" else
				Swseq03 when vector_PTR = "0010" else
				Swseq04 when vector_PTR = "0011" else
				Swseq05 when vector_PTR = "0100" else
				Swseq06 when vector_PTR = "0101" else
				Swseq07 when vector_PTR = "0110" else
				Swseq08 when vector_PTR = "0111" else
				Swseq09 when vector_PTR = "1000" else
				Swseq10 when vector_PTR = "1001" else
				Swseq11 when vector_PTR = "1010" else
				Swseq12 when vector_PTR = "1011" else
				Swseq13 when vector_PTR = "1100" else
				"100100100";		-- Aplica vector nulo, pero no debería darse

Dela_sel <=	Dela01 when vector_PTR = "0000" else
				Dela02 when vector_PTR = "0001" else
				Dela03 when vector_PTR = "0010" else
				Dela04 when vector_PTR = "0011" else
				Dela05 when vector_PTR = "0100" else
				Dela06 when vector_PTR = "0101" else
				Dela07 when vector_PTR = "0110" else
				Dela08 when vector_PTR = "0111" else
				Dela09 when vector_PTR = "1000" else
				Dela10 when vector_PTR = "1001" else
				Dela11 when vector_PTR = "1010" else
				Dela12 when vector_PTR = "1011" else
				Dela13 when vector_PTR = "1100" else
				"0010000000";		-- Pone un tiempo cualquiera para vector nulo que no debería darse,
										-- el reenganche viene con calculo_END = '1'

end Behavioral;
