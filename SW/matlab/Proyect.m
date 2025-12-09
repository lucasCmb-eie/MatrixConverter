clc, clear;
s = tf('s');
syms z
T=1/5e6;
L=0.012;
R=1.2;
Ys=1/(s*L+R);
Yz=c2d(Ys,T,'tustin');
Yfrr=recadel(Ys, 1e-8);

% Definir la función de transferencia
num = [0.004146 0.004146];
den = [1 -0.99];

% Periodo de muestreo (asumiendo Ts = 0.001 s, ajusta según tu sistema)
Ts = 100e-6;  % 1 ms
H = tf(num, den, Ts);

% Parámetros de las señales trifásicas
f = 100;  % Frecuencia en Hz
A = 1;   % Amplitud
t = 0:Ts:2;  % Vector de tiempo (1 segundo)

% Generar señales trifásicas de entrada (desfasadas 120°)
x_a = A * sin(2*pi*f*t);                    % Fase A (0°)
x_b = A * sin(2*pi*f*t - 2*pi/3);          % Fase B (-120°)
x_c = A * sin(2*pi*f*t - 4*pi/3);          % Fase C (-240° o +120°)

% Calcular la respuesta del sistema para cada fase
y_a = lsim(H, x_a, t);
y_b = lsim(H, x_b, t);
y_c = lsim(H, x_c, t);

% Visualización - Sistema Trifásico
figure('Position', [100 100 1400 900]);

% Subplot 1: Señales de entrada trifásicas
subplot(4,1,1);
plot(t, x_a, 'r', 'LineWidth', 1.5, 'DisplayName', 'Fase A (0°)');
hold on;
plot(t, x_b, 'g', 'LineWidth', 1.5, 'DisplayName', 'Fase B (-120°)');
plot(t, x_c, 'b', 'LineWidth', 1.5, 'DisplayName', 'Fase C (-240°)');
grid on;
xlabel('Tiempo (s)');
ylabel('Amplitud');
title('Señales de Entrada Trifásicas: 50 Hz con desfase de 120°');
legend('Location', 'best');
xlim([0 0.08]);  % Mostrar 80 ms para ver ~4 ciclos

% Subplot 2: Señales de salida trifásicas
subplot(4,1,2);
plot(t, y_a, 'r', 'LineWidth', 1.5, 'DisplayName', 'Salida Fase A');
hold on;
plot(t, y_b, 'g', 'LineWidth', 1.5, 'DisplayName', 'Salida Fase B');
plot(t, y_c, 'b', 'LineWidth', 1.5, 'DisplayName', 'Salida Fase C');
grid on;
xlabel('Tiempo (s)');
ylabel('Amplitud');
title('Señales de Salida del Sistema (Trifásicas)');
legend('Location', 'best');
xlim([0 0.08]);

% Subplot 3: Comparación Fase A
subplot(4,1,3);
plot(t, x_a, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Entrada A');
hold on;
plot(t, y_a, 'r', 'LineWidth', 1.5, 'DisplayName', 'Salida A');
grid on;
xlabel('Tiempo (s)');
ylabel('Amplitud');
title('Comparación Fase A: Entrada vs Salida');
legend('Location', 'best');
xlim([0 0.08]);

% Subplot 4: Todas las fases juntas (entrada y salida)
subplot(4,1,4);
plot(t, x_a, 'r--', 'LineWidth', 1, 'DisplayName', 'Entrada A');
hold on;
plot(t, x_b, 'g--', 'LineWidth', 1, 'DisplayName', 'Entrada B');
plot(t, x_c, 'b--', 'LineWidth', 1, 'DisplayName', 'Entrada C');
plot(t, y_a, 'r', 'LineWidth', 1.5, 'DisplayName', 'Salida A');
plot(t, y_b, 'g', 'LineWidth', 1.5, 'DisplayName', 'Salida B');
plot(t, y_c, 'b', 'LineWidth', 1.5, 'DisplayName', 'Salida C');
grid on;
xlabel('Tiempo (s)');
ylabel('Amplitud');
title('Comparación Global: Todas las Fases');
legend('Location', 'eastoutside');
xlim([0 0.08]);

% Análisis en frecuencia
figure('Position', [100 100 1200 400]);

% Respuesta en frecuencia
subplot(1,2,1);
bode(H);
grid on;
title('Diagrama de Bode del Sistema');

% Evaluar ganancia y fase a 50 Hz
w = 2*pi*f;  % Frecuencia angular en rad/s
[mag, phase] = bode(H, w);
mag_dB = 20*log10(mag);

subplot(1,2,2);
text(0.1, 0.8, sprintf('Análisis a f = 50 Hz:'), 'FontSize', 12, 'FontWeight', 'bold');
text(0.1, 0.6, sprintf('Ganancia: %.4f (%.2f dB)', mag, mag_dB), 'FontSize', 11);
text(0.1, 0.4, sprintf('Fase: %.2f°', phase), 'FontSize', 11);
text(0.1, 0.2, sprintf('Periodo de muestreo: %.4f s', Ts), 'FontSize', 11);
axis off;

fprintf('\n=== SISTEMA TRIFÁSICO - ANÁLISIS ===\n');
fprintf('Frecuencia: 50 Hz\n');
fprintf('Desfase entre fases: 120°\n\n');

fprintf('=== ECUACIÓN EN DIFERENCIAS ===\n');
fprintf('y[n] = %.6f*x[n] + %.6f*x[n-1] + %.4f*y[n-1]\n\n', ...
    num(1)/den(1), num(2)/den(1), -den(2)/den(1));

fprintf('=== RESPUESTA DEL SISTEMA A 50 Hz ===\n');
fprintf('Ganancia: %.6f (%.2f dB)\n', mag, mag_dB);
fprintf('Fase: %.2f°\n', phase);
fprintf('Atenuación: %.2f%%\n\n', (1-mag)*100);

fprintf('=== AMPLITUDES MÁXIMAS ===\n');
fprintf('Entrada Fase A: %.4f\n', max(abs(x_a)));
fprintf('Salida Fase A:  %.4f\n', max(abs(y_a(end-1000:end))));
fprintf('Entrada Fase B: %.4f\n', max(abs(x_b)));
fprintf('Salida Fase B:  %.4f\n', max(abs(y_b(end-1000:end))));
fprintf('Entrada Fase C: %.4f\n', max(abs(x_c)));
fprintf('Salida Fase C:  %.4f\n\n', max(abs(y_c(end-1000:end))));

fprintf('Nota: Las tres fases mantienen el desfase de 120° a la salida\n');