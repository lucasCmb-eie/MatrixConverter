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
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;

entity Out_CNTL is
    Port ( CNT_trig : in  STD_LOGIC;
           clock : in  STD_LOGIC;
			  Ir_0 : in  STD_LOGIC_VECTOR (8 downto 0); --Referencia
			  Ir_1 : in  STD_LOGIC_VECTOR (8 downto 0);
			  Io_u : in  STD_LOGIC_VECTOR (8 downto 0);
			  Io_v : in  STD_LOGIC_VECTOR (8 downto 0);
			  Io_w : in  STD_LOGIC_VECTOR (8 downto 0);
           	  Vo_star_0 : inout  STD_LOGIC_VECTOR (15 downto 0);
           	  Vo_star_1 : inout  STD_LOGIC_VECTOR (15 downto 0));
end Out_CNTL;

architecture Behavioral of Out_CNTL is
-- type Iodef is array (1 downto 0) of STD_LOGIC_VECTOR (8 downto 0);

--	Resolucion de Io trifasica
--													 		  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--							 |								  | |			  |
--							 '------------------------' '---------'
--											  |						|
--											  |						'---> Decimales (4 bits)
--											  '---------> Resolucion de medicion (9 bits)
--
--	Resolucion de Vo_star
--															 		  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--		  |														  | |	  |
--		  '--------------------------------------------' '---'
--									  |									|
--									  |									'---> Decimales (2 bits)
--									  '-----------------> Resolucion de medicion (16 bits)
--	Resolucion de X
--													 								  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|35|34|33|32|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--													 		  1
--	Resolucion de Io bifasica
--													 							  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|35|34|33|32|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--													 		  1
signal X1 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";		-- X es la variable de estado del observador
signal X2 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal X3 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal X4 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal X5 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal X6 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";

signal S_1 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";	-- X_ es una variable intermedia para el calculo
signal S_2 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";	--		del nuevo estado
signal S_3 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal S_4 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal S_5 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal S_6 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";

signal Y1 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal Y2 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal Y3 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal Y4 : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";

signal prodP01 : std_logic_vector (35 downto 0);
signal prodA01 : std_logic_vector (17 downto 0);
signal prodB01 : std_logic_vector (17 downto 0);

signal prodP02 : std_logic_vector (35 downto 0);
signal prodA02 : std_logic_vector (17 downto 0);
signal prodB02 : std_logic_vector (17 downto 0);

signal Vog_0_long : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";
signal Vog_1_long : std_logic_vector (35 downto 0) := "000000000000000000000000000000000000";

signal Io_0 : STD_LOGIC_VECTOR (35 downto 0) := "000000000000000000000000000000000000";
signal Io_1 : STD_LOGIC_VECTOR (35 downto 0) := "000000000000000000000000000000000000";

signal SumaProdP01 : std_logic_vector (35 downto 0);
signal Auxi01, Auxi02, Auxi03, Auxi04 : std_logic_vector (35 downto 0);

signal Vog_0, Vog_1 : std_logic_vector (8 downto 0);


signal stat : std_logic_vector (4 downto 0) := "00000";

begin
--
--		Control de maquina de estados
--
process (clock)
begin
if clock = '1' and clock'event then		-- Flanco de ascendente
	if stat = "11000" then
		if CNT_trig = '1' then
			stat <= "00000";
		end if;
	else
		stat <= stat + "00001";
	end if;

