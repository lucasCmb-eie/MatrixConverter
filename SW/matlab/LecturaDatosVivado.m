%% ========================================================================
%  Analisis de la simulacion del conversor matricial (SVM)
%
%  Lee los CSV que escribe tb_SVM_Wrapper.vhd via textio y grafica:
%    - tensiones de salida crudas y su espectro
%    - corrientes en una carga RL por fase (modelo del motor)
%    - trayectoria del vector espacial en el plano alfa-beta
%    - angulo y frecuencia instantanea de rotacion del vector
%    - estados de las llaves de la matriz de conmutacion
%
%  Sin acentos a proposito: los CSV y este archivo viajan entre Vivado,
%  Windows y MATLAB y los caracteres extendidos se corrompen.
% =========================================================================

clear; clc; close all;

%% ------------------------- Parametros -----------------------------------

ARCH_TENSIONES   = 'Clk10M_60i_50o_Simetrico.csv';
ARCH_DIRECCIONES = 'w_direcciones_log.csv';

Fs = 10e6;              % muestreo del testbench: 1 muestra por flanco de clk
Ts = 1/Fs;

F_OUT = 50;             % frecuencia comandada a la salida (rampa i_al_o) [Hz]
F_IN  = 60;             % frecuencia de la fuente trifasica de entrada [Hz]

R_CARGA = 1.2;          % carga RL por fase [Ohm]
L_CARGA = 0.012;        % [H]

I_PICO_OBJETIVO = 1.0;  % pico deseado para la carga RL reescalada [A]

T_TRANSITORIO = 0.040;  % tramo inicial descartado en los graficos de regimen [s]
T_ZOOM        = 0.002;  % ancho de las ventanas de zoom [s]
F_MAX_PLOT    = 1000;   % tope del eje de frecuencia en las FFT [Hz]
VENT_SUAVIZADO = 200e-6;% ventana de movmean para matar el ripple de PWM [s]

%% ------------------------- Carga de datos -------------------------------

if ~isfile(ARCH_TENSIONES)
    error('No se encuentra %s en el directorio actual.', ARCH_TENSIONES);
end

fprintf('Leyendo %s ...\n', ARCH_TENSIONES);
datos = readtable(ARCH_TENSIONES);

u = datos.Tension_U;
v = datos.Tension_V;
w = datos.Tension_W;
t = datos.Muestra * Ts;

N = numel(t);
fprintf('  %d muestras, %.4f s simulados\n', N, t(end));

idx_ss = t >= T_TRANSITORIO;   % mascara de regimen permanente

%% ------------------------- Tensiones de salida --------------------------

figure('Name', 'Tensiones de salida del SVM', 'Color', 'w');

subplot(2,1,1);
plot(t, u, 'r', t, v, 'g', t, w, 'b');
grid on; legend('U','V','W'); xlim([0 t(end)]);
xlabel('Tiempo [s]'); ylabel('Amplitud [V]');
title('Tensiones trifasicas a la salida de la matriz (crudas, conmutadas)');

t0 = T_TRANSITORIO;
subplot(2,1,2);
plot(t, u, 'r', t, v, 'g', t, w, 'b');
grid on; legend('U','V','W'); xlim([t0 t0+T_ZOOM]);
xlabel('Tiempo [s]'); ylabel('Amplitud [V]');
title(sprintf('Zoom de %g ms: detalle de conmutacion', T_ZOOM*1e3));

[f_v, P_u] = espectro(u, Fs);

figure('Name', 'Espectro de la tension U', 'Color', 'w');
plot(f_v, P_u, 'k'); grid on; xlim([0 F_MAX_PLOT]);
xlabel('Frecuencia [Hz]'); ylabel('|P1(f)|');
title('Espectro de amplitud unilateral de u(t) (con modo comun)');

%% ------------------------- Corrientes en la carga RL --------------------
% La carga es una estrella de neutro flotante, asi que no ve el modo comun.
% Restarlo es parte del modelo, no un artificio de graficado.

