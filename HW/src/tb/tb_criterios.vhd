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

--! Criterio 2: escalon de amplitud 0,05 -> 0,10 pu a los 100 ms.
--! Sobrepico < 20 %, establecimiento al 2 % en < 60 ms.
--!
--! El objetivo es 0,10 y no 0,15 porque 0,15 es INALCANZABLE: el barrido de
--! lazo abierto muestra que el modulador satura en |v_o| ~ 0,50, o sea
--! 0,50 * 1,0397 / 3,9563 = 0,131 pu de corriente. El 0,15 del plan pedia
--! mas de lo que este conversor entrega sobre esta carga.
entity tb_crit2_escalon_amplitud is
end entity tb_crit2_escalon_amplitud;

architecture sim of tb_crit2_escalon_amplitud is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_AMP_REF => 838861,      -- 0,05 pu
                     G_TS_ESC1 => 488,         -- 100 ms
                     G_AMP_2   => 1677722);    -- 0,10 pu
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
                     G_TS_ESC2 => 976, G_AMP_3 => 1677722,
                     G_FREEZE  => 1);
end architecture sim;


--! Criterio 4b: lo mismo SIN anti-windup. La prueba es diferencial: si el
--! pico al desaturar es igual en las dos, el freeze no esta haciendo nada.
entity tb_crit4b_sin_freeze is
end entity tb_crit4b_sin_freeze;

architecture sim of tb_crit4b_sin_freeze is
begin
    dut : entity work.tb_ControlCorriente
        generic map (G_TS_ESC1 => 488, G_AMP_2 => 8388608,
                     G_TS_ESC2 => 976, G_AMP_3 => 1677722,
                     G_FREEZE  => 0);
end architecture sim;
