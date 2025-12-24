%% Configuración Inicial
clear; clc; close all;

% Parámetros de simulación (Coinciden con tu VHDL)
filename = 'salida_100Hz_svm_Corregida.csv';
Fs = 100e6;           % Frecuencia de muestreo: 5 MHz
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

% Zoom a un par de ciclos (40ms aprox) para ver detalle
subplot(4,1,2);
plot(t, u, 'r', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase U (Detalle de Conmutación)');
xlim([0 min(0.04, max(t))]); 

% Zoom a un par de ciclos (40ms aprox) para ver detalle
subplot(4,1,3);
plot(t, v, 'g', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase V (Detalle de Conmutación)');
xlim([0 min(0.04, max(t))]); 

% Zoom a un par de ciclos (40ms aprox) para ver detalle
subplot(4,1,4);
plot(t, w, 'b', 'LineWidth', 1.2);
grid on;
xlabel('Tiempo [s]');
ylabel('Amplitud [V]');
title('Zoom Fase W (Detalle de Conmutación)');
xlim([0 max(t)]); 
% Mostramos solo los primeros 40ms o el total si es menor

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

% 1. Calcular la Tensión de Modo Común (Tensión del Neutro)
% En una carga equilibrada, el potencial del neutro es el promedio de las fases.
v_neutro = (u + v + w) / 3;

% 2. Calcular las Tensiones Fase-Neutro (Lo que realmente ve la bobina)
% Restamos la tensión de modo común a cada fase.
u_load = u - v_neutro;
v_load = v - v_neutro;
w_load = w - v_neutro;

% 3. Simular la corriente usando las tensiones corregidas
% Ahora el sistema "ve" un neutro flotante y la suma de corrientes será 0.
i_u = lsim(G_z, u, t);
i_v = lsim(G_z, v, t);
i_w = lsim(G_z, w, t);

% Verificación opcional:
% La suma i_u + i_v + i_w debería ser ahora extremadamente cercana a cero (orden de 1e-15)
sum_currents = i_u + i_v + i_w;
plot(t, sum_currents); title('Suma de corrientes (Debe ser cero)');


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