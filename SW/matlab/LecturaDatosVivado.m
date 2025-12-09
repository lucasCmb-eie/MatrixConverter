%% Configuración Inicial
clear; clc; close all;

% Parámetros de simulación (Coinciden con tu VHDL)
filename = 'salida_svm_5MHz.csv';
Fs = 5e6;           % Frecuencia de muestreo: 5 MHz
Ts = 1/Fs;          % Periodo de muestreo: 200 ns

%% Importación de Datos
% Verificamos si existe el archivo antes de cargar
if ~isfile(filename)
    error('El archivo %s no se encuentra en el directorio actual.', filename);
end

fprintf('Leyendo archivo CSV... (esto puede tardar unos segundos)\n');
data = readtable(filename);

% Extracción de vectores
n_muestras = data.Muestra;
u = data.Tension_U;
v = data.Tension_V;
w = data.Tension_W;

% Generación del vector de tiempo real
t = n_muestras * Ts;

%% Grafico 1: Dominio del Tiempo (Vista General)
figure('Name', 'Salida SVM - Dominio del Tiempo', 'Color', 'w');
subplot(2,1,1);
plot(t, u, 'r', 'LineWidth', 1); hold on;
plot(t, v, 'g', 'LineWidth', 1);
plot(t, w, 'b', 'LineWidth', 1);
grid on;
legend('Fase U', 'Fase V', 'Fase W');
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Tensiones Trifásicas SVM (Simulación VHDL)');
xlim([0 max(t)]);

% Zoom a un par de ciclos (40ms aprox) para ver detalle
subplot(2,1,2);
plot(t, u, 'r', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase U (Detalle de Conmutación)');
% Mostramos solo los primeros 40ms o el total si es menor
xlim([0 min(0.04, max(t))]); 

%% Grafico 2: Análisis Espectral (FFT de Fase U)
% Útil para validar la fundamental de 50Hz y ver armónicos
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

% Hacemos zoom en bajas frecuencias para ver la fundamental (50Hz)
xlim([0 1000]);

%% 1. Definición de la Carga (Modelo RL por fase)
% Valores ejemplo de un motor pequeño o carga de prueba
R = 1.2;            % Resistencia en Ohms
L_ind = 0.012;      % Inductancia en Henrys (12 mH)

% Función de Transferencia Continua G(s) = I(s)/V(s) = 1/(Ls + R)
s = tf('s');
G_s = 1 / (L_ind * s + R);

fprintf('Modelo de Carga: R=%.1f Ohm, L=%.1f mH\n', R, L_ind*1000);

%% 2. Discretización
% Es CRUCIAL usar el mismo tiempo de muestreo que tus datos (200ns)
% Ts ya fue definido arriba como 1/Fs (aprox 2e-7 segundos)
G_z = c2d(G_s, Ts, 'tustin'); % Método Tustin (bilineal) recomendado

%% 3. Simulación de la respuesta (Corrientes)
% Usamos lsim para aplicar las tensiones grabadas al sistema
fprintf('Calculando corrientes (simulando respuesta dinámica)...\n');

% Como lsim toma (sistema, entrada, tiempo), calculamos para cada fase
% Nota: Asumimos carga en estrella equilibrada con neutro conectado para simplificar
% (Si no hay neutro, se usarían tensiones de línea, pero esto es una buena aproximación inicial)
i_u = lsim(G_z, u, t);
i_v = lsim(G_z, v, t);
i_w = lsim(G_z, w, t);

%% 4. Visualización de Resultados
figure('Name', 'Corrientes Resultantes en Carga RL', 'Color', 'w');

% Plot de las corrientes
subplot(2,1,1);
plot(t, i_u, 'r', 'LineWidth', 1.2); hold on;
plot(t, i_v, 'g', 'LineWidth', 1.2);
plot(t, i_w, 'b', 'LineWidth', 1.2);
grid on;
legend('i_U', 'i_V', 'i_W');
xlabel('Tiempo [s]');
ylabel('Corriente [A]');
title('Corrientes Trifásicas Filtradas por Carga RL');
xlim([0 max(t)]);

% Zoom para ver el rizado (ripple) de corriente debido al PWM
subplot(2,1,2);
plot(t, i_u, 'r', 'LineWidth', 1.5);
grid on;
title('Zoom Corriente Fase U (Ripple de PWM visible)');
ylabel('Corriente [A]');
xlabel('Tiempo [s]');
% Hacemos zoom en una zona donde la corriente sea alta (ej: 10ms a 12ms)
xlim([0.01 0.012]); 

%% 5. Verificación opcional: Plano Alfa-Beta (Círculo de Clarke)
% Transformada de Clarke manual para ver la trayectoria del vector corriente
i_alpha = (2/3) * (i_u - 0.5*i_v - 0.5*i_w);
i_beta  = (2/3) * (0 + (sqrt(3)/2)*i_v - (sqrt(3)/2)*i_w);

figure('Name', 'Trayectoria Vectorial de Corriente', 'Color', 'w');
plot(i_alpha, i_beta, 'k', 'LineWidth', 1.5);
grid on; axis equal;
title('Trayectoria del Vector Espacial de Corriente (Plano \alpha\beta)');
xlabel('i_\alpha [A]');
ylabel('i_\beta [A]');