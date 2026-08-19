%% ========================================================================
%  Analisis del barrido de frecuencia de ENTRADA (tb_SVM_FinVar)
%
%  Testbench: frecuencia deseada de salida (rampa i_al_o) FIJA en 50 Hz, y
%  fuente trifasica de entrada en escalones de 40, 50 y 60 Hz, 0,2 s cada uno.
%
%  Lo que se busca contestar: la salida NO se mueve cuando se corre la red de
%  entrada (es el modo de falla que ya aparecio una vez), y cuanto crecen las
%  bandas de intermodulacion al alejarse f_in de f_out.
%
%  Los escalones se detectan con la columna Freq_Hz del CSV (que aca es la
%  frecuencia de ENTRADA), no con tiempos hardcodeados.
%
%  Sin acentos a proposito: los CSV y este archivo viajan entre Vivado,
%  Windows y MATLAB y los caracteres extendidos se corrompen.
% =========================================================================

clear; clc; close all;

%% ------------------------- Parametros -----------------------------------

ARCH_TENSIONES   = 'Clk10M_FiVar_50o.csv';
ARCH_DIRECCIONES = 'w_direcciones_FiVar.csv';

Fs = 1e6;               % muestreo del testbench: 1 de cada 10 flancos de clk
Ts = 1/Fs;

F_OUT = 50;             % referencia comandada a la salida, FIJA en este testbench [Hz]
                        % las de entrada salen de la columna Freq_Hz

R_CARGA = 1.2;          % carga RL por fase [Ohm]
L_CARGA = 0.012;        % [H]

T_TRANSITORIO = 0.040;  % tramo descartado al medir la rotacion del 1er escalon [s]
T_ZOOM        = 0.002;  % ancho de las ventanas de zoom [s]
F_MAX_PLOT    = 1000;   % tope del eje de frecuencia en las FFT [Hz]
F_RESIDUO     = 1000;   % tope para el calculo de residuo espectral [Hz]
VENT_SUAVIZADO = 200e-6;% ventana de movmean para matar el ripple de PWM [s]

T_VENTANA_FFT = 0.2;    % ventana de FFT por escalon [s] -> bines de 5 Hz.
                        % Todo producto m*f_in + n*f_out es multiplo de 10 Hz
                        % y cae exacto en un bin; los multiplos IMPARES de
                        % 5 Hz no pueden tener senal real y sirven de piso.

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

if ~ismember('Freq_Hz', datos.Properties.VariableNames)
    error(['El CSV no tiene columna Freq_Hz. Este script espera la salida de ' ...
           'tb_SVM_FinVar.vhd, no la de tb_SVM_Wrapper.vhd.']);
end
f_cmd = datos.Freq_Hz;   % frecuencia de la fuente de ENTRADA

N = numel(t);
fprintf('  %d muestras, %.4f s simulados\n', N, t(end));

% La carga es una estrella de neutro flotante, asi que no ve el modo comun.
% Restarlo es parte del modelo, no un artificio de graficado.
v_neutro = (u + v + w) / 3;
u_carga  = u - v_neutro;
v_carga  = v - v_neutro;
w_carga  = w - v_neutro;

%% ------------------------- Deteccion de escalones -----------------------

lim   = [1; find(diff(f_cmd) ~= 0) + 1; N+1];
n_esc = numel(lim) - 1;

fprintf('\nEscalones detectados: %d\n', n_esc);
for k = 1:n_esc
    idx = lim(k):lim(k+1)-1;
    fprintf('  %d) f_in = %3d Hz   t = [%.4f  %.4f] s   (%d muestras)\n', ...
            k, f_cmd(idx(1)), t(idx(1)), t(idx(end)), numel(idx));
end

%% ------------------------- Panorama temporal ----------------------------

figure('Name', 'Barrido de f_in: tensiones de salida', 'Color', 'w');

