library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

library std;
use std.textio.all;

entity tb_SVM_Wrapper is
end tb_SVM_Wrapper;

architecture Behavioral of tb_SVM_Wrapper is
    
    constant PER2 : time := (10 ns /2); -- Se busca 100MHz
    constant CLK_FREQ : real := 1.0e8;
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;
    constant coef_Alpha : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.00004166, INT_BITS-1, -FRAC_BITS);
    constant coef_Beta  : sfixed(INT_BITS-1 downto -FRAC_BITS) := to_sfixed(0.999999000, INT_BITS-1, -FRAC_BITS);
    
    constant q_value : std_logic_vector(8 downto 0) := "100000000"; -- Valor fijo de q (Q0.8)
    constant phi_value : std_logic_vector(10 downto 0) := "00000000000"; -- Valor fijo de phi_i

    signal fin_calc_ts : std_logic;
    signal fin_ciclo : std_logic;
    signal inicio_ciclo : std_logic;

    signal clk : std_logic;
    signal rst : std_logic;
    signal enable_SVM : std_logic;
    signal tick_enable : std_logic;

    signal alph_O : std_logic_vector(10 downto 0);

    -- Señales de tension trifasica
    signal tension_fase_U : std_logic_vector(31 downto 0);
    signal tension_fase_V : std_logic_vector(31 downto 0);
    signal tension_fase_W : std_logic_vector(31 downto 0);

    -- Señales entre SVM y RL
    signal tension_SVM_U : std_logic_vector(31 downto 0);
    signal tension_SVM_V : std_logic_vector(31 downto 0);
    signal tension_SVM_W : std_logic_vector(31 downto 0);

    -- Señales T. Clark de tension trifasica
    signal Clark_alfa_Vi : std_logic_vector(31 downto 0);
    signal Clark_beta_Vi : std_logic_vector(31 downto 0);
    signal Clark_alfa_Io : std_logic_vector(31 downto 0);
    signal Clark_beta_Io : std_logic_vector(31 downto 0);

    -- Salida diente de sierra
    signal Sierra_angle_50Hz : std_logic_vector(10 downto 0);-- Salida del diente de sierra 50Hz
    signal Sierra_angle_Var : std_logic_vector(10 downto 0);-- Salida del diente de sierra variable
    
    signal w_direcciones : std_logic_vector(17 downto 0); --Coeficientes de la matriz de conmutacion
