/*
 * medir_criterios.c -- criterios 5 y 6 del spec, sobre la placa.
 *
 *   | 5 | Conversion de frecuencia, 60 in / 55 out | fundamental de i_o en
 *   |   |                                          | 55 Hz; nada en 60 Hz
 *   |   |                                          | sobre el piso
 *   | 6 | Referencia nula, regimen                 | ciclo limite de x1/x2
 *   |   |                                          | acotado a pocos LSB
 *
 * Los dos se miden ACA y no en XSIM porque piden ventanas largas: el criterio 5
 * necesita 1,7 s de registro para separar 55 de 60 Hz, que en simulacion son
 * 16,8 millones de ciclos de reloj.
 *
 * El modo se elige en compilacion con MODO. Es un programa de banco: recompilar
 * cuesta segundos y asi no hay que gastar un bit de GPIO en seleccionarlo.
 *
 * Uso:
 *   1. poner MODO en 5 o en 6
 *   2. powershell -File SW\ps\programar_y_capturar.ps1
 *   3. python SW/python/AnalizarCriterio5.py captura.csv     (o Criterio6)
 */

#define MODO  7

#include "pspl.h"

/* ------------------------------------------------------------- set points
 *
 * Los de 50 Hz salen de `python SW/python/ModeloControlPR.py params`, la misma
 * fuente que tb_ControlCorriente. Los de 60/55 se recalcularon con el mismo
 * metodo:
 *     paso_nco(f) = round(f * 2**32 / 10e6)
 *     paso_ref(f) = paso_nco(f) * 2048
 *     k(f)        = 2*sin(pi*f*Ts) en Q1.24
 */
#define V_KP         169613184    /* Kp = 10,1097 en Q8.24                   */
#define V_B          2718742      /* b = Kr*Ts, Kr = 791,258, en Q8.24       */
#define V_Q_MAX      14529495     /* sqrt(3)/2 en Q8.24                      */
#define V_INV_VI     32396475     /* 1/0,5179 en Q8.24                       */
#define V_AMP_06     1006633      /* 0,06 pu en Q8.24                        */

#if MODO == 5
/*
 * CRITERIO 5. 60 Hz de entrada, 55 Hz de salida.
 *
 * POR QUE 60/55 Y NO 60/50, que seria lo natural: con 60 y 50 todo producto
 * m*f_in + n*f_o es multiplo de 10 Hz, asi que cada bin recibe INFINITOS
 * productos y no se puede atribuir una banda a una causa. Con 55 la grilla se
 * vuelve de 5 Hz y cada banda queda identificada. Esta en el spec 7.4.
 *
 * N = 8192 muestras, una por Ts, son 1,678 s de ventana: df = 0,596 Hz y el
 * lobulo principal de Hann mide 2,38 Hz. Con N = 4096 el lobulo seria 4,77 Hz
 * contra una separacion de 5 Hz entre 55 y 60: demasiado al limite para afirmar
 * que no hay nada en 60.
 */
#define V_FREC_IN    25770        /* 60 Hz de entrada (real 60,000457 Hz)    */
#define V_PASO_REF   48377856     /* 55 Hz de salida = 23622 * 2048          */
#define V_K          1187140      /* k(55 Hz) en Q1.24                       */
#define V_AMP_REF    V_AMP_06
#define N_MUESTRAS   8192u
/* i_alfa e i_beta: la corriente de salida en el marco estacionario, que es lo
 * que el criterio mide. No se usan las de fase (6,7,8) porque la planta
 * simulada son tres RL independientes y deja pasar secuencia cero, medido el
 * 03/10/2026: Io_V daba +72 % sobre Io_U mientras alfa/beta estaban limpias. */
static const u32 RANURAS[] = { 9u, 10u };
#define ETIQUETAS    "i_alfa,i_beta"