end if;
end process;
--
process (clock)
begin
if clock = '1' and clock'event then		-- Flanco de ascendente
--
--		Avance de estado disparado por el TIC de muestreo de la Matriz (41 uS)
--
----------------------------------------------------------------------------------
-- Ao= [			0.6325		0.0044		0				0				0				0
--					-9.3689		0.9987		-0.0502		0				0				0
--             3.6770		0.0502		0.9987		0				0				0
--              0				0				0				0.6325		0.0044		0
--              0				0				0				-9.3689		0.9987		-0.0502
--              0				0				0				3.6770		0.0502		0.9987	]
--
----------------------------------------------------------------------------------
-- Bo= [			0.0044		0				0.3453		0
--					0				0				9.3689		0
--					0				0				-3.6770		0
--					0				0.0044		0				0.3453
--					0				0				0				9.3689
--					0				0				0				-3.6770	]
--
--	V_io = [ 	Vo_star_0	Vo_star_1	Io_0			Io_1	]
--
--
--	Resolucion de las constantes de la matriz (maximo valor entero -> +/- 15,xxxxxx
-- (las constantes se multiplican por 8.192)
--						  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--		 |				  | |												  |
--		 '------------' '------------------------------------'
--					|									|
--					|									'---> Decimales (13 bits)
--					'---------> Resolucion de enteros (5 bits)
--
--	Resolucion de X reducido
--																  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--		 |														  | |		  |
--		 '------------------------------------------' '------'
--										  |							  |
--										  |							  '---> Decimales (3 bits)
--										  '---------> Resolucion de enteros (15 bits)
-----------------------------------------------------------------------------------------
--	Organizacion de calculo de estado: X(k+1) = A * X(K) + B * V_io
--		En el calculo de A * X(K) se acumulan los resultados en un vector de suma temporal
--		llamado S_, para evitar alterar X(K) hasta que ya no se necesite, esto ocurre entre
--		los estados "00000" y "10100".
--		Luego a partir del estado "10101" la acumulacion del producto B * V_io se hace 
--		directamente en X para generar el X(k+1) porque ya no se necesita X(K).
--		En el estado "11010" se completa el calculo de la transicion de estado X(k+1).
-----------------------------------------------------------------------------------------
-- Ajuste de resolucion de los multiplicadores:
--		Los términos de X tienen 36 bits de resolucion y los operandos de multiplicacion
--		tienen 18 bit, para maximisar el rendimiento de los rangos numericos se recorta X
--		desplazando las constantes que multiplican en cada operacion.
--		La ubicacion del punto decimal del resultado de las multiplicaciones debe ser fijo
--		para que puedan acumularse en el producto matricial.
--
--
--
	case stat is
		when "00000" =>				-- Termino A11*X1
			prodA01 <= X1(30 downto 13);
			prodB01 <= "000001010000111101";	-- 	A11 = 0.6325 * 8.192

		when "00001" =>				-- Termino A21*X1
			S_1 <= prodP01;						-- Almacena A11*X1
			prodB01 <= "101101010000110010";	-- 	A21 = -9.3689 * 8.192

		when "00010" =>				-- Termino A31*X1
			S_2 <= prodP01;						-- Almacena A21*X1
			prodB01 <= "000111010110101010";	-- 	A31 = 3.6770 * 8.192

		when "00011" =>				-- Termino A12*X2
			S_3 <= prodP01;						-- Almacena A31*X1
			prodA01 <= X2(30 downto 13);
			prodB01 <= "000000000000100100";	-- 	A12 = 0.0044 * 8.192

		when "00100" =>				-- Termino A22*X2
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A12*X2)
			prodB01 <= "000001111111110101";	-- 	A22 = 0.9987 * 8.192

		when "00101" =>				-- Termino A32*X2
			S_1 <= S_1 + Auxi01;					-- Suma A11*X1 + A12*X2
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (A22*X2)
			prodB01 <= "000000000110011011";	-- 	A32 = 0.0502 * 8.192

		when "00111" =>				-- Termino A23*X3
			S_2 <= S_2 + Auxi02;					-- Suma A21*X1 + A22*X2
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A32*X2)
			prodA01 <= X3(30 downto 13);
			prodB01 <= "111111111001100101";	-- 	A23 = -0.0502 * 8.192

		when "01000" =>				-- Termino A33*X3
			S_3 <= S_3 + Auxi01;					-- Suma A31*X1 + A32*X2
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (A23*X3)
			prodB01 <= "000001111111110101";	-- 	A33 = 0.9987 * 8.192

		when "01001" =>				-- Termino A44*X4
			S_2 <= S_2 + Auxi02;					-- Suma A21*X1 + A22*X2 + A23*X3
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A33*X3)
			prodA01 <= X4(30 downto 13);
			prodB01 <= "000001010000111101";	-- 	A44 = 0.6325 * 8.192

		when "01010" =>				-- Termino A54*X4
			S_3 <= S_3 + Auxi01;					-- Suma A31*X1 + A32*X2 + A33*X3
			S_4 <= prodP01;						-- Almacena A44*X4
			prodB01 <= "101101010000110010";	-- 	A54 = -9.3689 * 8.192

		when "01011" =>				-- Termino A64*X4
			S_5 <= prodP01;						-- Almacena A54*X4
			prodB01 <= "000111010110101010";	-- 	A64 = 3.6770 * 8.192

		when "01100" =>				-- Termino A45*X5
			S_6 <= prodP01;						-- Almacena A64*X4
			prodA01 <= X5(30 downto 13);
			prodB01 <= "000000000000100100";	-- 	A45 = 0.0044 * 8.192

		when "01101" =>				-- Termino A55*X5
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A45*X5)
			prodB01 <= "000001111111110101";	-- 	A55 = 0.9987 * 8.192

		when "01110" =>				-- Termino A65*X5
			S_4 <= S_4 + Auxi01;					-- Suma A44*X4 + A45*X5
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (A55*X5)
			prodB01 <= "000000000110011011";	-- 	A65 = 0.0502 * 8.192

		when "01111" =>				-- Termino A56*X6
			S_5 <= S_5 + Auxi02;					-- Suma A54*X4 + A55*X5
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A65*X5)
			prodA01 <= X6(30 downto 13);
			prodB01 <= "111111111001100101";	-- 	A56 = -0.0502 * 8.192

		when "10000" =>				-- Termino A66*X6
			S_6 <= S_6 + Auxi01;					-- Suma A64*X4 + A65*X5
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (A56*X6)
			prodB01 <= "000001111111110101";	-- 	A66 = 0.9987 * 8.192

		when "10001" =>				-- Termino B11*Vo_star_0
			S_5 <= S_5 + Auxi02;					-- Suma A54*X4 + A55*X5 + A56*X6
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (A66*X6)
			if Vo_star_0(8) = '0' then
				prodA01 <= Vo_star_0 & "00";
			else
				prodA01 <= Vo_star_0 & "00";
			end if;
			prodB01 <= "000000000000100100";	-- 	B11 = 0.0044 * 8.192

		when "10010" =>				-- Termino B42*Vo_star_1
			S_6 <= S_6 + Auxi01;					-- Suma A64*X4 + A65*X5 + A66*X6
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (B11*Vo_star_0)
			if Vo_star_1(8) = '0' then
				prodA01 <= Vo_star_1 & "00";
			else
				prodA01 <= Vo_star_1 & "00";
			end if;

		when "10011" =>				-- Termino B13*Io_0
			S_1 <= S_1 + Auxi02;					-- Suma A11*X1 + A12*X2 + B11*Vo_star_0
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (B42*Vo_star_1)
			prodA01 <= Io_0(30 downto 13);
			prodB01 <= "000000101100001101";	-- 	B13 = 0.3453 * 8.192

		when "10100" =>				-- Termino B23*Io_0
			S_4 <= S_4 + Auxi01;					-- Suma A44*X4 + A45*X5 + B42*Vo_star_1
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (B13*Io_0)
			prodB01 <= "010010101111001110";	-- 	B23 = 9.3689 * 8.192

		when "10101" =>				-- Termino B33*Io_0
			X1 <= S_1 + Auxi02;					-- Suma A11*X1 + A12*X2 + B11*Vo_star_0 + B13*Io_0
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (B23*Io_0)
			prodB01 <= "111000101001010110";	-- 	B33 = -3.6770 * 8.192
			Y1 <= X1;								-- Y_o(k) = C_o * X_o(k)

		when "10110" =>				-- Termino B44*Io_1
			X2 <= S_2 + Auxi01;					-- Suma A21*X1 + A22*X2 + A23*X3 + B23*Io_0
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (B33*Io_0)
			prodA01 <= Io_1(30 downto 13);
			prodB01 <= "000000101100001101";	-- 	B44 = 0.3453 * 8.192

		when "10111" =>				-- Termino B54*Io_1
			X3 <= S_3 + Auxi02;					-- Suma A31*X1 + A32*X2 + A33*X3 + B33*Io_0
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (B44*Io_1)
			prodB01 <= "010010101111001110";	-- 	B54 = 9.3689 * 8.192
			Y3 <= X2;								-- Y_o(k) = C_o * X_o(k)

		when "11000" =>				-- Termino B64*Io_1
			X4 <= S_4 + Auxi01;					-- Suma A44*X4 + A45*X5 + B42*Vo_star_1 + B44*Io_1
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (B54*Io_1)
			prodB01 <= "111000101001010110";	-- 	B64 = -3.6770 * 8.192
			Y2 <= X4;								-- Y_o(k) = C_o * X_o(k)