v_neutro = (u + v + w) / 3;
u_carga  = u - v_neutro;
v_carga  = v - v_neutro;
w_carga  = w - v_neutro;

fprintf('Simulando carga RL: R = %.2f Ohm, L = %.1f mH ...\n', R_CARGA, L_CARGA*1e3);
[i_u, i_v, i_w] = filtrar_RL(u_carga, v_carga, w_carga, R_CARGA, L_CARGA, t, Ts);

figure('Name', 'Corrientes en la carga RL', 'Color', 'w');
subplot(2,1,1);
plot(t, i_u, 'r', t, i_v, 'g', t, i_w, 'b');
grid on; legend('i_U','i_V','i_W'); xlim([0 t(end)]);
xlabel('Tiempo [s]'); ylabel('Corriente [A]');
title('Corrientes trifasicas filtradas por la carga RL');

subplot(2,1,2);
plot(t, i_u, 'r', t, i_v, 'g', t, i_w, 'b');
grid on; legend('i_U','i_V','i_W'); xlim([t0 t0+10*T_ZOOM]);
xlabel('Tiempo [s]'); ylabel('Corriente [A]');
title('Zoom: ripple de PWM sobre la corriente');

[f_i, P_iu] = espectro(i_u, Fs);

figure('Name', 'Espectro de la corriente U', 'Color', 'w');
plot(f_i, P_iu, 'k'); grid on; xlim([0 F_MAX_PLOT]);
xlabel('Frecuencia [Hz]'); ylabel('|P1(f)|');
title('Espectro de amplitud unilateral de i_u(t)');

%% ------------------------- Carga RL reescalada a 1 A --------------------
% Se escalan R y L por el mismo factor, asi que R/L (y con el la constante
% de tiempo y el filtrado de armonicos) no cambia: la forma de onda es
% identica y solo cambia la ganancia. Se muestran los valores equivalentes
% por si conviene dimensionar la carga real de esa manera.

i_pico = max([max(abs(i_u(idx_ss))), max(abs(i_v(idx_ss))), max(abs(i_w(idx_ss)))]);
k_esc  = I_PICO_OBJETIVO / i_pico;

R_1A = R_CARGA / k_esc;
L_1A = L_CARGA / k_esc;

fprintf('Carga equivalente para %.1f A de pico: R = %.4f Ohm, L = %.2f mH\n', ...
        I_PICO_OBJETIVO, R_1A, L_1A*1e3);

figure('Name', 'Corrientes RL escaladas a 1 A de pico', 'Color', 'w');
h_fases = plot(t, i_u*k_esc, 'r', t, i_v*k_esc, 'g', t, i_w*k_esc, 'b');
grid on; xlim([0 t(end)]);
linea_horizontal( I_PICO_OBJETIVO, 'k--', 1.0);
linea_horizontal(-I_PICO_OBJETIVO, 'k--', 1.0);
% legend despues de las lineas de referencia y con handles explicitos, para que
% no aparezcan como 'data1'/'data2' ni se desalineen los colores
legend(h_fases, 'i_U', 'i_V', 'i_W');
xlabel('Tiempo [s]'); ylabel('Corriente [A]');
title(sprintf('Corrientes con carga R = %.3f Ohm, L = %.2f mH (pico = %.1f A)', ...
              R_1A, L_1A*1e3, I_PICO_OBJETIVO));

%% ------------------------- Vector espacial de corriente -----------------

i_alfa = (2/3) * (i_u - 0.5*i_v - 0.5*i_w);
i_beta = (1/sqrt(3)) * (i_v - i_w);

i_mod = hypot(i_alfa, i_beta);

% Radio de referencia: amplitud de la componente fundamental de i_u
[~, k_out] = min(abs(f_i - F_OUT));
r_ref = P_iu(k_out);

% --- Trayectoria completa (incluye el transitorio de arranque) -----------
figure('Name', 'Trayectoria del vector de corriente', 'Color', 'w');