subplot(3,1,1);
plot(t, u, 'r', t, v, 'g', t, w, 'b');
grid on; xlim([0 t(end)]);
marcar_escalones(t, lim);
legend('U','V','W');
xlabel('Tiempo [s]'); ylabel('Amplitud [V]');
title('Tensiones a la salida de la matriz (crudas, conmutadas)');

subplot(3,1,2);
plot(t, u_carga, 'r');
grid on; xlim([0 t(end)]);
marcar_escalones(t, lim);
xlabel('Tiempo [s]'); ylabel('Amplitud [V]');
title('Fase U sin modo comun (lo que ve la carga en estrella)');

subplot(3,1,3);
stairs(t, f_cmd, 'k', 'LineWidth', 1.4);
grid on; xlim([0 t(end)]); ylim([min(f_cmd)-5 max(f_cmd)+5]);
xlabel('Tiempo [s]'); ylabel('f_{in} [Hz]');
title(sprintf('Frecuencia de la fuente de entrada (salida fija en %g Hz)', F_OUT));

%% ------------------------- Corrientes en la carga RL --------------------
% Solo para visualizacion. Las mediciones espectrales se hacen sobre la
% TENSION: el modelo RL arranca de cero y su transitorio de tau = L/R deja
% una falda de baja frecuencia que contamina los bines de pocas decenas de Hz.

fprintf('\nSimulando carga RL: R = %.2f Ohm, L = %.1f mH ...\n', R_CARGA, L_CARGA*1e3);
[i_u, i_v, i_w] = filtrar_RL(u_carga, v_carga, w_carga, R_CARGA, L_CARGA, t, Ts);

figure('Name', 'Barrido de f_in: corrientes en la carga RL', 'Color', 'w');
plot(t, i_u, 'r', t, i_v, 'g', t, i_w, 'b');
grid on; xlim([0 t(end)]);
marcar_escalones(t, lim);
legend('i_U','i_V','i_W');
xlabel('Tiempo [s]'); ylabel('Corriente [A]');
title(sprintf(['Corrientes con R = %.2f Ohm, L = %.1f mH  -  la frecuencia debe ' ...
               'quedarse en %g Hz en los tres escalones'], ...
               R_CARGA, L_CARGA*1e3, F_OUT));

%% ------------------------- Analisis por escalon -------------------------

vent = round(VENT_SUAVIZADO / Ts);

% Vector espacial de TENSION, suavizado a una ventana de conmutacion. Sirve
% para medir la frecuencia de rotacion sin el transitorio de arranque que
% tendria el vector de corriente del modelo RL.
v_alfa = (2/3) * (u_carga - 0.5*v_carga - 0.5*w_carga);
v_beta = (1/sqrt(3)) * (v_carga - w_carga);
v_alfa_s = movmean(v_alfa, vent);
v_beta_s = movmean(v_beta, vent);
theta_v  = unwrap(atan2(v_beta_s, v_alfa_s));

f_entrada   = zeros(n_esc,1);
f_medida    = zeros(n_esc,1);
amp_fund    = zeros(n_esc,1);
residuo_pct = zeros(n_esc,1);

n_fft = round(T_VENTANA_FFT * Fs);

figure('Name', 'Barrido de f_in: espectros por escalon', 'Color', 'w');

