----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10.01.2025 22:30:51
-- Design Name: 
-- Module Name: Tb_Modulador_1 - Behavioral
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use ieee.std_logic_textio.all;
use std.env.finish;

entity tb_modulador is
end tb_modulador;

architecture tb of tb_modulador is

    component modulador
        port (i_reloj     : in std_logic;
              i_al_o      : in std_logic_vector (10 downto 0);
              i_be_i      : in std_logic_vector (10 downto 0);
              i_q_i       : in std_logic_vector (8 downto 0);
              i_phi_i     : in std_logic_vector (10 downto 0);
              o_fin_ciclo    : out std_logic;
              o_inicio_ciclo : out std_logic;
              o_fin_calc_ts  : out std_logic;
              o_direcciones  : out std_logic_vector (17 downto 0));
    end component;

    signal auxi00      : std_logic;
    signal auxi01      : std_logic;
    signal auxi02      : std_logic;
    signal direcciones : std_logic_vector (17 downto 0);

    constant TbPeriod : time := 5 ns; -- 200MHz
    signal TbClock : std_logic := '0';
    signal TbSimEnded : std_logic := '0';

    signal T1, T2, T3, T4, T5 ,T6 ,T7 ,T8 ,T9, T10, T11, T12, T13 :integer := 0;
    signal AL_O : std_logic_vector (10 downto 0) := "00000000000";
    signal BE_I : std_logic_vector (10 downto 0) := "00000000000";
    signal Q_I : std_logic_vector (8 downto 0) := "000000000";
    signal PHI_I : std_logic_vector (10 downto 0) := "00000000000";
    
    --Archivos I/O
    file ArchivoSalida : TEXT open WRITE_MODE is "F:\Proyecto_Final\repo\FinalProject_Ing\HW\src\tb\util\output.txt";
    file ArchivoEntrada : TEXT open READ_MODE is "F:\Proyecto_Final\repo\FinalProject_Ing\HW\src\tb\util\input.txt";

begin

    dut : modulador
    port map (i_reloj       => TbClock,
              i_al_o        => al_o,
              i_be_i        => be_i,
              i_q_i         => q_i,
              i_phi_i       => phi_i,
              o_fin_ciclo    => auxi00,
              o_inicio_ciclo => auxi01,
              o_fin_calc_ts  => auxi02,
              o_direcciones  => direcciones);

    -- Clock process definitions
   RELOJ_process :process
   begin
		TbClock <= '0';
		wait for TbPeriod/2;
		TbClock <= '1';
		wait for TbPeriod/2;
   end process;

    MEDIDOR_TIEMPO :process(TbClock, AUXI02)
    begin
        if(rising_edge(TbClock)) then
             if DIRECCIONES(0) = '1' then
                 T1 <= T1 + 1;
             end if;
             if DIRECCIONES(1) = '1' then
                 T2 <= T2 + 1;
             end if;
             if DIRECCIONES(2) = '1' then
                 T3 <= T3 + 1;
             end if;
             if DIRECCIONES(3) = '1' then
                 T4 <= T4 + 1;
             end if;
             if DIRECCIONES(4) = '1' then
                 T5 <= T5 + 1;
             end if;
             if DIRECCIONES(5) = '1' then
                 T6 <= T6 + 1;
             end if;
             if DIRECCIONES(6) = '1' then
                 T7 <= T7 + 1;
             end if;
             if DIRECCIONES(7) = '1' then
                 T8 <= T8 + 1;
             end if;
             if DIRECCIONES(8) = '1' then
                 T9 <= T9 + 1;
             end if;
             if DIRECCIONES(9) = '1' then
                 T10 <= T10 + 1; 
             end if;
             if DIRECCIONES(10) = '1' then
                 T11 <= T11 + 1;
             end if;
             if DIRECCIONES(11) = '1' then
                 T12 <= T12 + 1;
             end if;
             if DIRECCIONES(12) = '1' then
                 T13 <= T13 + 1;
             end if;
        end if;
        
        if(falling_edge(AUXI02)) then
             T1 <= 0;
             T2 <= 0;
             T3 <= 0;
             T4 <= 0;
             T5 <= 0;
             T6 <= 0;
             T7 <= 0;
             T8 <= 0;
             T9 <= 0;
             T10 <= 0;
             T11 <= 0;
             T12 <= 0;
             T13 <= 0;
        end if;
    end process;
    
 --Lectura del archivo con datos de entrada
     LECTURA_process : process (AUXI02)
         variable line_input : line;
         variable param : string(1 downto 3);
         variable alo : std_logic_vector (10 downto 0);
         variable bei : std_logic_vector (10 downto 0);
         variable phi : std_logic_vector (10 downto 0);
         variable q : std_logic_vector (8 downto 0);
         
         begin
             if(endfile(ArchivoEntrada)) then
                 report "Archivo entrada leido completamente";
             end if;
         
             if(rising_edge(AUXI02) and not endfile(ArchivoEntrada)) then
                 readline(ArchivoEntrada, line_input);
                 hread(line_input, alo);
                 
                 AL_O <= alo;
                 --
                 readline(ArchivoEntrada, line_input);
                 hread(line_input, bei);
                 
                 BE_I <= bei;
                 --
                 readline(ArchivoEntrada, line_input);
                 read(line_input, q);
                 
                 Q_I <= q;
                 --
                 readline(ArchivoEntrada, line_input);
                 hread(line_input, phi);
                 
                 PHI_I <= phi;
                 
                 readline(ArchivoEntrada, line_input);
             end if;
     end process;
     
 --Escritura del archivo de salida
     ESCRITURA_process : process (AUXI02)
     
         variable line_output : line;
         variable Ttot : integer :=0;
         
         begin
             if(rising_edge(AUXI02)) then
                 Ttot := (T1 + T2 + T3 + T4 + T5 + T6 + T7 + T8 + T9 + T10 + T11 + T12 + T13); 
             
                 write(line_output, string'("Valores Direcciones, "));
                 write(line_output, string'("multiplicar por 0.005 us para obtener valor temporal"));
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N1: "));
                 write(line_output, T1);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N2: "));
                 write(line_output, T2);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N3: "));
                 write(line_output, T3);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N4: "));
                 write(line_output, T4);                
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N5: "));
                 write(line_output, T5);              
                 writeline(ArchivoSalida, line_output);
 
                 write(line_output, string'("N6: "));
                 write(line_output, T6);
                 writeline(ArchivoSalida, line_output);
 
                 write(line_output, string'("N7: "));
                 write(line_output, T7);
                 writeline(ArchivoSalida, line_output);
 
                 write(line_output, string'("N8: "));
                 write(line_output, T8);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N9: "));
                 write(line_output, T9);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("N10: "));
                 write(line_output, T10);
                 writeline(ArchivoSalida, line_output);
     
                 write(line_output, string'("N11: "));
                 write(line_output, T11);
                 writeline(ArchivoSalida, line_output);
 
                 write(line_output, string'("N12: "));
                 write(line_output, T12);
                 writeline(ArchivoSalida, line_output);
             
                 write(line_output, string'("N13: "));
                 write(line_output, T13);
                 writeline(ArchivoSalida, line_output);
                 
                 write(line_output, string'("Ntot: "));
                 write(line_output, Ttot);
                 writeline(ArchivoSalida, line_output);
                 Ttot := 0;
             end if;
             
     end process;

end tb;

