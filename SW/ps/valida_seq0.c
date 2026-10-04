/*
 * valida_seq0.c -- aplicacion minima del PS para validar el signo de seq0.
 *
 * QUE VALIDA Y POR QUE EXISTE
 *
 * Modulador.vhd tenia el signo de seq0 complementado, y el modulador
 * sintetizaba el vector en al_o + 180 grados. El arreglo esta en la rama
 * hitos_placa con un marcador "NO MERGEAR sin validar": esta aplicacion es la
 * validacion que falta.
 *
 * La medicion: capturar la PALABRA DE CONMUTACION (ranura 12) junto con el
 * al_o COMANDADO en el mismo Ts (ranura 18), volcarlas, y comparar offline el
 * angulo del vector aplicado contra el comandado. Si el arreglo es correcto
 * coinciden; si el bug volviera, difieren en 180 grados.
 *
 * Este programa NO decodifica nada. Solo captura y vuelca CSV. El desarmado de
 * la palabra de 9 bits a la matriz 3x3, la transformada de Clark y el atan2 van
 * en SW/python/DecodificarSeq0.py, donde se pueden testear y cruzar contra el
 * w_direcciones_log.csv que escribe la simulacion. Un C que hace trigonometria
 * es un C en el que no se puede confiar justo cuando el resultado no cierra.
 *
 * COMO CORRERLO
 *
 *   1. Vitis: plataforma desde HW/wrappers/design_testPSPLComm_wrapper.xsa
 *      (regenerarla con `write_hw_platform -fixed -include_bit -force`).
 *   2. Aplicacion standalone sobre ps7_cortexa9_0, con este archivo como unica
 *      fuente.
 *   3. Capturar la UART (115200 8N1) a un archivo, p. ej. con PuTTY o
 *      `plink -serial COMx -sercfg 115200 > captura.csv`.
 *   4. python SW/python/DecodificarSeq0.py captura.csv
 *
 * Build: -Os alcanza. No necesita interrupciones ni DDR mas alla del .bss.
 */

#include "pspl.h"

/* -------------------------------------------------------------- set points
 *
 * Salen de `python SW/python/ModeloControlPR.py params`, que es la misma
 * fuente que usa tb_ControlCorriente, o sea los valores con los que los
 * criterios 1 a 4 pasaron en XSIM.
 */
#define V_FREC_IN    21475        /* 50 Hz de entrada, paso del NCO          */
#define V_PASO_REF   43980800     /* 50 Hz de salida = 21475 * 2048          */
#define V_AMP_REF    1006633      /* 0,06 pu en Q8.24                        */
#define V_K          1079257      /* k(50 Hz) = 2*sin(pi*50*Ts) en Q1.24     */
#define V_KP         169613184    /* Kp = 10,1097 en Q8.24                   */
#define V_B          2718742      /* b = Kr*Ts, Kr = 791,258, en Q8.24       */
#define V_Q_MAX      14529495     /* sqrt(3)/2 en Q8.24                      */
#define V_INV_VI     32396475     /* 1/0,5179 en Q8.24                       */

/* Cuantas fotos. Las capturas consecutivas caen a ~1 Ts una de otra (el
 * armado espera el proximo o_trg_calculo), y 1 Ts son 3,686 grados a 50 Hz,
 * asi que ~98 capturas cubren un periodo de salida. 300 da unos tres. */
/*
 * BARRIDO DEL RETARDO DE CAPTURA.
 *
 * La primera corrida en la placa (03/10/2026) devolvio 300 fotos y las 300
 * cayeron en un VECTOR NULO: 0x124 o 0x049, las tres salidas a la misma
 * entrada. La causa es que o_trg_calculo cae siempre en la misma ranura del
 * patron SSVM, y esa ranura es el N/2 con que el patron arranca.
 *
 * Asi que ahora se BARRE el punto de muestreo por la ventana de PWM, moviendo
 * el indice 10 de CtrlRegs. N_RET puntos espaciados PASO_RET clocks cubren los
 * 2048 del Ts, y en cada punto se toman N_POR_RET fotos para promediar sobre el
 * angulo de salida.
 *
 * El rango util es 0..2046: en 2047 el disparo cae un Ts completo despues y
 * choca con el siguiente.
 */