#elif MODO == 6
/*
 * CRITERIO 6. Referencia NULA, regimen.
 *
 * Con amp_ref = 0 el lazo no tiene nada que seguir, pero los resonantes siguen
 * integrando el error de cuantizacion: lo que queda es un ciclo limite. El
 * criterio pide que este acotado a POCOS LSB.
 *
 * Por eso la ranura 19 lleva los 32 bits BAJOS de x1 (Q8.40) y no los altos:
 * un ciclo limite de unos pocos LSB desaparece si se trunca a Q8.24. La
 * magnitud no se pierde, se observa por la ranura 16 (v_alfa = kp*e + x1>>16).
 *
 * N = 4096 son 0,84 s, de sobra para ver si el ciclo limite crece o esta
 * acotado. Se captura tambien la 18 para confirmar que q se queda en cero: si
 * no lo hace, lo que se esta midiendo no es un ciclo limite sino un offset.
 */
#define V_FREC_IN    21475        /* 50 Hz                                   */
#define V_PASO_REF   43980800     /* 50 Hz                                   */
#define V_K          1079257      /* k(50 Hz) en Q1.24                       */
#define V_AMP_REF    0            /* <-- referencia NULA, el punto del test   */
#define N_MUESTRAS   4096u
/* Se agrega i_alfa: el ciclo limite de x1 solo se interpreta sabiendo QUE
 * CORRIENTE produce. Medido el 03/10/2026, x1 oscila 7,09e-03 en valor absoluto
 * -- 1,82 veces la ventana de 32 bits bajos, asi que hay que desenvolver -- y
 * sin la corriente ese numero no dice si molesta o no. */
static const u32 RANURAS[] = { 19u, 18u, 9u };
#define ETIQUETAS    "x1_alfa,q_al_o_sat,i_alfa"

#elif MODO == 7
/*
 * EFECTO DEL ESTADO GUARDADO EN EL TRANSITORIO.
 *
 * El criterio 6 dejo abierta una pregunta: el resonante no decae -- det(A) = 1
 * exacto, oscilador sin perdidas -- asi que cuando llega una referencia arranca
 * con la energia que agarro en el arranque. Importa eso?
 *
 * EL DISE~O DEL EXPERIMENTO. No hace falta resetear nada ni comparar contra una
 * condicion artificial: la amplitud guardada YA VARIA sola entre corridas,
 * medido factor 2,08 (7,79e9 contra 1,62e10 LSB). Esa variacion es la variable
 * independiente, gratis.
 *
 *   si el estado guardado afecta el transitorio -> el sobrepico varia con el
 *   si no lo afecta -> el sobrepico sale reproducible aunque x1 varie al doble
 *
 * Se capturan N_PRE muestras con amp_ref = 0 (para medir cuanta energia hay) y
 * despues N_POST con el escalon aplicado. Corriendo el programa varias veces
 * salen pares (energia previa, sobrepico) que se correlacionan.
 *
 * OJO con el commit: aca va SIN el usleep de sp_commit(), porque una espera de
 * 2 ms en medio de la captura dejaria un hueco de 10 Ts y rompería la cadencia
 * uniforme. Las escrituras son unas pocas transacciones AXI, muy por debajo del
 * Ts, asi que entran entre dos capturas sin molestar.
 */
#define V_FREC_IN    21475
#define V_PASO_REF   43980800
#define V_K          1079257
#define V_AMP_REF    0            /* arranca en cero; el escalon va en el medio */
#define N_PRE        512u         /* 0,105 s: cinco periodos de 50 Hz           */
#define N_POST       1536u        /* 0,315 s: cubre los 60 ms de establecimiento */
#define N_MUESTRAS   (N_PRE + N_POST)
static const u32 RANURAS[] = { 19u, 9u, 14u, 18u };
#define ETIQUETAS    "x1_alfa,i_alfa,ref_alfa,q_al_o_sat"

#else
#error "MODO tiene que ser 5, 6 o 7"
#endif

#define N_RAN  (sizeof(RANURAS) / sizeof(RANURAS[0]))

static u32 datos[N_MUESTRAS][N_RAN];

