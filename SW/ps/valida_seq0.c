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

#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

/* ------------------------------------------------------------------ mapa AXI
 *
 * Las direcciones las asigna assign_bd_address en create_bd.tcl y las imprime
 * la auditoria (DIRECCION|SEG_axi_gpio_ctrl_Reg @ 0x41200000). Se ponen a mano
 * y no por xparameters.h a proposito: asi este archivo compila contra
 * cualquier plataforma regenerada sin depender de como Vitis bautizo los
 * defines. Si el BD cambia de direcciones, la auditoria lo canta.
 */
#define CTRL_BASE   0x41200000u   /* ch1 = control, ch2 = wr_data           */
#define DATA_BASE   0x41210000u   /* ch1 = dato capturado, ch2 = selector   */

/* registros del AXI GPIO. Los TRI no existen: los dos canales se configuraron
 * all-outputs / all-inputs, asi que la direccion quedo fija en hardware y
 * escribirlos no hace nada. */
#define GPIO_DATA   0x00u
#define GPIO2_DATA  0x08u

/* ------------------------------------------------------- bits de ch1 (control) */
#define B_RST       (1u << 0)     /* reset del datapath                      */
#define B_EN        (1u << 1)     /* enable del modulador                    */
#define B_ARM       (1u << 2)     /* arma una captura                        */
#define B_WRSTB     (1u << 3)     /* strobe de escritura a CtrlRegs          */
#define WRIDX_SH    4
#define WRIDX_MSK   (0xFu << WRIDX_SH)
#define B_RSTREG    (1u << 8)     /* reset SOLO del banco de set points      */

/* ------------------------------------------------------------------ CtrlRegs */
#define SP_FREC_IN   0u
#define SP_PASO_REF  1u
#define SP_AMP_REF   2u
#define SP_K         3u
#define SP_KP        4u
#define SP_B         5u
#define SP_PHI_I     6u
#define SP_Q_MAX     7u
#define SP_INV_VI    8u
#define SP_FREEZE    9u
#define SP_COMMIT   15u

/* ------------------------------------------------------- UART, a mano
 *
 * La Blackboard expone UN solo puente USB-serie (un unico COM aparece al
 * conectarla), y de los dos UART del PS -- UART0 en MIO 14..15, UART1 en
 * MIO 48..49, los dos habilitados a 115200 en el PS7 -- solo uno llega a el.
 * Cual es cableado de la placa y no se puede deducir del diseño.
 *
 * Asi que el banner sale por LOS DOS, escribiendo directo al FIFO de cada uno
 * en vez de pasar por stdout. El que este conectado lo muestra y la pregunta
 * se contesta sola, sin tener que probar la BSP dos veces.
 *
 * Es seguro: los UART son perifericos del PS, existen siempre y no dependen de
 * que la PL este programada, asi que esto NO se puede colgar.
 */
#define UART0_BASE      0xE0000000u
#define UART1_BASE      0xE0001000u
#define UART_SR         0x2Cu            /* Channel Status Register */
#define UART_FIFO       0x30u            /* TX/RX FIFO              */
#define UART_SR_TXFULL  (1u << 4)

static void uart_puts(u32 base, const char *s)
{
    while (*s != '\0') {
        while ((Xil_In32(base + UART_SR) & UART_SR_TXFULL) != 0u) {
            /* espera lugar en el FIFO */
        }
        Xil_Out32(base + UART_FIFO, (u32)(unsigned char)(*s));
        s++;
    }
}

/* ---------------------------------------------------------------- CaptureBank */
#define N_RANURAS   20u
#define IDX_ESTADO  13u           /* devuelve el estado, no un registro      */

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
#define N_CAP       300u

/* Se captura TODO a RAM y se vuelca al final. Imprimir intercalado no sirve:
 * una linea de ~180 caracteres a 115200 baudios tarda ~15 ms, o sea 73 Ts, y
 * el barrido quedaria aliaseado a 270 grados por muestra. */
static u32 fotos[N_CAP][N_RANURAS];

/* Copia por software de ch1. Es un UNICO registro de 32 bits, asi que todo
 * cambio tiene que ser read-modify-write: escribir un bit sin preservar los
 * otros resetea el datapath o desarma una captura a medias. */
static u32 ctrl;

static void ctrl_aplicar(void)
{
    Xil_Out32(CTRL_BASE + GPIO_DATA, ctrl);
}

/* Escribe un set point al banco SHADOW. No se ve en el lazo hasta el commit. */
static void sp_escribir(u32 idx, u32 dato)
{
    /* El dato va primero: i_wr_stb latchea por FLANCO ASCENDENTE y wr_data
     * tiene que estar estable antes del flanco. */
    Xil_Out32(CTRL_BASE + GPIO2_DATA, dato);

    ctrl = (ctrl & ~(WRIDX_MSK | B_WRSTB)) | ((idx << WRIDX_SH) & WRIDX_MSK);
    ctrl_aplicar();                 /* idx puesto, stb todavia en 0 */

    ctrl |= B_WRSTB;
    ctrl_aplicar();                 /* flanco ascendente: aca entra el dato */

    ctrl &= ~B_WRSTB;
    ctrl_aplicar();                 /* listo para el proximo */
}

/* Aplica el shadow al banco activo.
 *
 * Escribir el indice 15 solo levanta `pendiente`; el banco se copia en el
 * flanco de o_trg_calculo, o sea una vez por Ts = 204,8 us. Por eso la espera:
 * volver antes significaria leer set points que todavia no estan activos.
 *
 * OJO: el modulador tiene que estar habilitado (B_EN) para que o_trg_calculo
 * pulse. Con el modulador parado el commit se queda pendiente para siempre.
 */