#define N_RET       32u              /* puntos del barrido                   */
#define PASO_RET    64u              /* 32 * 64 = 2048, la ventana completa   */
#define N_POR_RET   8u               /* fotos por punto                       */
#define N_CAP       (N_RET * N_POR_RET)

/* Se captura TODO a RAM y se vuelca al final. Imprimir intercalado no sirve:
 * una linea de ~180 caracteres a 115200 baudios tarda ~15 ms, o sea 73 Ts, y
 * el barrido quedaria aliaseado a 270 grados por muestra. */
static u32 fotos[N_CAP][N_RANURAS];
/* el retardo con que se tomo cada foto, para que el decodificador agrupe */
static u32 rets[N_CAP];

int main(void)
{
    u32 n;
    u32 i;
    u32 r;
    u32 k;
    int fallo;

    /*
     * El modulador arranca HABILITADO y el datapath en RESET.
     *
     * El orden importa: el commit de CtrlRegs cae en el flanco de
     * o_trg_calculo, que lo genera el modulador, asi que hay que habilitarlo
     * ANTES de commitear o los set points nunca se aplican. Y el datapath
     * queda en reset mientras se carga la sintonia, para que el lazo no corra
     * ni un Ts con los defaults inertes.
     *
     * B_RSTREG queda en 0: CtrlRegs tiene reset propio y arranca FUERA de
     * reset (inicializa shadow y activo con sus defaults en la declaracion),
     * asi que acepta escrituras de entrada. Si estuviera en 1 las ignoraria.
     */
    /*
     * LO PRIMERO ES HABLAR, antes de tocar la PL.
     *
     * Si la PL no esta programada no hay slave AXI en 0x4120_0000, el
     * interconnect nunca contesta y el ARM se CUELGA en la primera escritura.
     * El sintoma es cero salida por la UART, que es un silencio ambiguo: no
     * distingue "no corrio", "UART equivocada" y "PL sin programar".
     *
     * Con el banner primero el silencio se vuelve diagnostico:
     *   no se ve NADA              -> no corrio, o es la otra UART
     *   se ve el banner y se cuelga -> la PL no esta programada
     */
    /* Por los dos UART, para que se vea cual es el que llega al USB. La linea
     * que aparezca dice de cual se trata; si aparecen las dos, hay dos puentes. */
    uart_puts(UART0_BASE,
              "\r\n\r\n# ---- valida_seq0 ---- salida por UART0 (MIO 14..15)\r\n");
    uart_puts(UART1_BASE,
              "\r\n\r\n# ---- valida_seq0 ---- salida por UART1 (MIO 48..49)\r\n");

    /* Y a partir de aca por stdout. Si ves el banner de arriba pero NO esta
     * linea, standalone_stdout de la BSP apunta al UART desconectado: ponerlo
     * en el que si aparecio arriba. */
    con_str("# consola por UART_CONSOLA, sin pasar por la BSP.\r\n");
    con_str("# Ahora toco la PL en 0x");
    con_hex(CTRL_BASE);
    con_str(". Si se cuelga aca, la PL NO esta programada.\r\n");

    ctrl = B_RST | B_EN;
    ctrl_aplicar();
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);
    Xil_Out32(DATA_BASE + GPIO2_DATA, 0u);

    con_str("# La PL contesta.\r\n");

    /* Eco de ch2 (wr_data), que no tiene efecto porque wr_stb esta en 0. Es
     * informativo y NO aborta: que un canal all-outputs devuelva lo escrito
     * depende de la version del AXI GPIO, asi que un eco distinto no prueba
     * que algo este mal. Si vuelve 0 o 0xFFFFFFFF, sospechar de la PL. */
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0x5A5A5A5Au);
    con_str("# eco de ch2: escrito 5a5a5a5a, leido ");
    con_hex(Xil_In32(CTRL_BASE + GPIO2_DATA));
    con_str("\r\n");
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);

    con_str("# valida_seq0: captura la palabra de conmutacion contra el al_o comandado\r\n");

    sp_escribir(SP_FREC_IN,  V_FREC_IN);
    sp_escribir(SP_PASO_REF, V_PASO_REF);
    sp_escribir(SP_AMP_REF,  V_AMP_REF);
    sp_escribir(SP_K,        V_K);
    sp_escribir(SP_KP,       V_KP);
    sp_escribir(SP_B,        V_B);
    sp_escribir(SP_PHI_I,    0u);
    sp_escribir(SP_Q_MAX,    V_Q_MAX);
    sp_escribir(SP_INV_VI,   V_INV_VI);
    sp_escribir(SP_FREEZE,   1u);
    sp_commit();

    /* Suelta el datapath. */
    ctrl &= ~B_RST;
    ctrl_aplicar();

    /* Regimen. El criterio 2 establece al 2 % en menos de 60 ms; 200 ms es
     * casi 1000 Ts y deja el transitorio bien atras. */
    usleep(200000);

    /* Antes de capturar: que el clamp este limpio. La ranura 19 lo trae
     * sticky, y si CtrlRegs rechazo un set point los numeros de abajo serian
     * de una sintonia distinta de la que se pidio. */
    fallo = capturar(fotos[0]);
    if (fallo != 0) {
        con_str("# ERROR: no llego ningun o_trg_calculo.\r\n");
        con_str("# El modulador esta habilitado? bit1 de ch1.\r\n");
        return 1;
    }
    if ((fotos[0][3] & 0xFFFFu) != 0u) {
        con_str("# ERROR: clamp = ");
        con_hex(fotos[0][3] & 0xFFFFu);
        con_str(" -- CtrlRegs rechazo un set point.\r\n");
        con_str("# Los bits dicen que indice: el 3 es k, el 7 es q_max.\r\n");
        return 1;
    }

    /*
     * El barrido. Por cada punto de retardo se escribe el indice 10, se
     * commitea, y se toman N_POR_RET fotos.
     *
     * El commit cae en el flanco de o_trg_calculo, asi que sp_commit() espera
     * un Ts: sin eso las primeras fotos del punto saldrian con el retardo
     * ANTERIOR y el barrido quedaria corrido.
     */
    n = 0u;
    for (r = 0u; r < N_RET; r++) {
        u32 ret = r * PASO_RET;

        sp_escribir(SP_RETARDO, ret);
        sp_commit();

        for (k = 0u; k < N_POR_RET; k++) {
            if (capturar(fotos[n]) != 0) {
                con_str("# ERROR: se corto el disparo con retardo ");
                con_dec(ret);
                con_str(", captura ");
                con_dec(n);
                con_str("\r\n");
                return 1;
            }
            rets[n] = ret;
            n++;
        }
    }

    /* Volcado. Todo en hex crudo: el que decodifica es DecodificarSeq0.py. */
    con_str("# ranuras: 00-02 Vi(u,v,w)  03 clamp  04,05,11 Vo(u,v,w)\r\n");
    con_str("#          06-08 Io(u,v,w)  09,10 i_alfa,i_beta  12 direcciones\r\n");
    con_str("#          13 ESTADO  14,15 ref_alfa,ref_beta  16,17 v_alfa,v_beta\r\n");
    con_str("#          18 q|al_o|sat  19 x1_alfa(32 b bajos de Q8.40)\r\n");
    con_str("# ranura 18: bits 8-0 = q, bits 19-9 = al_o, bit 20 = sat\r\n");
    con_str("# la columna 'ret' es el retardo de captura en clocks:\r\n");
    con_str("# el decodificador agrupa por ella.\r\n");
    con_str("n,ret");
    for (i = 0u; i < N_RANURAS; i++) {
        con_str(",d");
        con_dec(i);
    }
    con_str("\r\n");

    for (n = 0u; n < N_CAP; n++) {
        con_dec(n);
        con_str(",");
        con_dec(rets[n]);
        for (i = 0u; i < N_RANURAS; i++) {
            con_str(",");
            con_hex(fotos[n][i]);
        }
        con_str("\r\n");
    }
    con_str("# fin, ");
    con_dec(N_CAP);
    con_str(" capturas en ");
    con_dec(N_RET);
    con_str(" puntos de retardo, paso ");
    con_dec(PASO_RET);
    con_str(" clocks\r\n");
    return 0;
}
