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
#define SP_RETARDO  10u
#define SP_COMMIT   15u

/* ------------------------------------------------------- UART, a mano
 *
 * La Blackboard expone UN solo puente USB-serie (un unico COM aparece al
 * conectarla), y de los dos UART del PS -- UART0 en MIO 14..15, UART1 en
 * MIO 48..49, los dos habilitados a 115200 en el PS7 -- solo uno llega a el.
 * Cual es cableado de la placa y no se puede deducir del diseÃ±o.
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

/*
 * MEDIDO en la Blackboard el 03/10/2026: el banner por UART1 (MIO 48..49)
 * aparece en la terminal y el de UART0 (MIO 14..15) no. O sea que el puente
 * USB-serie esta en UART1, y standalone_stdout de la BSP tiene que valer
 * ps7_uart_1.
 *
 * Es cableado de placa: al migrar a otra hay que volver a mirar cual de los dos
 * banners sale.
 */

static void uart_putc(u32 base, char c)
{
    while ((Xil_In32(base + UART_SR) & UART_SR_TXFULL) != 0u) {
        /* espera lugar en el FIFO */
    }
    Xil_Out32(base + UART_FIFO, (u32)(unsigned char)c);
}

static void uart_puts(u32 base, const char *s)
{
    while (*s != '\0') {
        uart_putc(base, *s);
        s++;
    }
}

/*
 * ------------------------------------------------------------------ consola
 *
 * Toda la salida va por UART_CONSOLA con estas tres funciones, NO por
 * xil_printf. Formatear dos tipos de entero son veinte lineas y a cambio el
 * programa queda INDEPENDIENTE de la BSP.
 *
 * Por que importa: stdout de la BSP standalone sale de standalone_stdin, que a
 * su vez sale de STDIN_INSTANCE, que un archivo GENERADO fija tomando el
 * PRIMERO de UARTPS_NUM_DRIVER_INSTANCES -- o sea ps7_uart_0, que en esta placa
 * no esta cableado. Cambiarlo requiere tocar los dos parametros Y recompilar la
 * plataforma, y encima se pierde cada vez que alguien la regenera desde el
 * .xsa, porque SW/vitis/ no esta versionado. Un programa cuyo unico proposito
 * es diagnosticar no puede depender de eso.
 *
 * UART_CONSOLA es la unica linea a cambiar si la placa cambia. El banner doble
 * de main() dice cual es.
 */
#define UART_CONSOLA    UART1_BASE

static void con_str(const char *s)
{
    uart_puts(UART_CONSOLA, s);
}

/* hex sin ceros a la izquierda, como el %x de printf */
static void con_hex(u32 v)
{
    char buf[9];
    int i = 8;

    buf[8] = '\0';
    if (v == 0u) {
        con_str("0");
        return;
    }
    while (v != 0u) {
        u32 d = v & 0xFu;
        i--;
        buf[i] = (char)((d < 10u) ? ('0' + (int)d) : ('a' + (int)(d - 10u)));
        v >>= 4;
    }
    con_str(&buf[i]);
}

/* decimal sin signo. u32 maximo = 4294967295, diez digitos */
static void con_dec(u32 v)
{
    char buf[11];
    int i = 10;

    buf[10] = '\0';
    if (v == 0u) {
        con_str("0");
        return;
    }
    while (v != 0u) {
        i--;
        buf[i] = (char)('0' + (int)(v % 10u));
        v /= 10u;
    }
    con_str(&buf[i]);
}

/*
 * NO se puede retargetear stdout definiendo outbyte() aca. Se intento y el
 * enlace falla con
 *
 *   multiple definition of `outbyte'; valida_seq0.c.obj: first defined here
 *
 * El truco de ganarle a la libreria definiendo el simbolo en la aplicacion solo
 * funciona si el miembro de la libreria NO se incluye por otra razon, y el
 * objeto de la BSP que trae outbyte entra igual porque se necesita otro simbolo
 * del mismo archivo.
 *
 * Y pelear con el parametro de la BSP tampoco sirve. standalone_stdout se
 * FUERZA a seguir a standalone_stdin (xilstandalone.cmake:188), y las dos salen
 * de STDIN_INSTANCE, que un archivo GENERADO fija tomando el PRIMERO de
 * UARTPS_NUM_DRIVER_INSTANCES = "ps7_uart_0;ps7_uart_1". O sea: el default es
 * el UART que NO esta cableado, cambiarlo pide tocar los dos parametros Y
 * recompilar la plataforma, y encima se pierde cada vez que alguien la
 * regenera, porque SW/vitis/ no esta versionado por decision.
 *
 * Por eso este programa NO usa stdout: toda su salida va por con_str/con_hex/
 * con_dec sobre UART_CONSOLA. Queda independiente de la BSP, que es lo que
 * corresponde para un programa cuyo unico proposito es diagnosticar.
 */

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