begin
    
    modulador_core : entity work.modulador
        port map (
            i_reloj        => clk,
            i_enable       => enable_SVM,
            i_al_o         => Sierra_angle_50Hz,
            i_be_i         => Sierra_angle_50Hz,
            i_q_i          => "000100000",
            i_phi_i        => "00000000000", 
            o_fin_ciclo    => fin_ciclo,
            o_inicio_ciclo => inicio_ciclo,
            o_fin_calc_ts  => fin_calc_ts,
            o_direcciones  => w_direcciones
        );

    matrixConmut_core : entity work.matrixConmut
        port map (
            i_clk => clk,
            i_M   => w_direcciones,
            i_U => tension_fase_U,
            i_V => tension_fase_V,
            i_W => tension_fase_W,

            o_U => tension_SVM_U,
            o_V => tension_SVM_V,
            o_W => tension_SVM_W
        );
    
    --NCO
    AC: entity work.AC_SOURCE
        port map (
            i_clk => clk,
            i_rst => rst,

            o_U   => tension_fase_U,
            o_V   => tension_fase_V,
            o_W   => tension_fase_W
        );

    U_EnableGen : entity work.EnableGen
        generic map (
            CLK_FREQ_HZ => 100000000,
            TCONV_NS    => 16000     -- Tconv = 16 µs
        )
        port map (
            i_clk  => clk,
            i_rst  => rst,
            o_tick => tick_enable
        );

    TClark_Vi: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_enable => tick_enable,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_alfa => Clark_alfa_Vi,
            o_beta => Clark_beta_Vi
        );

    TClark_Io: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_enable => tick_enable,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_alfa => Clark_alfa_Io,
            o_beta => Clark_beta_Io
        );

    PhaseGenVar: entity work.PhaseSawGen
        generic map(
            G_CLK_FREQ => 1.0e8,  -- frecuencia de reloj (Hz)
            G_SAW_FREQ   => 100.0    -- frecuencia de la senoide (Hz)
        )
        port map (
            i_clk   => clk,
            i_rst   => rst,
            i_sin   => to_sfixed(Clark_alfa_Vi, INT_BITS - 1, -FRAC_BITS),  -- usamos componente α
            o_angle => Sierra_angle_Var
        );

    PhaseGen50: entity work.PhaseSawGen
        port map (
            i_clk   => clk,
            i_rst   => rst,
            i_sin   => to_sfixed(Clark_alfa_Vi, INT_BITS - 1, -FRAC_BITS),  -- usamos componente α
            o_angle => Sierra_angle_50Hz
        );

    DoClock: process
    begin
        clk <= '1';
        wait for PER2;
        clk <= '0';
        wait for PER2;
        
    end process DoClock;

    -- Init
    InitTest: process
        begin
            --Starting Test
            report "ncoLUT_tb start...";
            report "Reset";   
            rst <= '1';
            enable_SVM <= '0';
            wait for (2*PER2);
            report "Begin";
            rst <= '0';
            enable_SVM <= '1';
            alph_O <= Sierra_angle_50Hz;
            wait for 90ms;
            alph_O <= Sierra_angle_Var;

        end process InitTest;

    -- ========================================================================
    -- PROCESO DE LOGGING A CSV (Muestreo @ 5MHz)
    -- ========================================================================
    -- Asegúrate de incluir 'use std.textio.all;' antes de la entity si no está.
    
    gen_csv_5MHz: process
        file file_handler : text open write_mode is "F:\Proyecto_Final\repo\FinalProject_Ing\SW\matlab\test.csv";
        variable row      : line;
        
        -- Contadores y control
        variable v_ciclos_counter : integer := 2;
        variable v_muestra_idx    : integer := 0;
        constant C_DIVISOR        : integer := 20; -- 100MHz / 5MHz = 20
        
        -- Variables auxiliares para conversión a Real
        variable v_real_U : real;
        variable v_real_V : real;
        variable v_real_W : real;
    begin
        -- 1. Escribir Encabezado
        write(row, string'("Muestra,Tension_U,Tension_V,Tension_W"));
        writeline(file_handler, row);

        -- 2. Bucle principal
        loop
            wait until rising_edge(clk);
            
            -- Solo ejecutamos la escritura cuando el contador llega a 0
            --if v_ciclos_counter = 0 then
                
                -- Conversión de Q8.24 (std_logic_vector) a REAL usando fixed_pkg
                -- Usamos las constantes ya definidas en tu código [cite: 4]
                v_real_U := to_real(to_sfixed(tension_SVM_U, INT_BITS-1, -FRAC_BITS));
                v_real_V := to_real(to_sfixed(tension_SVM_V, INT_BITS-1, -FRAC_BITS));
                v_real_W := to_real(to_sfixed(tension_SVM_W, INT_BITS-1, -FRAC_BITS));

                -- Columna 1: Indice de muestra (equivale a pasos de 200ns)
                write(row, v_muestra_idx);
                write(row, string'(","));
                
                -- Columna 2: U
                write(row, v_real_U);
                write(row, string'(","));
                
                -- Columna 3: V
                write(row, v_real_V);
                write(row, string'(","));
                
                -- Columna 4: W
                write(row, v_real_W);
                
                writeline(file_handler, row);
                
                v_muestra_idx := v_muestra_idx + 1;
            --end if;

            -- Gestión del contador de diezmado (0 a 19)
            --if v_ciclos_counter = (C_DIVISOR - 1) then
             --   v_ciclos_counter := 0;
           -- else
            --    v_ciclos_counter := v_ciclos_counter + 1;
            --end if;
            
        end loop;
    end process gen_csv_5MHz;


end Behavioral;
