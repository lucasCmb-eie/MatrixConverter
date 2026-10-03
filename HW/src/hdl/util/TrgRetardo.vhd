library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--!
-- Retardo programable del disparo de captura, dentro de la ventana de PWM.
--
-- POR QUE EXISTE
--
-- CaptureBank se dispara con o_trg_calculo del SVM_wrapper, que es
-- fin_calc_ts_falling: el final de la fase de calculo del modulador. Ese
-- instante cae SIEMPRE en la misma ranura del patron SSVM, y medido en la
-- placa el 03/10/2026 esa ranura es un VECTOR NULO: las 300 fotos de la
-- primera corrida devolvieron 0x124 (las tres salidas a la entrada U) o 0x049
-- (las tres a W), sin una sola excepcion.
--
-- Un vector nulo no tiene angulo, asi que no sirve para comparar contra al_o y
-- la validacion del signo de seq0 era imposible: no habia informacion que
-- medir. El patron SSVM arranca y termina con N/2, y el disparo cae ahi.
--
-- Con este retardo el punto de muestreo se barre por los 2048 clocks del Ts, y
-- eso hace dos cosas: permite caer en los vectores activos (que es lo que
-- destraba la validacion) y convierte a CaptureBank en un osciloscopio de
-- muestreo del patron de conmutacion completo.
--
-- COMO SE USA
--
-- i_retardo son clocks de espera desde el flanco de i_trg; el pulso sale
-- retardo+1 ciclos despues. 11 bits cubren los 2048 clocks del Ts, asi que
-- cualquier valor alcanza la ventana entera. El PS lo mueve por un indice de
-- CtrlRegs, sin re-sintetizar.
--
-- o_trg es un pulso de UN ciclo, no un nivel: CaptureBank detecta flanco
-- (CaptureBank.vhd:99, `i_trigger = '1' and trg_z1 = '0'`).
--
-- Un flanco nuevo mientras cuenta REARRANCA la cuenta. Con retardo <= 2047 y
-- un Ts de 2048 clocks la cuenta siempre termina antes del disparo siguiente,
-- asi que en operacion normal no pasa; es la conducta segura si el Ts cambiara.
entity TrgRetardo is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_trg     : in  std_logic;                      --! o_trg_calculo del SVM
        i_retardo : in  std_logic_vector(10 downto 0);  --! clocks de espera, 0..2047
        o_trg     : out std_logic                       --! pulso de un ciclo
    );
end entity TrgRetardo;

architecture rtl of TrgRetardo is
    signal trg_z1   : std_logic := '0';
    signal contando : std_logic := '0';
    signal cuenta   : unsigned(10 downto 0) := (others => '0');
    signal pulso    : std_logic := '0';
begin

    o_trg <= pulso;

    proceso : process (i_clk)
    begin
        if rising_edge(i_clk) then
            --! por default el pulso baja: asi dura un solo ciclo sin tener que
            --! acordarse de bajarlo en cada rama
            pulso <= '0';

            if i_rst = '1' then
                trg_z1   <= '0';
                contando <= '0';
                cuenta   <= (others => '0');
            else
                trg_z1 <= i_trg;

                if i_trg = '1' and trg_z1 = '0' then
                    --! flanco de i_trg: (re)arranca
                    if unsigned(i_retardo) = 0 then
                        pulso    <= '1';        -- sin retardo
                        contando <= '0';
                    else
                        contando <= '1';
                        cuenta   <= to_unsigned(1, cuenta'length);
                    end if;

                elsif contando = '1' then
                    if cuenta = unsigned(i_retardo) then
                        pulso    <= '1';
                        contando <= '0';
                    else
                        cuenta <= cuenta + 1;
                    end if;
                end if;
            end if;
        end if;
    end process proceso;

end architecture rtl;
