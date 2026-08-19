-- =========================================================================
-- tb_SVM_FoutVar
--
-- Variante de tb_SVM_Wrapper con la ENTRADA FIJA en 50 Hz (red) y la
-- frecuencia DESEADA DE SALIDA (rampa i_al_o) recorriendo escalones de
-- 40, 50 y 60 Hz, 0,2 s cada uno (0,6 s de simulacion en total).
--
-- El acumulador de fase de la salida NO se reinicia entre escalones: solo
-- cambia el incremento, asi que la fase es continua y el salto de frecuencia
-- no introduce una discontinuidad artificial en el angulo comandado.
--
-- Salidas a CSV (decimadas x10 -> Fs = 1 MHz):
--   Clk10M_50i_FoVar.csv     Muestra,Tension_U,Tension_V,Tension_W,Freq_Hz
--   w_direcciones_FoVar.csv  Muestra,Direcciones
-- Freq_Hz es la frecuencia comandada a la SALIDA en ese instante.
--
-- Nota: a diferencia de tb_SVM_Wrapper, aca no se instancian la segunda
-- TransformadaClark ni el segundo CORDIC (alimentaban Angle_Io, que no se
-- conectaba a nada). Se quitaron para no pagar su costo de simulacion.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;
use ieee.numeric_std.all;

use work.sine_lut_pkg.all;

library std;
use std.textio.all;

entity tb_SVM_FoutVar is
end tb_SVM_FoutVar;

architecture Behavioral of tb_SVM_FoutVar is

    constant PER2 : time := (100 ns /2); -- 10 MHz

    constant INT_BITS    : integer := 8;
    constant FRAC_BITS   : integer := 24;

    constant q_value   : std_logic_vector(8 downto 0)  := "010110011"; -- q (Q0.8) = 179
    constant phi_value : std_logic_vector(10 downto 0) := "00000000000";

    signal clk : std_logic;
    signal rst : std_logic;
    signal enable_SVM : std_logic;

    -- Senales de tension trifasica de entrada (fuente ideal)
    signal tension_fase_U : std_logic_vector(31 downto 0);
    signal tension_fase_V : std_logic_vector(31 downto 0);
    signal tension_fase_W : std_logic_vector(31 downto 0);

    -- Senales entre SVM y la carga
    signal tension_SVM_U : std_logic_vector(31 downto 0);
    signal tension_SVM_V : std_logic_vector(31 downto 0);
    signal tension_SVM_W : std_logic_vector(31 downto 0);

    -- T. Clark de la tension de entrada
    signal Clark_alfa_Vi : std_logic_vector(31 downto 0);
    signal Clark_beta_Vi : std_logic_vector(31 downto 0);

    signal Angle_Vi : unsigned(10 downto 0); -- angulo de entrada por el camino real

    signal test_al_o : std_logic_vector(10 downto 0); -- rampa de salida (frecuencia variable)
    signal test_be_i : std_logic_vector(10 downto 0); -- rampa ideal de entrada, solo referencia
    signal w_direcciones : std_logic_vector(17 downto 0);
    signal w_trigger : std_logic;
    signal w_ClarkValido_V : std_logic;

    -- ---------------------------------------------------------------------
    -- Escalones de frecuencia de SALIDA
    -- ---------------------------------------------------------------------
    -- FTW = round(f * 2^32 / 10 MHz) = round(f * 429,4967296)
    type ftw_array_t  is array (0 to 2) of unsigned(31 downto 0);
    type freq_array_t is array (0 to 2) of integer;

    constant FTW_STEPS : ftw_array_t := (to_unsigned(17180, 32),   -- 40 Hz
                                         to_unsigned(21475, 32),   -- 50 Hz
                                         to_unsigned(25770, 32));  -- 60 Hz
    constant FREQ_STEPS : freq_array_t := (40, 50, 60);

    constant CICLOS_POR_ESCALON : integer := 2000000; -- 0,2 s a 10 MHz
    constant T_TOTAL            : time    := 600 ms;  -- 3 escalones

    signal idx_escalon : integer range 0 to 2 := 0;
    signal ftw_out     : unsigned(31 downto 0);
    signal freq_hz     : integer;

    -- Acumulador de fase de la rampa de salida
    signal phase_accumulator : unsigned(31 downto 0) := (others => '0');

    -- Fuente trifasica de entrada FIJA en 50 Hz
    constant FREQ_TUNING_WORD_IN : unsigned(31 downto 0) := to_unsigned(21475, 32); -- 50 Hz

    -- Acumuladores de fase del NCO trifasico de entrada. Secuencia POSITIVA,
    -- igual que AC_Source: V = -120 grados, W = +120 grados.
    -- OJO: el desfase va tambien en el valor inicial de la DECLARACION, no solo
    -- en el reset, porque 'rst' baja cerca de un flanco de clk y si se pierde
    -- por carrera de deltas las tres fases arrancarian en 0 (U=V=W).
    signal phase_acc_U : unsigned(31 downto 0) := x"00000000";
    signal phase_acc_V : unsigned(31 downto 0) := x"AAAAAAA9";  -- -120 grados
    signal phase_acc_W : unsigned(31 downto 0) := x"55555555";  -- +120 grados

    -- Corte ordenado de la simulacion (permite cerrar los archivos CSV)
    signal fin_sim : std_logic := '0';