static void sp_commit(void)
{
    sp_escribir(SP_COMMIT, 0);
    usleep(2000);                   /* ~10 Ts, de sobra para un Ts de 204,8 us */
}

/*
 * Una captura: armar, esperar el disparo del modulador, leer las 20 ranuras,
 * desarmar.
 *
 * La captura la pide el PS pero la DISPARA el modulador (o_trg_calculo), asi
 * que la foto cae siempre en el mismo punto de la ventana de PWM. Y es una
 * sola captura por armado: los disparos siguientes no repisan la foto, que es
 * lo que permite barrer el selector con 20 transacciones AXI sin correr contra
 * el Ts.
 *
 * Devuelve 0, o -1 si el disparo nunca llego.
 */
static int capturar(u32 *v)
{
    u32 i;
    u32 vueltas;

    ctrl |= B_ARM;
    ctrl_aplicar();

    /* El indice 13 del selector devuelve el estado SIN pasar por los registros
     * de captura, justamente para poder poleerlo antes de que la foto exista.
     * Bit 0 = listo. */
    Xil_Out32(DATA_BASE + GPIO2_DATA, IDX_ESTADO);
    for (vueltas = 0u; vueltas < 1000000u; vueltas++) {
        if ((Xil_In32(DATA_BASE + GPIO_DATA) & 1u) != 0u) {
            break;
        }
    }
    if (vueltas >= 1000000u) {
        ctrl &= ~B_ARM;
        ctrl_aplicar();
        return -1;
    }

    /* El selector es combinacional dentro de CaptureBank, y la BSP standalone
     * mapea 0x4000_0000-0x7FFF_FFFF como Device memory (no cacheable, no
     * reordenable), asi que la escritura del selector completa antes de la
     * lectura siguiente. No hace falta demora entre las dos. */
    for (i = 0u; i < N_RANURAS; i++) {
        Xil_Out32(DATA_BASE + GPIO2_DATA, i);
        v[i] = Xil_In32(DATA_BASE + GPIO_DATA);
    }

    /* El desarmado ES el ack: limpia o_listo, que es nivel y no pulso. */
    ctrl &= ~B_ARM;
    ctrl_aplicar();
    return 0;
}

int main(void)
{
    u32 n;
    u32 i;
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

    /* Y a partir de aca, por stdout (que la BSP apunta a uno de los dos). Si
     * ves la linea de arriba pero NO esta, stdout esta en el UART equivocado:
     * cambiar standalone_stdout en la BSP al que si aparecio. */
    xil_printf("# Esta linea sale por stdout. Si falta, stdout esta en el otro UART.\r\n");
    xil_printf("# Ahora toco la PL en 0x%x. Si se cuelga aca, la PL NO esta programada.\r\n",
               (unsigned int)CTRL_BASE);

    ctrl = B_RST | B_EN;
    ctrl_aplicar();
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);
    Xil_Out32(DATA_BASE + GPIO2_DATA, 0u);

    xil_printf("# La PL contesta.\r\n");

    /* Eco de ch2 (wr_data), que no tiene efecto porque wr_stb esta en 0. Es
     * informativo y NO aborta: que un canal all-outputs devuelva lo escrito
     * depende de la version del AXI GPIO, asi que un eco distinto no prueba
     * que algo este mal. Si vuelve 0 o 0xFFFFFFFF, sospechar de la PL. */
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0x5A5A5A5Au);
    xil_printf("# eco de ch2: escrito 5a5a5a5a, leido %x\r\n",
               (unsigned int)Xil_In32(CTRL_BASE + GPIO2_DATA));
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);

    xil_printf("# valida_seq0: captura la palabra de conmutacion contra el al_o comandado\r\n");

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
        xil_printf("# ERROR: no llego ningun o_trg_calculo.\r\n");
        xil_printf("# El modulador esta habilitado? bit1 de ch1.\r\n");
        return 1;
    }
    if ((fotos[0][3] & 0xFFFFu) != 0u) {
        xil_printf("# ERROR: clamp = %x -- CtrlRegs rechazo un set point.\r\n",
                   (unsigned int)(fotos[0][3] & 0xFFFFu));
        xil_printf("# Los bits dicen que indice: el 3 es k, el 7 es q_max.\r\n");
        return 1;
    }

    for (n = 0u; n < N_CAP; n++) {
        if (capturar(fotos[n]) != 0) {
            xil_printf("# ERROR: se corto el disparo en la captura %d\r\n",
                       (int)n);
            return 1;
        }
    }

    /* Volcado. Todo en hex crudo: el que decodifica es DecodificarSeq0.py. */
    xil_printf("# ranuras: 00-02 Vi(u,v,w)  03 clamp  04,05,11 Vo(u,v,w)\r\n");
    xil_printf("#          06-08 Io(u,v,w)  09,10 i_alfa,i_beta  12 direcciones\r\n");
    xil_printf("#          13 ESTADO  14,15 ref_alfa,ref_beta  16,17 v_alfa,v_beta\r\n");
    xil_printf("#          18 q|al_o|sat  19 x1_alfa(32 b bajos de Q8.40)\r\n");
    xil_printf("# ranura 18: bits 8-0 = q, bits 19-9 = al_o, bit 20 = sat\r\n");
    xil_printf("n");
    for (i = 0u; i < N_RANURAS; i++) {
        xil_printf(",d%d", (int)i);
    }
    xil_printf("\r\n");

    for (n = 0u; n < N_CAP; n++) {
        xil_printf("%d", (int)n);
        for (i = 0u; i < N_RANURAS; i++) {
            xil_printf(",%x", (unsigned int)fotos[n][i]);
        }
        xil_printf("\r\n");
    }
    xil_printf("# fin, %d capturas\r\n", (int)N_CAP);
    return 0;
}
