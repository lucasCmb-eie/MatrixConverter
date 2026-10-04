#ifndef PSPL_H
#define PSPL_H
/*
 * pspl.h -- la plomeria PS<->PL del banco, compartida por los programas de
 * SW/ps/.
 *
 * POR QUE UN HEADER Y NO COPIAR Y PEGAR
 *
 * Este repo ya tiene una cicatriz de ese modo de falla: HW/src/ip/SinAXI/
 * guarda copias de VHDL que quedaron congeladas en 2026-02 mientras los
 * originales siguieron recibiendo correcciones, y CLAUDE.md tiene que advertir
 * explicitamente que no se espejen cambios ahi. Esta plomeria ya acumulo tres
 * bugs encontrados en la placa -- el programa que hablaba despues de tocar la
 * PL, el UART equivocado, y el orden del commit -- asi que duplicarla seria
 * garantizar que el proximo arreglo quede a medias.
 *
 * Todo es `static` o `static inline`: es header-only a proposito, para no
 * complicar el CMake de Vitis con un segundo archivo de fuente.
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
/*
 * Arma una captura y espera el disparo del modulador. Devuelve 0, o -1 si el
 * disparo nunca llego.
 *
 * La captura la pide el PS pero la DISPARA el modulador (via TrgRetardo), asi
 * que la foto cae siempre en el mismo punto de la ventana de PWM. Y es UNA sola
 * por armado: los disparos siguientes no repisan la foto, que es lo que permite
 * barrer el selector sin correr contra el Ts.
 */
static int armar_y_esperar(void)
{
    u32 vueltas;

    ctrl |= B_ARM;
    ctrl_aplicar();

    /* El indice 13 del selector devuelve el estado SIN pasar por los registros
     * de captura, justamente para poder poleerlo antes de que la foto exista.
     * Bit 0 = listo. */
    Xil_Out32(DATA_BASE + GPIO2_DATA, IDX_ESTADO);
    for (vueltas = 0u; vueltas < 1000000u; vueltas++) {
        if ((Xil_In32(DATA_BASE + GPIO_DATA) & 1u) != 0u) {
            return 0;
        }
    }
    ctrl &= ~B_ARM;
    ctrl_aplicar();
    return -1;
}

/* El desarmado ES el ack: limpia o_listo, que es nivel y no pulso. */
static void desarmar(void)
{
    ctrl &= ~B_ARM;
    ctrl_aplicar();
}

/*
 * Lee las ranuras listadas en `sel` (n de ellas) de la foto ya congelada.
 *
 * El selector es combinacional dentro de CaptureBank, y la BSP standalone mapea
 * 0x4000_0000-0x7FFF_FFFF como Device memory (no cacheable, no reordenable),
 * asi que la escritura del selector completa antes de la lectura siguiente: no
 * hace falta demora entre las dos.
 */
static void leer_ranuras(u32 *v, const u32 *sel, u32 n)
{
    u32 i;
    for (i = 0u; i < n; i++) {
        Xil_Out32(DATA_BASE + GPIO2_DATA, sel[i]);
        v[i] = Xil_In32(DATA_BASE + GPIO_DATA);
    }
}

/*
 * Captura SOLO las ranuras pedidas. Es la que usan las medidas largas: leer las
 * 20 cuando se necesitan 2 gasta 18 transacciones AXI por muestra y, sobre
 * todo, 10 veces mas memoria y 10 veces mas UART.
 */
static int capturar_sel(u32 *v, const u32 *sel, u32 n)
{
    if (armar_y_esperar() != 0) {
        return -1;
    }
    leer_ranuras(v, sel, n);
    desarmar();
    return 0;
}

/* Captura las 20 ranuras. */
static int capturar(u32 *v)
{
    static const u32 TODAS[N_RANURAS] = {
        0u, 1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u, 9u,
        10u, 11u, 12u, 13u, 14u, 15u, 16u, 17u, 18u, 19u
    };
    return capturar_sel(v, TODAS, N_RANURAS);
}


#endif /* PSPL_H */