subplot(1,2,1);
plot(i_alfa, i_beta, 'k'); grid on; axis equal;
xlabel('i_\alpha [A]'); ylabel('i_\beta [A]');
title('Completa (incluye el transitorio de arranque)');

% --- Trayectoria en regimen, con circulo de referencia ------------------
subplot(1,2,2);
plot(i_alfa(idx_ss), i_beta(idx_ss), 'k'); hold on;
ang = linspace(0, 2*pi, 512);
plot(r_ref*cos(ang), r_ref*sin(ang), 'r--', 'LineWidth', 1.5);
grid on; axis equal; hold off;
legend('Trayectoria', sprintf('Circulo de referencia (%.4f A)', r_ref), ...
       'Location', 'southoutside');
xlabel('i_\alpha [A]'); ylabel('i_\beta [A]');
title(sprintf('Regimen (t > %g ms)', T_TRANSITORIO*1e3));

% --- Modulo del vector contra el tiempo ---------------------------------
% Aca se lee directo lo que en el plano alfa-beta aparece como grosor del
% anillo: si el modulo no es constante, hay batido con la entrada.

vent = round(VENT_SUAVIZADO / Ts);
i_mod_suave = movmean(i_mod, vent);

mod_med = mean(i_mod(idx_ss));
mod_min = min(i_mod_suave(idx_ss));
mod_max = max(i_mod_suave(idx_ss));
rizado  = 100 * (mod_max - mod_min) / (2*mod_med);

figure('Name', 'Modulo del vector de corriente', 'Color', 'w');
plot(t, i_mod, 'Color', [0.75 0.75 0.75]); hold on;
plot(t, i_mod_suave, 'k', 'LineWidth', 1.4);
xlim([0 t(end)]);
linea_horizontal(mod_med, 'r--', 1.2);
grid on; hold off;
legend('|i| instantaneo', '|i| suavizado', 'Media en regimen', 'Location','best');
xlabel('Tiempo [s]'); ylabel('|i| [A]');
title(sprintf(['Modulo del vector de corriente  -  rizado +/-%.1f%% ' ...
               '(batido esperado a %g Hz = |f_{in} - f_{out}|)'], ...
               rizado, abs(F_IN - F_OUT)));

%% ------------------------- Angulo y frecuencia de rotacion --------------

theta_i = movmean(unwrap(atan2(i_beta, i_alfa)), vent);
f_inst  = [0; diff(theta_i)] / (2*pi) * Fs;

% Pendiente media en regimen: la frecuencia de rotacion real
p = polyfit(t(idx_ss), theta_i(idx_ss), 1);
f_medida = p(1) / (2*pi);

figure('Name', 'Angulo y frecuencia del vector de corriente', 'Color', 'w');

subplot(2,1,1);
plot(t, theta_i, 'k', 'LineWidth', 1.2); grid on;
xlabel('Tiempo [s]'); ylabel('Angulo [rad]');
title(sprintf('Angulo desenrollado  -  pendiente en regimen = %.2f Hz (comandado %g Hz)', ...
              f_medida, F_OUT));

subplot(2,1,2);
plot(t, f_inst, 'k'); grid on;
xlim([0 t(end)]);
linea_horizontal(F_OUT, 'r--', 1.2);
xlabel('Tiempo [s]'); ylabel('Frecuencia [Hz]');
ylim([-20 100]);
title('Frecuencia de rotacion instantanea (suavizada)');

%% ------------------------- Resumen numerico -----------------------------
% Lo que en los graficos se ve a ojo, medido.

fprintf('\n--- Contenido espectral de la tension de salida (sin modo comun) ---\n');
frecs = unique([0, abs(F_IN-F_OUT), F_OUT, F_IN, F_IN+F_OUT, 2*F_OUT, 3*F_OUT]);
[~, P_ul] = espectro(u_carga, Fs);
fprintf('  DC          : %+.6f\n', mean(u_carga));
for fr = frecs(frecs > 0)
    [~, kk] = min(abs(f_v - fr));
    fprintf('  %7.1f Hz  : %.4f\n', fr, P_ul(kk));