--
-- A partir de aqui comienza el calculo de V_og(k)
--			Se superpone un poco con el cambio de estado X(k) --> X(k+1)
--
		when "11001" =>				-- Termino Ko11*Y1
			X5 <= S_5 + Auxi02;					-- Suma A54*X4 + A55*X5 + A56*X6 + B54*Io_1
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (B64*Io_1)
			prodA01 <= Y1(30 downto 13);
			prodB01 <= "110011111100100110";	-- 	-Ko11 = -6.0265 * 8.192

		when "11010" =>				-- Termino Ko22*Y2
			X6 <= S_6 + Auxi01;					-- Suma A64*X4 + A65*X5 + A66*X6 + B64*Io_1
			Auxi02 <= prodP01;					-- Desocupa el multiplicador (-Ko11*Y1)
			prodA01 <= Y2(30 downto 13);
			Y4 <= X5;
--
-- Con la disponibilidad de Y cuntinua el calculo de Vog
--
		when "11011" =>
			Vog_0_long <= Vog_0_long + Auxi02;	-- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1 - Ko11*Y1
			Auxi01 <= prodP01;					-- Desocupa el multiplicador (Ko22*Y2)

		when "11100" =>
			Vog_1_long <= Vog_1_long + Auxi01;	-- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1 - Ko22*Y2
			
		when "11101" =>
			Vog_0_long <= Vog_0_long - Y3;	-- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1 - Y3 - Ko11*Y1

		when "11110" =>
			Vog_1_long <= Vog_1_long - Y4;	-- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1 - Y4 - Ko22*Y2

		when others =>	null;	--
				
		end case;