int main(void)
{
    u32 n;
    u32 i;

    uart_puts(UART0_BASE, "\r\n\r\n# ---- medir_criterios ---- UART0 (MIO 14..15)\r\n");
    uart_puts(UART1_BASE, "\r\n\r\n# ---- medir_criterios ---- UART1 (MIO 48..49)\r\n");
    con_str("# modo ");
    con_dec(MODO);
    con_str(", ");
    con_dec(N_MUESTRAS);
    con_str(" muestras de ");
    con_str(ETIQUETAS);
    con_str("\r\n");

    /* El modulador habilitado ANTES del commit: el commit cae en el flanco de
     * o_trg_calculo, que lo genera el modulador. Con el parado se queda
     * pendiente para siempre. El datapath arranca en reset para que el lazo no
     * corra ni un Ts con los defaults inertes. */
    ctrl = B_RST | B_EN;
    ctrl_aplicar();
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);
    Xil_Out32(DATA_BASE + GPIO2_DATA, 0u);

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
    /* El retardo no importa aca: i_alfa/i_beta y x1_alfa son valores del lazo,
     * que se actualizan una vez por Ts y no dependen de en que punto de la
     * ventana de PWM se mire. Queda en 0. */
    sp_escribir(SP_RETARDO,  0u);
    sp_commit();

    ctrl &= ~B_RST;
    ctrl_aplicar();

    /* Regimen antes de medir. El criterio 2 establece al 2 % en menos de 60 ms;
     * 300 ms son casi 1500 Ts. Para el criterio 6 importa mas todavia: lo que
     * se quiere ver es el ciclo limite, no la cola del transitorio. */
    usleep(300000);

    /* El clamp tiene que estar limpio, o la sintonia no es la que se pidio. */
    {
        u32 chk[N_RANURAS];
        if (capturar(chk) != 0) {
            con_str("# ERROR: no llego ningun o_trg_calculo.\r\n");
            return 1;
        }
        if ((chk[3] & 0xFFFFu) != 0u) {
            con_str("# ERROR: clamp = ");
            con_hex(chk[3] & 0xFFFFu);
            con_str(" -- CtrlRegs rechazo un set point.\r\n");
            return 1;
        }
    }

    /*
     * La adquisicion. Cada capturar_sel espera el disparo del modulador, asi
     * que las muestras salen a UN Ts exacto una de otra: 204,8 us, fs =
     * 4882,8125 Hz. Esa uniformidad es lo que hace valido el espectro; si el
     * lazo de lectura tardara mas de un Ts se saltearia disparos y el muestreo
     * dejaria de ser uniforme. Leer dos ranuras son cuatro transacciones AXI,
     * muy por debajo del Ts.
     */
    for (n = 0u; n < N_MUESTRAS; n++) {
#if MODO == 7
        /* El escalon, justo en N_PRE. Sin usleep: el commit cae solo en el
         * proximo flanco de o_trg_calculo, que es el mismo que dispara la
         * captura siguiente. */
        if (n == N_PRE) {
            sp_escribir(SP_AMP_REF, V_AMP_06);
            sp_escribir(SP_COMMIT, 0u);
        }
#endif
        if (capturar_sel(datos[n], RANURAS, N_RAN) != 0) {
            con_str("# ERROR: se corto el disparo en la muestra ");
            con_dec(n);
            con_str("\r\n");
            return 1;
        }
    }

    /* Volcado. Hex crudo, el que interpreta es el script de Python. */
    con_str("# fs = 4882.8125 Hz (una muestra por Ts de 204,8 us)\r\n");
#if MODO == 7
    con_str("# escalon de amp_ref 0 -> 0,06 pu en la muestra ");
    con_dec(N_PRE);
    con_str("\r\n");
#endif
    con_str("n,");
    con_str(ETIQUETAS);
    con_str("\r\n");
    for (n = 0u; n < N_MUESTRAS; n++) {
        con_dec(n);
        for (i = 0u; i < N_RAN; i++) {
            con_str(",");
            con_hex(datos[n][i]);
        }
        con_str("\r\n");
    }
    con_str("# fin, ");
    con_dec(N_MUESTRAS);
    con_str(" muestras\r\n");
    return 0;
}
