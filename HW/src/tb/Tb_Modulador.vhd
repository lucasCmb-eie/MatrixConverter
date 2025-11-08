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
  use std.textio.all;
  use ieee.std_logic_textio.all;
  use std.env.finish;

entity tb_modulador is
end entity tb_modulador;

architecture tb of tb_modulador is

  component modulador is
    port (
      i_reloj        : in    std_logic;
      i_al_o         : in    std_logic_vector(10 downto 0);
      i_be_i         : in    std_logic_vector(10 downto 0);
      i_q_i          : in    std_logic_vector(8 downto 0);
      i_phi_i        : in    std_logic_vector(10 downto 0);
      i_enable       : in    std_logic;
      o_fin_ciclo    : out   std_logic;
      o_inicio_ciclo : out   std_logic;
      o_fin_calc_ts  : out   std_logic;
      o_direcciones  : out   std_logic_vector(17 downto 0)
    );
  end component modulador;

  signal auxi00      : std_logic;
  signal auxi01      : std_logic;
  signal auxi02      : std_logic;
  signal direcciones : std_logic_vector(17 downto 0);

  constant tbperiod   : time      := 5 ns; -- 200MHz
  signal   tbclock    : std_logic := '0';
  signal   tbsimended : std_logic := '0';

  signal t1     : integer                       := 0;
  signal t2     : integer                       := 0;
  signal t3     : integer                       := 0;
  signal t4     : integer                       := 0;
  signal t5     : integer                       := 0;
  signal t6     : integer                       := 0;
  signal t7     : integer                       := 0;
  signal t8     : integer                       := 0;
  signal t9     : integer                       := 0;
  signal t10    : integer                       := 0;
  signal t11    : integer                       := 0;
  signal t12    : integer                       := 0;
  signal t13    : integer                       := 0;
  signal al_o   : std_logic_vector(10 downto 0) := "00000000000";
  signal be_i   : std_logic_vector(10 downto 0) := "00000000000";
  signal q_i    : std_logic_vector(8 downto 0)  := "000000000";
  signal phi_i  : std_logic_vector(10 downto 0) := "00000000000";
  signal enable : std_logic                     := '0';

  -- Archivos I/O
  file ArchivoSalida  : TEXT open WRITE_MODE is "F:\Proyecto_Final\repo\FinalProject_Ing\HW\src\tb\util\output.txt";
  file ArchivoEntrada : TEXT open READ_MODE is "F:\Proyecto_Final\repo\FinalProject_Ing\HW\src\tb\util\input.txt";

begin

  dut : component modulador
    port map (
      i_reloj        => tbclock,
      i_al_o         => al_o,
      i_be_i         => be_i,
      i_q_i          => q_i,
      i_phi_i        => phi_i,
      i_enable       => enable,
      o_fin_ciclo    => auxi00,
      o_inicio_ciclo => auxi01,
      o_fin_calc_ts  => auxi02,
      o_direcciones  => direcciones
    );

  -- Clock process definitions
  reloj_process : process is
  begin

    tbclock <= '0';
    wait for tbperiod / 2;
    tbclock <= '1';
    wait for tbperiod / 2;

  end process reloj_process;

  reset_proceso : process is
    begin
        wait for 10 us;
        enable <= '1';
        wait;
    end process;

  medidor_tiempo : process (tbclock, auxi02) is
  begin

    if (rising_edge(tbclock) and enable = '1') then
      if (direcciones(0) = '1') then
        t1 <= t1 + 1;
      end if;
      if (direcciones(1) = '1') then
        t2 <= t2 + 1;
      end if;
      if (direcciones(2) = '1') then
        t3 <= t3 + 1;
      end if;
      if (direcciones(3) = '1') then
        t4 <= t4 + 1;
      end if;
      if (direcciones(4) = '1') then
        t5 <= t5 + 1;
      end if;
      if (direcciones(5) = '1') then
        t6 <= t6 + 1;
      end if;
      if (direcciones(6) = '1') then
        t7 <= t7 + 1;
      end if;
      if (direcciones(7) = '1') then
        t8 <= t8 + 1;
      end if;
      if (direcciones(8) = '1') then
        t9 <= t9 + 1;
      end if;
      if (direcciones(9) = '1') then
        t10 <= t10 + 1;
      end if;
      if (direcciones(10) = '1') then
        t11 <= t11 + 1;
      end if;
      if (direcciones(11) = '1') then
        t12 <= t12 + 1;
      end if;
      if (direcciones(12) = '1') then
        t13 <= t13 + 1;
      end if;
    end if;

    if (falling_edge(auxi02) and enable = '1') then
      t1  <= 0;
      t2  <= 0;
      t3  <= 0;
      t4  <= 0;
      t5  <= 0;
      t6  <= 0;
      t7  <= 0;
      t8  <= 0;
      t9  <= 0;
      t10 <= 0;
      t11 <= 0;
      t12 <= 0;
      t13 <= 0;
    end if;

  end process medidor_tiempo;

  -- Lectura del archivo con datos de entrada
  lectura_process : process (auxi02) is

    variable line_input : line;
    variable param      : string(1 downto 3);
    variable alo        : std_logic_vector(10 downto 0);
    variable bei        : std_logic_vector(10 downto 0);
    variable phi        : std_logic_vector(10 downto 0);
    variable q          : std_logic_vector(8 downto 0);

  begin

    if (endfile(ArchivoEntrada)) then
      report "Archivo entrada leido completamente";
    end if;

    if (rising_edge(auxi02) and not endfile(ArchivoEntrada)) then
      readline(ArchivoEntrada, line_input);
      hread(line_input, alo);

      al_o <= alo;
      --
      readline(ArchivoEntrada, line_input);
      hread(line_input, bei);

      be_i <= bei;
      --
      readline(ArchivoEntrada, line_input);
      read(line_input, q);

      q_i <= q;
      --
      readline(ArchivoEntrada, line_input);
      hread(line_input, phi);

      phi_i <= phi;

      readline(ArchivoEntrada, line_input);
    end if;

  end process lectura_process;

  -- Escritura del archivo de salida
  escritura_process : process (auxi02) is

    variable line_output : line;
    variable ttot        : integer := 0;

  begin

    if (rising_edge(auxi02)) then
      ttot := (t1 + t2 + t3 + t4 + t5 + t6 + t7 + t8 + t9 + t10 + t11 + t12 + t13);

      write(line_output, string'("Valores Direcciones, "));
      write(line_output, string'("multiplicar por 0.005 us para obtener valor temporal"));
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N1: "));
      write(line_output, t1);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N2: "));
      write(line_output, t2);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N3: "));
      write(line_output, t3);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N4: "));
      write(line_output, t4);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N5: "));
      write(line_output, t5);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N6: "));
      write(line_output, t6);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N7: "));
      write(line_output, t7);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N8: "));
      write(line_output, t8);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N9: "));
      write(line_output, t9);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N10: "));
      write(line_output, t10);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N11: "));
      write(line_output, t11);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N12: "));
      write(line_output, t12);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("N13: "));
      write(line_output, t13);
      writeline(ArchivoSalida, line_output);

      write(line_output, string'("Ntot: "));
      write(line_output, Ttot);
      writeline(ArchivoSalida, line_output);
      ttot := 0;
    end if;

  end process escritura_process;

end architecture tb;