end if;
end process;

process (clock)
begin
if clock = '1' and clock'event then		-- Flanco de ascendente
--
-- Primer tramo del calculo de V_og(k)
--		Es posible porque el termino (Gv + Ko) * i_r (k) no necesita ni de X ni de Y
--
--	Resolucion de i_r 
--													 		  1
--		.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.--.
--		|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
--		´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´--´
--							 |								  | |			  |
--							 '------------------------' '---------'
--											  |						|
--											  |						'---> Decimales (4 bits)
--											  '---------> Resolucion de medicion (9 bits)
	case stat is
		when "00000" =>				-- Termino (GV+Ko)11*Ir_0 
			if Ir_0(8) = '0' then				-- Carga extension numerica de Ir_0
				prodA02 <= "00000" & Ir_0 & "0000";
			else
				prodA02 <= "11111" & Ir_0 & "0000";
			end if;
			prodB02 <= "010101011110111100";	-- 	(GV+Ko)11 = 10.7417 * 8.192

		when "00001" =>				-- Termino (GV+Ko)21*Ir_0
			Vog_0_long <= prodP02;				-- Almacena (GV+Ko)11*Ir_0
			prodB02 <= "010110101010010100";	-- 	(GV+Ko)21 = 11.3306 * 8.192

		when "00010" =>				-- Termino (GV+Ko)12*Ir_1
			Vog_1_long <= prodP02;				-- Almacena (GV+Ko)21*Ir_0
			if Ir_1(8) = '0' then				-- Carga extension numerica de Ir_1
				prodA02 <= "00000" & Ir_1 & "0000";
			else
				prodA02 <= "11111" & Ir_1 & "0000";
			end if;
			prodB02 <= "101010100001000011";	-- 	(GV+Ko)12 = -11.3306 * 8.192

		when "00011" =>				-- Termino (GV+Ko)22*Ir_1
			Auxi03 <= prodP02;					-- Desocupa el multiplicador ((GV+Ko)12*Ir_1)
			prodB02 <= "010101011110111100";	-- 	(GV+Ko)22 = 10.7417 * 8.192