for k = 1:n_esc

    idx  = lim(k):lim(k+1)-1;
    F_IN = f_cmd(idx(1));
    f_entrada(k) = F_IN;

    % --- Frecuencia de rotacion medida --------------------------------
    % Se descartan los bordes: 'vent' muestras que ensucia el movmean y,
    % en el primer escalon, el arranque del modulador.
    guarda = vent;
    if k == 1
        guarda = max(vent, round(T_TRANSITORIO / Ts));
    end
    idx_rot = idx(1+guarda : end-vent);
    p = polyfit(t(idx_rot), theta_v(idx_rot), 1);
    f_medida(k) = p(1) / (2*pi);

    % --- Espectro sobre una ventana entera de T_VENTANA_FFT ------------
    n_win = floor(numel(idx) / n_fft) * n_fft;
    if n_win < n_fft
        warning(['Escalon %d: solo %d muestras, menos que la ventana de FFT ' ...
                 'de %d. Se usa el escalon completo y los bines dejan de caer ' ...
                 'exactos sobre los productos de 10 Hz.'], k, numel(idx), n_fft);
        n_win = numel(idx);
    end
    idx_fft = idx(1:n_win);
    [f_v, P_u] = espectro(u_carga(idx_fft), Fs);
    df = f_v(2) - f_v(1);

    % --- Bandas de interes ---------------------------------------------
    % El fundamental va primero: todo se reporta relativo a el. En el
    % escalon de f_in = f_out las bandas de intermodulacion degeneran
    % (|f_in - f_out| cae en DC y 2*f_in - f_out sobre el fundamental);
    % el lazo de abajo las saltea avisando.
    bandas = { ...
        'fundamental f_out',     F_OUT; ...
        '|f_in - f_out|',        abs(F_IN - F_OUT); ...
        '2*f_in - f_out',        2*F_IN - F_OUT; ...
        '2*f_in + f_out',        2*F_IN + F_OUT; ...
        '5*f_out',               5*F_OUT; ...
        '7*f_out',               7*F_OUT};

    amp_fund(k) = nivel(f_v, P_u, F_OUT);

    fprintf('\n--- Escalon %d/%d : f_in = %g Hz (f_out comandada = %g Hz) ---\n', ...
            k, n_esc, F_IN, F_OUT);
    fprintf('  Ventana de FFT: %.3f s -> bines de %.2f Hz\n', n_win*Ts, df);
    fprintf('  Rotacion medida del vector de tension: %.3f Hz  (error %+.3f Hz)\n', ...
            f_medida(k), f_medida(k) - F_OUT);
    fprintf('  Fundamental: %.6f\n', amp_fund(k));
    fprintf('  %-18s %9s %9s %10s %10s\n', 'banda', 'f [Hz]', 'nivel', '% fund', 'piso %');

    vistas = [];
    for b = 1:size(bandas,1)
        nom = bandas{b,1};
        fb  = bandas{b,2};

        if fb <= 0
            fprintf('  %-18s %9.1f      cae en DC, se saltea\n', nom, fb);
            continue;
        end
        if fb > Fs/2
            continue;
        end
        if b > 1 && any(abs(vistas - fb) < df/2)
            fprintf('  %-18s %9.1f      colisiona con una banda ya listada, se saltea\n', ...
                    nom, fb);
            continue;
        end
        vistas(end+1) = fb; %#ok<SAGROW>

        Pb = nivel(f_v, P_u, fb);
        % Control: +5 Hz cae en un multiplo IMPAR de 5 Hz, donde no puede
        % haber senal real. Mide el piso de fuga local.
        Pc = nivel(f_v, P_u, fb + 5);

        fprintf('  %-18s %9.1f %9.6f %9.2f %9.2f\n', ...
                nom, fb, Pb, 100*Pb/amp_fund(k), 100*Pc/amp_fund(k));
    end

    % --- Residuo espectral por debajo de F_RESIDUO ----------------------
    sel = f_v > 0 & f_v <= F_RESIDUO;
    k_f = abs(f_v - F_OUT) < df/2;
    residuo_pct(k) = 100 * sqrt(sum(P_u(sel & ~k_f).^2)) / amp_fund(k);
    fprintf('  Residuo por debajo de %g Hz: %.2f %% del fundamental\n', ...
            F_RESIDUO, residuo_pct(k));

    % --- Grafico --------------------------------------------------------
    subplot(n_esc, 1, k);
    plot(f_v, P_u, 'k'); grid on; xlim([0 F_MAX_PLOT]);
    hold on;
    plot(F_OUT, amp_fund(k), 'ro', 'MarkerSize', 8, 'LineWidth', 1.2);
    hold off;
    xlabel('Frecuencia [Hz]'); ylabel('|P1(f)|');
    title(sprintf('Escalon %d: f_{in} = %g Hz, f_{out} medida %.2f Hz, residuo < %g Hz = %.2f %%', ...
                  k, F_IN, f_medida(k), F_RESIDUO, residuo_pct(k)));
