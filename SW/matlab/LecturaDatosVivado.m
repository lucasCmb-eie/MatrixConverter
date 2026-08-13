%% Configuración Inicial
clear; clc; close all;

% Parámetros de simulación (Coinciden con tu VHDL)
filename = 'Clk10M_test50Hz_Simetrico.csv';
filename_dir = 'w_direcciones_log.csv';
Fs = 10e6;           % Frecuencia de muestreo: 5 MHz (Nota: 10e6 son 10 MHz, ajustar si es necesario)
Ts = 1/Fs;           % Periodo de muestreo: 100 ns

%% Importación de Datos - Tensiones
% Verificamos si existe el archivo antes de cargar
if ~isfile(filename)
    error('El archivo %s no se encuentra en el directorio actual.', filename);
end

fprintf('Leyendo archivo CSV principal... (esto puede tardar unos segundos)\n');
data = readtable(filename);

% Extracción de vectores
n_muestras = data.Muestra;
u = data.Tension_U;
v = data.Tension_V;
w = data.Tension_W;

% Generación del vector de tiempo real
t = n_muestras * Ts;

%% Importación de Datos - Direcciones
if isfile(filename_dir)
    fprintf('Leyendo archivo de direcciones...\n');
    data_dir = readtable(filename_dir);
    
    % CORRECCIÓN: Multiplicamos por Ts para que esté en segundos y no en número de muestra
    t_dir = data_dir{:, 1} * Ts; 
    direccion = data_dir{:, 2};
else
    warning('El archivo %s no se encuentra. Se omitirá su gráfica.', filename_dir);
    t_dir = [];
    direccion = [];
end

%% Grafico 1: Dominio del Tiempo (Vista General)
figure('Name', 'Salida SVM - Dominio del Tiempo', 'Color', 'w');
subplot(4,1,1);
plot(t, u, 'r', 'LineWidth', 1); hold on;
plot(t, v, 'g', 'LineWidth', 1);
plot(t, w, 'b', 'LineWidth', 1);
grid on;
legend('Fase U', 'Fase V', 'Fase W');
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Tensiones Trifásicas SVM (Simulación VHDL)');
xlim([0 max(t)]);