--
--	A partir de aqui comienza la transformacion de trifasica a bifasica de la corriente de salida,
--	a la vez que completa el calculo del primer tramo de V_og(k) vaciando el pipeline (2 terminos).
--
		when "00100" =>				-- Termino KaBI11*Io_u
			Auxi04 <= prodP02;					-- Desocupa el multiplicador ((GV+Ko)22*Ir_1)
			Vog_0_long <= Vog_0_long + Auxi03;	-- Suma (GV+Ko)11*Ir_0 + (GV+Ko)12*Ir_1
			if Io_u(8) = '0' then				-- Carga extension numerica de Io_u
				prodA02 <= "00000" & Io_u & "0000";
			else
				prodA02 <= "11111" & Io_u & "0000";
			end if;
			prodB02 <= "000001010101010101";	-- 	KaBI11 = 0.6667 * 8.192

		when "00101" =>				-- Termino KaBI12*Io_v 
			Io_0 <= prodP02;						-- Almacena KaBI11*Io_u
			Vog_1_long <= Vog_1_long + Auxi04;	-- Suma (GV+Ko)21*Ir_0 + (GV+Ko)22*Ir_1
			if Io_v(8) = '0' then				-- Carga extension numerica de Io_v
				prodA02 <= "00000" & Io_v & "0000";
			else
				prodA02 <= "11111" & Io_v & "0000";
			end if;
			prodB02 <= "111111010101010101";	-- 	KaBI12 = -0.3333 * 8.192

		when "00110" =>				-- Termino KaBI22*Io_v 
			Auxi03 <= prodP02;					-- Desocupa el multiplicador (KaBI12*Io_v)
			prodB02 <= "000001001001111001";	-- 	KaBI22 = 0.5774 * 8.192

		when "00111" =>				-- Termino KaBI13*Io_w 
			Io_1 <= prodP02;						-- Almacena KaBI22*Io_v
			Io_0 <= Io_0 + Auxi03;				-- Suma KaBI11*Io_u + KaBI12*Io_v
			if Io_w(8) = '0' then				-- Carga extension numerica de Io_w
				prodA02 <= "00000" & Io_w & "0000";
			else
				prodA02 <= "11111" & Io_w & "0000";
			end if;
			prodB02 <= "111111010101010101";	-- 	KaBI12 = -0.3333 * 8.192

		when "01000" =>				-- Termino KaBI23*Io_w 
			Auxi03 <= prodP02;					-- Desocupa el multiplicador (KaBI13*Io_w)
			prodB02 <= "111110110110000110";	-- 	KaBI22 = -0.5774 * 8.192

		when "01001" =>				-- Termino 
			Io_0 <= Io_0 + Auxi03;				-- Suma KaBI11*Io_u + KaBI12*Io_v + KaBI13*Io_w
			Auxi04 <= prodP02;					-- Desocupa el multiplicador (KaBI23*Io_w)

		when "01010" =>				-- Termino 
			Io_1 <= Io_1 + Auxi04;						-- Suma KaBI22*Io_v + KaBI23*Io_w

		when others =>	null;	--
				
		end case;
end if;
end process;




Multi01 : MULT18X18		--	MUL1
   port map (
      P => prodP01,    -- 36-bit multiplier output
      A => prodA01,    -- 18-bit multiplier input
      B => prodB01     -- 18-bit multiplier input
   );

Multi02 : MULT18X18		--	MUL1
   port map (
      P => prodP02,    -- 36-bit multiplier output
      A => prodA02,    -- 18-bit multiplier input
      B => prodB02     -- 18-bit multiplier input
   );


end Behavioral;

