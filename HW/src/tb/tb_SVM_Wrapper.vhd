library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_SVM_Wrapper is
end tb_SVM_Wrapper;

architecture Behavioral of tb_SVM_Wrapper is
    
    constant PER2 : time := (100 ns /2); -- 10 MHz
    
    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;
    
    constant q_value : std_logic_vector(8 downto 0) := "000111000"; -- Valor fijo de q (Q0.8) 001000000 64
    constant phi_value : std_logic_vector(10 downto 0) := "00000000000"; -- Valor fijo de phi_i

    signal fin_calc_ts : std_logic;
    signal fin_ciclo : std_logic;
    signal inicio_ciclo : std_logic;

    signal clk : std_logic;
    signal rst : std_logic;
    signal enable_SVM : std_logic;

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
    signal Angle_Vi : unsigned(10 downto 0);-- Salida del diente de sierra 50Hz
    signal Angle_Io : unsigned(10 downto 0);-- Salida del diente de sierra variable
    
    signal w_direcciones : std_logic_vector(17 downto 0); --Coeficientes de la matriz de conmutacion
    signal w_trigger : std_logic;
    signal w_ClarkValido_V : std_logic;
    signal w_ClarkValido_I : std_logic;

begin
    
    modulador_core : entity work.SVM_wrapper
        port map(
            i_clk    => clk, 
            i_enable => enable_SVM,
            i_al_o   => STD_LOGIC_VECTOR(Angle_Vi), 
            i_be_i   => STD_LOGIC_VECTOR(Angle_Vi), 
            i_q_i    => q_value,  
            i_phi_i  => phi_value, 

            o_trg_calculo => w_trigger,
            o_direcciones_Matriz => w_direcciones,

            --Tensiones 
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
            i_frec => "01",

            o_U   => tension_fase_U,
            o_V   => tension_fase_V,
            o_W   => tension_fase_W
    );

    TClark_Vi: entity work.TransformadaClark
        generic map (
            INT_BITS  => INT_BITS,
            FRAC_BITS => FRAC_BITS
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_start => w_trigger,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_valido => w_ClarkValido_V,

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
            i_start => w_trigger,

            i_U   => tension_fase_U,
            i_V   => tension_fase_V,
            i_W   => tension_fase_W,

            o_valido => w_ClarkValido_I,

            o_alfa => Clark_alfa_Io,
            o_beta => Clark_beta_Io
    );
    
    PhaseGenVar_V: entity work.CORDIC_atan2
        port map (
            clk   => clk,
            rst   => rst,
            start   => w_ClarkValido_V, 

            x_in => signed(Clark_beta_Vi),
            y_in => signed(Clark_alfa_Vi),

            angle_out => Angle_Vi,
            done => open
    );

    PhaseGenVar_I: entity work.CORDIC_atan2
        port map (
            clk   => clk,
            rst   => rst,
            start   => w_ClarkValido_I, 

            x_in => signed(Clark_beta_Io),
            y_in => signed(Clark_alfa_Io),

            angle_out => Angle_Io,
            done => open
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
            rst <= '0';
            enable_SVM <= '1';
            -- alph_O <= Sierra_angle_50Hz;
            -- wait for 90ms;
            -- alph_O <= Sierra_angle_Var;
            wait;
        end process InitTest;

    -- ========================================================================
    -- PROCESO DE LOGGING A CSV (Muestreo @ 5MHz)
    -- ========================================================================
    -- Asegúrate de incluir 'use std.textio.all;' antes de la entity si no está.
    
    gen_csv_5MHz: process
        file file_handler : text open write_mode is "F:\FPGA\Potencia FPGA\MatrixConverter\SW\matlab\Clk10M_test50Hz_Simetrico.csv";
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

            
        end loop;
    end process gen_csv_5MHz;
    gen_w_direcciones_csv: process
        file file_w : text open write_mode is "F:\\FPGA\\Potencia FPGA\\MatrixConverter\\SW\\matlab\\w_direcciones_log.csv";
        variable row : line;
        variable v_idx : integer := 0;
        variable v_bin_str : string(1 to 18);
        variable i : integer;
    begin
        -- Encabezado CSV
        write(row, string'("Muestra,Direcciones"));
        writeline(file_w, row);

        -- Bucle de muestreo (cada rising_edge(clk))
        loop
            wait until rising_edge(clk);

            -- Construir cadena binaria de 18 bits desde w_direcciones(17 downto 0)
            v_bin_str := (others => '0');
            for i in 0 to 17 loop
                if w_direcciones(17 - i) = '1' then
                    v_bin_str(i+1) := '1';
                else
                    v_bin_str(i+1) := '0';
                end if;
            end loop;

            -- Escribir índice y valor
            write(row, v_idx);
            write(row, string'(","));
            write(row, v_bin_str);
            writeline(file_w, row);

            v_idx := v_idx + 1;
        end loop;
    end process gen_w_direcciones_csv;

end Behavioral;