end

%% ------------------------- Inmunidad a la frecuencia de entrada ---------
% El resultado central de este testbench: la salida NO tiene que moverse.

figure('Name', 'Barrido de f_in: inmunidad de la salida', 'Color', 'w');

subplot(1,2,1);
plot(f_entrada, f_medida, 'bo-', 'LineWidth', 1.4, 'MarkerFaceColor', 'b');
grid on;
xlim([min(f_entrada)-5, max(f_entrada)+5]);
linea_horizontal(F_OUT, 'k--', 1.2);
ylim([F_OUT-5, F_OUT+5]);
legend('f_{out} medida', sprintf('Comandada (%g Hz)', F_OUT), 'Location', 'best');
xlabel('f_{in} de la fuente [Hz]'); ylabel('f_{out} medida [Hz]');
title('La salida no debe seguir a la entrada');

subplot(1,2,2);
bar(f_entrada, residuo_pct, 0.5);
grid on;
xlabel('f_{in} de la fuente [Hz]'); ylabel('Residuo [%]');
title(sprintf('Residuo espectral por debajo de %g Hz', F_RESIDUO));

fprintf('\n--- Resumen del barrido ---\n');
fprintf('  %10s %12s %12s %12s %12s\n', ...
        'f_in [Hz]', 'f_out med', 'error [Hz]', 'fundamental', 'residuo [%]');
for k = 1:n_esc
    fprintf('  %10g %12.3f %12.3f %12.6f %12.2f\n', ...
            f_entrada(k), f_medida(k), f_medida(k)-F_OUT, ...
            amp_fund(k), residuo_pct(k));
end

%% ------------------------- Estados de las llaves ------------------------
% La columna del CSV es una cadena binaria de 18 bits, pero readtable la
% interpreta como un numero decimal cuyos digitos SON los bits. Como
% o_direcciones(17 downto 9) esta cableado a cero, el valor nunca pasa de
% 111111111 (~1.1e8) y entra exacto en un double, asi que se pueden extraer
% los digitos con aritmetica. (Usar bitget sobre ese numero da basura:
% mezcla los bits de la representacion decimal.)

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

    figure('Name', 'Barrido de f_in: llaves de la matriz', 'Color', 'w');
    paso = 1.5;
    for k = 1:n_esc
        % Zoom en el centro de cada escalon
        idx  = lim(k):lim(k+1)-1;
        F_IN = f_cmd(idx(1));
        t_c  = t(idx(round(numel(idx)/2)));

        subplot(n_esc, 1, k);
        hold on;
        for b = 0:8
            plot(t_dir, bits(:,b+1) + b*paso, 'b');
        end
        grid on; hold off;
        yticks((0:8)*paso + 0.5);
        yticklabels(etiquetas);
        xlim([t_c t_c+T_ZOOM]);
        ylim([-0.5, 9*paso]);
        xlabel('Tiempo [s]');
        title(sprintf('f_{in} = %g Hz  -  zoom de %g ms en el centro del escalon', ...
                      F_IN, T_ZOOM*1e3));
    end
else
    warning('No se encuentra %s. Se omite el grafico de llaves.', ARCH_DIRECCIONES);
end

%% ------------------------- Funciones locales ----------------------------

function marcar_escalones(t, lim)
    % Linea vertical punteada en cada cambio de escalon
    estaba_hold = ishold;
    hold on;
    yl = ylim;
    for k = 2:numel(lim)-1
        plot([t(lim(k)) t(lim(k))], yl, 'k--');
    end
    ylim(yl);
    if ~estaba_hold
        hold off;
    end
end

function P = nivel(f, P1, f0)
    % Amplitud del bin mas cercano a f0
    [~, k] = min(abs(f - f0));
    P = P1(k);
end

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
