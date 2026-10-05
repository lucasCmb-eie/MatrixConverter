library ieee;
use ieee.std_logic_1164.all;

--! Escenarios de los criterios 2, 3 y 4 del spec 7.4, como entidades
--! envoltorio sobre tb_ControlCorriente.
--!
--! Van aca y no en la linea de comandos de xelab porque -generic_top se
--! rompe con el '=' en Windows, y porque asi los parametros de cada prueba
--! quedan versionados y legibles en vez de escondidos en un script.
--!
--! Cada uno escribe control_corriente.csv en su directorio de trabajo, asi
--! que hay que correrlos en carpetas separadas. Analizar con
--! SW/python/AnalizarTransitorios.py.
--!
--! Los criterios 5 (espectro de conversion de frecuencia) y 6 (ciclo limite)
--! NO estan aca: se miden sobre la placa, donde las ventanas largas son
--! baratas y la carga es real.

--! Criterio 2: escalon de amplitud 0,03 -> 0,06 pu a los 100 ms.
--! Sobrepico < 20 %, establecimiento al 2 % en < 60 ms.
--!
--! POR QUE 0,06 Y NO 0,10. El techo de corriente de este conversor sobre esta
--! carga es q_max * V_i / |Z| = 0,866 * 0,5178 / 3,9563 = 0,1133 pu. Con el
--! escalon terminando en 0,10 (el 88 % del techo), un sobrepico del 20 %
--! caeria en 0,120 pu, o sea el 106 % del techo: SATURA ANTES DE SER VISIBLE.
--! El criterio pide "sobrepico < 20 %" y con ese escalon no podia fallar nunca
--! -- medía un pico recortado y daba verde con cualquier sintonia. Con 0,06 el
--! 20 % llega a 0,072 pu, el 64 % del techo, y se mide de verdad.
--!
--! Se mantiene el escalon de 2x (0,03 -> 0,06) para no cambiar la naturaleza
--! de la prueba.
--!
--! OJO con los numeros viejos: la version anterior de este comentario derivaba
--! el techo de |v_o|sat = 0,50 y 1/1,0397, que son las dos constantes que la
--! rama de investigacion RETRACTO (q_max paso a 0,866 y V_i a 0,5178). Daban
--! 0,131 pu, un 16 % mas de techo del que hay.
entity tb_crit2_escalon_amplitud is
end entity tb_crit2_escalon_amplitud;

architecture sim of tb_crit2_escalon_amplitud is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_AMP_REF => 503316,      -- 0,03 pu
                     G_TS_ESC1 => 488,         -- 100 ms
                     G_AMP_2   => 1006633);    -- 0,06 pu
end architecture sim;


--! Criterio 3: escalon de f_o 50 -> 30 Hz a los 150 ms, con frec_ref y k
--! viajando en el mismo Ts. Sin perdida de sincronismo, reestablecimiento
--! en < 60 ms.
entity tb_crit3_escalon_frecuencia is
end entity tb_crit3_escalon_frecuencia;

architecture sim of tb_crit3_escalon_frecuencia is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_TS_ESC1   => 732,       -- 150 ms
                     G_PASO_REF2 => 12885,     -- 30 Hz
                     G_K2        => 647626);   -- k(30 Hz) en Q1.24
end architecture sim;


--! Criterio 4a: sobrecomando a 0,50 pu (el maximo alcanzable es 0,219) entre
--! los 100 y los 200 ms, CON anti-windup.
entity tb_crit4a_freeze is
end entity tb_crit4a_freeze;

architecture sim of tb_crit4a_freeze is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_TS_ESC1 => 488, G_AMP_2 => 8388608,
                     G_TS_ESC2 => 976, G_AMP_3 => 1006633,
                     G_FREEZE  => 1);
end architecture sim;


--! Criterio 4b: lo mismo SIN anti-windup. La prueba es diferencial: si el
--! pico al desaturar es igual en las dos, el freeze no esta haciendo nada.
--!
--! La recuperacion tambien bajo de 0,10 a 0,06 pu, por la misma razon que el
--! criterio 2: a 0,10 el pico al desaturar se recorta contra el techo de
--! 0,1133 en LAS DOS corridas, y entonces la prueba diferencial no puede
--! distinguir el freeze del no-freeze aunque el freeze funcione.
entity tb_crit4b_sin_freeze is
end entity tb_crit4b_sin_freeze;

architecture sim of tb_crit4b_sin_freeze is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_TS_ESC1 => 488, G_AMP_2 => 8388608,
                     G_TS_ESC2 => 976, G_AMP_3 => 1006633,
                     G_FREEZE  => 0);
end architecture sim;