% Zoom a un par de ciclos para ver detalle
subplot(4,1,2);
plot(t, u, 'r', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase U (Detalle de Conmutación)');
xlim([0 max(t)]); 

subplot(4,1,3);
plot(t, v, 'g', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase V (Detalle de Conmutación)');
xlim([0 max(t)]);

subplot(4,1,4);
plot(t, w, 'b', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase W (Detalle de Conmutación)');
xlim([0 max(t)]);

%% Grafico Adicional: w_direcciones_log (Bits separados - Estilo Analizador Lógico - 9 bits)
if ~isempty(t_dir) && ~isempty(direccion)
    % Ajustamos la altura de la figura para 9 bits
    figure('Name', 'Evolución de Direcciones (Desglose por Bits)', 'Color', 'w', 'Position', [100, 100, 800, 500]);
    hold on;
    
    num_bits = 9; % Actualizado a 9 bits
    offset_step = 1.5; % Distancia vertical entre cada bit
    
    % Convertimos a entero sin signo para asegurar que bitget funcione correctamente
    dir_uint = uint32(direccion);
    
    ytick_pos = zeros(1, num_bits);
    ytick_labels = cell(1, num_bits);
    
    % Bucle para extraer y graficar cada bit desde el LSB (0) hasta el MSB (8)
    for i = 0:(num_bits-1)
        % bitget usa índice basado en 1 (por eso i+1)
        bit_val = double(bitget(dir_uint, i + 1));
        
        % Calculamos la posición base de este bit
        base_y = i * offset_step;
        
        % Graficamos el bit sumándole su posición base
        plot(t_dir, bit_val + base_y, 'b', 'LineWidth', 1.2);
        
        % Guardamos la posición para las etiquetas del eje Y
        ytick_pos(i+1) = base_y + 0.5;
        ytick_labels{i+1} = ['Bit ', num2str(i)];
    end
    
    grid on;
    xlabel('Tiempo [s]');
    
    % Ajustamos el eje Y para mostrar el nombre de cada bit
    yticks(ytick_pos);
    yticklabels(ytick_labels);
    
    title('Señal w\_direcciones\_log (8 downto 0)'); % Título actualizado
    xlim([0 max(t_dir)]);
    ylim([-0.5, (num_bits * offset_step)]);
    hold off;
end

%% Grafico 2: Análisis Espectral (FFT de Fase U)
L = length(u);
Y = fft(u);
P2 = abs(Y/L);
P1 = P2(1:floor(L/2)+1);
P1(2:end-1) = 2*P1(2:end-1);
f = Fs*(0:(L/2))/L;

figure('Name', 'Espectro de Frecuencia (Fase U)', 'Color', 'w');
plot(f, P1, 'k', 'LineWidth', 1.2);
title('Espectro de Amplitud Unilateral de u(t)');
xlabel('Frecuencia [Hz]');
ylabel('|P1(f)|');
grid on;
xlim([0 1000]);

%% 1. Definición de la Carga (Modelo RL por fase)
R = 1.2;            
L_ind = 0.012;      

s = tf('s');
G_s = 1 / (L_ind * s + R);
fprintf('Modelo de Carga: R=%.1f Ohm, L=%.1f mH\n', R, L_ind*1000);

%% 2. Discretización
G_z = c2d(G_s, Ts, 'tustin'); 

%% 3. Simulación de la respuesta (Corrientes)
fprintf('Calculando corrientes (simulando respuesta dinámica)...\n');

v_neutro = (u + v + w) / 3;
u_load = u - v_neutro;
v_load = v - v_neutro;
w_load = w - v_neutro;

i_u = lsim(G_z, u_load, t);
i_v = lsim(G_z, v_load, t);
i_w = lsim(G_z, w_load, t);

%% 4. Visualización de Resultados
figure('Name', 'Corrientes Resultantes en Carga RL', 'Color', 'w');
plot(t, i_u, 'r', 'LineWidth', 1.2); hold on;
plot(t, i_v, 'g', 'LineWidth', 1.2);
plot(t, i_w, 'b', 'LineWidth', 1.2);
grid on;
legend('i_U', 'i_V', 'i_W');
xlabel('Tiempo [s]');
ylabel('Corriente [A]');
title('Corrientes Trifásicas Filtradas por Carga RL');
xlim([0 max(t)]);

figure('Name', 'Zoom Ripple Corrientes', 'Color', 'w');
plot(t, i_u, 'r', 'LineWidth', 1.5);
grid on;
title('Zoom Corriente Fase U (Ripple de PWM visible)');
ylabel('Corriente [A]');
xlabel('Tiempo [s]');
xlim([0.07 0.072]); 

%% 5. Verificación opcional: Plano Alfa-Beta (Círculo de Clarke)
i_alpha = (2/3) * (i_u - 0.5*i_v - 0.5*i_w);
i_beta  = (2/3) * (0 + (sqrt(3)/2)*i_v - (sqrt(3)/2)*i_w);

figure('Name', 'Trayectoria Vectorial de Corriente', 'Color', 'w');
plot(i_alpha, i_beta, 'k', 'LineWidth', 1.5);
grid on; axis equal;
title('Trayectoria del Vector Espacial de Corriente (Plano \alpha\beta)');
xlabel('i_\alpha [A]');
ylabel('i_\beta [A]');

%% Grafico 6: Tensiones vs Corrientes (Figuras Individuales)
% Buscamos el factor de escala para que la corriente tenga la misma amplitud que la tensión
V_max = max([max(abs(u)), max(abs(v)), max(abs(w))]);
I_max = max([max(abs(i_u)), max(abs(i_v)), max(abs(i_w))]);
escala_I = V_max / I_max;

fprintf('Factor de escala aplicado a las corrientes para visualización: %.2f\n', escala_I);

% Fase U
figure('Name', 'Fase U: Tensión vs Corriente', 'Color', 'w', 'WindowState', 'maximized');
plot(t, u, 'r', 'LineWidth', 1.2); hold on;
plot(t, i_u * escala_I, 'k--', 'LineWidth', 1.5);
grid on;
legend('Tensión U', 'Corriente i_U (Escalada)', 'Location', 'best');
xlabel('Tiempo [s]'); ylabel('Amplitud'); title('Fase U (Tensión vs Corriente)');
xlim([0 max(t)]);

% Fase V
figure('Name', 'Fase V: Tensión vs Corriente', 'Color', 'w', 'WindowState', 'maximized');
plot(t, v, 'g', 'LineWidth', 1.2); hold on;
plot(t, i_v * escala_I, 'k--', 'LineWidth', 1.5);
grid on;
legend('Tensión V', 'Corriente i_V (Escalada)', 'Location', 'best');
xlabel('Tiempo [s]'); ylabel('Amplitud'); title('Fase V (Tensión vs Corriente)');
xlim([0 max(t)]);

% Fase W
figure('Name', 'Fase W: Tensión vs Corriente', 'Color', 'w', 'WindowState', 'maximized');
plot(t, w, 'b', 'LineWidth', 1.2); hold on;
plot(t, i_w * escala_I, 'k--', 'LineWidth', 1.5);
grid on;
legend('Tensión W', 'Corriente i_W (Escalada)', 'Location', 'best');
xlabel('Tiempo [s]'); ylabel('Amplitud'); title('Fase W (Tensión vs Corriente)');
xlim([0 max(t)]);


%% Grafico 7: Tensiones vs Bits de Dirección de la Matriz (Figuras Individuales)
if ~isempty(t_dir) && ~isempty(direccion)
    % Aseguramos variable entera para extraer bits
    dir_uint = uint32(direccion);
    % Ajustar el zoom a una ventana de 2 ms para poder ver los pulsos PWM
    t_start = 0.010; % Iniciar en 10 ms
    t_end   = 0.012; % Terminar en 12 ms
    
    % Extraemos los bits 
    b0 = double(bitget(dir_uint, 1));
    b1 = double(bitget(dir_uint, 2));
    b2 = double(bitget(dir_uint, 3));
    b3 = double(bitget(dir_uint, 4));
    b4 = double(bitget(dir_uint, 5));
    b5 = double(bitget(dir_uint, 6));
    b6 = double(bitget(dir_uint, 7));
    b7 = double(bitget(dir_uint, 8));
    b8 = double(bitget(dir_uint, 9));

    % Fase U: Bits 0, 3, 6 vs Tensión U
    figure('Name', 'Fase U y Estados de Llaves', 'Color', 'w', 'WindowState', 'maximized');
    plot(t, u, 'r', 'LineWidth', 1.5); hold on;
    plot(t_dir, b0 * V_max, 'k', 'LineWidth', 1.2);
    plot(t_dir, b3 * V_max, 'm', 'LineWidth', 1.2);
    plot(t_dir, b6 * V_max, 'c', 'LineWidth', 1.2);
    grid on;
    legend('Tensión U', 'Bit 0', 'Bit 3', 'Bit 6', 'Location', 'best');
    title('Fase U y Estados de Llaves [Bits 0, 3, 6]');
    xlabel('Tiempo [s]'); ylabel('Amplitud'); xlim([0 max(t)]);
    if max(t) > 0.04, xlim([0 0.04]); end 

    % Fase V: Bits 1, 4, 7 vs Tensión V
    figure('Name', 'Fase V y Estados de Llaves', 'Color', 'w', 'WindowState', 'maximized');
    plot(t, v, 'g', 'LineWidth', 1.5); hold on;
    plot(t_dir, b1 * V_max, 'k', 'LineWidth', 1.2);
    plot(t_dir, b4 * V_max, 'm', 'LineWidth', 1.2);
    plot(t_dir, b7 * V_max, 'c', 'LineWidth', 1.2);
    grid on;
    legend('Tensión V', 'Bit 1', 'Bit 4', 'Bit 7', 'Location', 'best');
    title('Fase V y Estados de Llaves [Bits 1, 4, 7]');
    xlabel('Tiempo [s]'); ylabel('Amplitud'); xlim([0 max(t)]);
    if max(t) > 0.04, xlim([0 0.04]); end

    % Fase W: Bits 2, 5, 8 vs Tensión W
    figure('Name', 'Fase W y Estados de Llaves', 'Color', 'w', 'WindowState', 'maximized');
    plot(t, w, 'b', 'LineWidth', 1.5); hold on;
    plot(t_dir, b2 * V_max, 'k', 'LineWidth', 1.2);
    plot(t_dir, b5 * V_max, 'm', 'LineWidth', 1.2);
    plot(t_dir, b8 * V_max, 'c', 'LineWidth', 1.2);
    grid on;
    legend('Tensión W', 'Bit 2', 'Bit 5', 'Bit 8', 'Location', 'best');
    title('Fase W y Estados de Llaves [Bits 2, 5, 8]');
    xlabel('Tiempo [s]'); ylabel('Amplitud'); xlim([0 max(t)]);
    if max(t) > 0.04, xlim([0 0.04]); end
end