end
fprintf('  Frecuencia de rotacion medida: %.2f Hz (comandada %g Hz)\n', f_medida, F_OUT);

%% ------------------------- Estados de las llaves ------------------------
% La columna del CSV es una cadena binaria de 18 bits, pero readtable la
% interpreta como un numero decimal cuyos digitos SON los bits. Como
% o_direcciones(17 downto 9) esta cableado a cero, el valor nunca pasa de
% 111111111 (~1.1e8) y entra exacto en un double, asi que se pueden extraer
% los digitos con aritmetica. (Usar bitget sobre ese numero, como se hacia
% antes, da basura: mezcla los bits de la representacion decimal.)

if isfile(ARCH_DIRECCIONES)
    fprintf('\nLeyendo %s ...\n', ARCH_DIRECCIONES);
    datos_dir = readtable(ARCH_DIRECCIONES);
    t_dir     = datos_dir{:,1} * Ts;
    palabra   = datos_dir{:,2};
    if ~isnumeric(palabra)   % por si readtable la detecta como texto
        palabra = str2double(string(palabra));
    end

    assert(max(palabra) < 1e9, ...
        'La palabra excede 9 digitos: los bits altos de o_direcciones ya no son cero.');

    % bits(:,k) = digito k-1 (bit 0 = LSB en la columna 1)
    bits = mod(floor(palabra ./ 10.^(0:8)), 10);

    % Formato de la palabra (ver matrixConmut.vhd):
    %   bits 8..6 = fila de salida U <- [U V W]
    %   bits 5..3 = fila de salida V <- [U V W]
    %   bits 2..0 = fila de salida W <- [U V W]
    salidas  = {'U','V','W'};
    entradas = {'U','V','W'};
    etiquetas = cell(1,9);
    for b = 0:8
        fila = salidas{3 - floor(b/3)};
        col  = entradas{3 - mod(b,3)};
        etiquetas{b+1} = sprintf('%s <- %s', fila, col);
    end

    figure('Name', 'Estados de la matriz de conmutacion', 'Color', 'w');
    hold on;
    paso = 1.5;
    for b = 0:8
        plot(t_dir, bits(:,b+1) + b*paso, 'b');
    end
    grid on; hold off;
    yticks((0:8)*paso + 0.5);
    yticklabels(etiquetas);
    xlim([t0 t0+T_ZOOM]);
    ylim([-0.5, 9*paso]);
    xlabel('Tiempo [s]');
    title(sprintf('Llaves cerradas de la matriz 3x3 (zoom de %g ms)', T_ZOOM*1e3));
else
    warning('No se encuentra %s. Se omite el grafico de llaves.', ARCH_DIRECCIONES);
end

%% ------------------------- Funciones locales ----------------------------

function h = linea_horizontal(y, estilo, ancho)
    % Reemplazo de yline(), que recien existe desde R2018b
    lim = xlim;
    estaba_hold = ishold;
    hold on;
    h = plot(lim, [y y], estilo, 'LineWidth', ancho);
    xlim(lim);
    if ~estaba_hold
        hold off;
    end
end

function [f, P1] = espectro(x, Fs)
    % Espectro de amplitud unilateral
    n  = numel(x);
    Y  = fft(x);
    P2 = abs(Y/n);
    P1 = P2(1:floor(n/2)+1);
    P1(2:end-1) = 2*P1(2:end-1);
    f  = Fs*(0:floor(n/2))'/n;
end

function [iu, iv, iw] = filtrar_RL(vu, vv, vw, R, L, t, Ts)
    % Respuesta de una carga RL serie por fase, discretizada por Tustin
    G_z = c2d(tf(1, [L R]), Ts, 'tustin');
    iu = lsim(G_z, vu, t);
    iv = lsim(G_z, vv, t);
    iw = lsim(G_z, vw, t);
end