begin

    modulador_core : entity work.SVM_wrapper
        port map(
            i_clk    => clk,
            i_enable => enable_SVM,
            i_al_o   => test_al_o,
            -- Angulo de entrada por el camino real: TransformadaClark + CORDIC_atan2
            i_be_i   => std_logic_vector(Angle_Vi),
            i_q_i    => q_value,
            i_phi_i  => phi_value,

            o_trg_calculo => w_trigger,
            o_direcciones_Matriz => w_direcciones,

            i_U => tension_fase_U,
            i_V => tension_fase_V,
            i_W => tension_fase_W,

            o_U => tension_SVM_U,
            o_V => tension_SVM_V,
            o_W => tension_SVM_W
    );

    -- ---------------------------------------------------------------------
    -- Fuente trifasica de entrada ideal, FIJA en 50 Hz
    -- ---------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                phase_acc_U <= x"00000000";
                phase_acc_V <= x"AAAAAAA9";  -- -120 grados
                phase_acc_W <= x"55555555";  -- +120 grados
            else
                phase_acc_U <= phase_acc_U + FREQ_TUNING_WORD_IN;
                phase_acc_V <= phase_acc_V + FREQ_TUNING_WORD_IN;
                phase_acc_W <= phase_acc_W + FREQ_TUNING_WORD_IN;
            end if;
        end if;
    end process;

    tension_fase_U <= std_logic_vector(SINE_TABLE(to_integer(phase_acc_U(31 downto 21))));
    tension_fase_V <= std_logic_vector(SINE_TABLE(to_integer(phase_acc_V(31 downto 21))));
    tension_fase_W <= std_logic_vector(SINE_TABLE(to_integer(phase_acc_W(31 downto 21))));

    -- Rampa ideal de entrada: no alimenta al modulador, queda como referencia
    -- para comparar contra Angle_Vi en el visor de ondas.
    -- Con secuencia positiva y tabla de senos, alfa = sin(theta) y beta = -cos(theta),
    -- asi que atan2(beta,alfa) = theta - PI/2, o sea theta - 512.
    test_be_i <= std_logic_vector(phase_acc_U(31 downto 21) - to_unsigned(512, 11));

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

    PhaseGenVar_V: entity work.CORDIC_atan2
        port map (
            clk   => clk,
            rst   => rst,
            start => w_ClarkValido_V,

            x_in => signed(Clark_alfa_Vi),
            y_in => signed(Clark_beta_Vi),

            angle_out => Angle_Vi,
            done => open
    );

    DoClock: process
    begin
        clk <= '1';
        wait for PER2;
        clk <= '0';
        wait for PER2;
    end process DoClock;

    InitTest: process
    begin
        report "tb_SVM_FoutVar: entrada fija 50 Hz, salida en escalones 40/50/60 Hz";
        rst <= '1';
        enable_SVM <= '0';
        -- 5*PER2 (no 2*PER2): asi el flanco de bajada de rst NO coincide con un
        -- flanco ascendente de clk y el reset se ve al menos en un flanco limpio.
        wait for (5*PER2);
        rst <= '0';
        enable_SVM <= '1';
        wait;
    end process InitTest;

    -- ---------------------------------------------------------------------
    -- Secuenciador de escalones de frecuencia de salida
    -- ---------------------------------------------------------------------
    EscalonFrec: process(clk)
        variable cont : integer range 0 to CICLOS_POR_ESCALON := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cont := 0;
                idx_escalon <= 0;
            elsif cont = CICLOS_POR_ESCALON - 1 then
                cont := 0;
                if idx_escalon < 2 then
                    idx_escalon <= idx_escalon + 1;
                end if;
            else
                cont := cont + 1;
            end if;
        end if;
    end process EscalonFrec;

    ftw_out <= FTW_STEPS(idx_escalon);
    freq_hz <= FREQ_STEPS(idx_escalon);

    -- ---------------------------------------------------------------------
    -- Rampa (NCO) de la referencia de salida deseada, frecuencia variable
    -- ---------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                phase_accumulator <= (others => '0');
            else
                phase_accumulator <= phase_accumulator + ftw_out;
            end if;
        end if;
    end process;

    -- Angulo de 11 bits para i_al_o: bits [31..21] mapeados de 0 a 2047
    test_al_o <= std_logic_vector(phase_accumulator(31 downto 21));

    -- ---------------------------------------------------------------------
    -- Corte de simulacion al terminar el ultimo escalon
    -- ---------------------------------------------------------------------
    FinDeSimulacion: process
    begin
        wait for T_TOTAL;
        fin_sim <= '1';
        wait for 1 us;   -- margen para que los procesos de log cierren los archivos
        report "tb_SVM_FoutVar: fin de los 3 escalones de frecuencia" severity failure;
        wait;
    end process FinDeSimulacion;

    -- ---------------------------------------------------------------------
    -- LOGGING A CSV (1 de cada 10 flancos -> Fs = 1 MHz)
    -- ---------------------------------------------------------------------
    gen_csv_tensiones: process
        file file_handler : text open write_mode is "F:\FPGA\Potencia FPGA\MatrixConverter\SW\matlab\Clk10M_50i_FoVar.csv";
        variable row      : line;

        variable v_muestra_idx : integer := 0;
        variable v_decim       : integer := 0;
        constant C_DECIMACION  : integer := 10;

        variable v_real_U : real;
        variable v_real_V : real;
        variable v_real_W : real;
    begin
        write(row, string'("Muestra,Tension_U,Tension_V,Tension_W,Freq_Hz"));
        writeline(file_handler, row);

        loop
            wait until rising_edge(clk);

            if fin_sim = '1' then
                file_close(file_handler);
                wait;
            end if;

            if v_decim = 0 then
                -- Conversion de Q8.24 (std_logic_vector) a REAL usando fixed_pkg
                v_real_U := to_real(to_sfixed(tension_SVM_U, INT_BITS-1, -FRAC_BITS));
                v_real_V := to_real(to_sfixed(tension_SVM_V, INT_BITS-1, -FRAC_BITS));
                v_real_W := to_real(to_sfixed(tension_SVM_W, INT_BITS-1, -FRAC_BITS));

                write(row, v_muestra_idx);          -- indice de muestra (pasos de 1 us)
                write(row, string'(","));
                write(row, v_real_U);
                write(row, string'(","));
                write(row, v_real_V);
                write(row, string'(","));
                write(row, v_real_W);
                write(row, string'(","));
                write(row, freq_hz);                -- frecuencia comandada a la salida
                writeline(file_handler, row);

                v_muestra_idx := v_muestra_idx + 1;
            end if;

            v_decim := (v_decim + 1) mod C_DECIMACION;
        end loop;
    end process gen_csv_tensiones;

    gen_w_direcciones_csv: process
        file file_w : text open write_mode is "F:\FPGA\Potencia FPGA\MatrixConverter\SW\matlab\w_direcciones_FoVar.csv";
        variable row : line;
        variable v_idx : integer := 0;
        variable v_decim : integer := 0;
        constant C_DECIMACION : integer := 10;
        variable v_bin_str : string(1 to 18);
        variable i : integer;
    begin
        write(row, string'("Muestra,Direcciones"));
        writeline(file_w, row);

        loop
            wait until rising_edge(clk);

            if fin_sim = '1' then
                file_close(file_w);
                wait;
            end if;

            if v_decim = 0 then
                -- Cadena binaria de 18 bits desde w_direcciones(17 downto 0)
                v_bin_str := (others => '0');
                for i in 0 to 17 loop
                    if w_direcciones(17 - i) = '1' then
                        v_bin_str(i+1) := '1';
                    else
                        v_bin_str(i+1) := '0';
                    end if;
                end loop;

                write(row, v_idx);
                write(row, string'(","));
                write(row, v_bin_str);
                writeline(file_w, row);

                v_idx := v_idx + 1;
            end if;

            v_decim := (v_decim + 1) mod C_DECIMACION;
        end loop;
    end process gen_w_direcciones_csv;

end Behavioral;
