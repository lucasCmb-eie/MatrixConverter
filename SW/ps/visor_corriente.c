/*
 * visor_corriente.c -- manda la corriente de la planta RL a la PC, en tramas,
 * y recibe escalones de set point. Del otro lado: SW/python/VisorCorriente.py.
 *
 * El formato de trama y la aritmetica de los comandos estan ESPEJADOS en
 * SW/python/visor_trama.py y visor_metricas.py. Si se cambia uno, se cambia el
 * otro: los tests de Python verifican el espejo, no este archivo.
 *
 * Uso:
 *   1. en Validador/src/UserConfig.cmake, compilar este archivo en lugar de
 *      medir_criterios.c, y recompilar la app
 *   2. powershell -ExecutionPolicy Bypass -File SW\ps\programar_y_capturar.ps1 -SoloProgramar
 *   3. python SW/python/VisorCorriente.py COM12
 *
 * EL LOOP. Una trama por vuelta: (1) vaciar el RX de la UART buscando
 * comandos, que quedan PENDIENTES; (2) capturar 512 Ts de i_alfa, i_beta,
 * ref_alfa y ref_beta, aplicando los pendientes en la muestra 64 con el commit
 * SIN usleep, como el MODO 7 de medir_criterios.c, asi la trama muestra el
 * antes y el despues; (3) mandar la trama. Mientras se transmite (~0,72 s) no
 * se captura: cada trama es una foto, no un registro continuo.
 *
 * Por que se capturan ref_alfa/ref_beta y no se reconstruyen en la PC: los set
 * points dan amplitud y frecuencia, pero NO la fase del NCO de ControlLazo, y
 * sin la fase no se ve el desfase entre la corriente y su referencia.
 */

#include "pspl.h"

/* ------------------------------------------------- constantes del lazo
 * Las mismas de medir_criterios.c, ya validadas en la placa. */
#define V_FREC_IN    21475u       /* 50 Hz de entrada                        */
#define V_KP         169613184u   /* Kp = 10,1097 en Q8.24                   */
#define V_B          2718742u     /* b = Kr*Ts en Q8.24                      */
#define V_Q_MAX      14529495u    /* sqrt(3)/2 en Q8.24                      */
#define V_INV_VI     32396475u    /* 1/0,5179 en Q8.24                       */

/* ------------------------------------------------- set points y rangos */
#define A_INI_MICRO  60000u       /* 0,06 pu                                 */
#define F_INI_MHZ    50000u       /* 50 Hz                                   */
#define A_MAX_MICRO  110000u      /* 0,11 pu: el techo es ~0,113 con inv_vi  */
#define F_MIN_MICRO  5000000u     /* 5 Hz                                    */
#define F_MAX_MICRO  100000000u   /* 100 Hz                                  */

/* ------------------------------------------------- trama */
#define SYNC            0xA55A5AA5u
#define N_MUESTRAS      512u
#define N_CAN           4u
#define MUESTRA_ESCALON 64u
#define FL_ESCALON      1u
#define FL_RECHAZO      2u

#define UART_SR_RXEMPTY (1u << 1)

static const u32 RANURAS[N_CAN] = { 9u, 10u, 14u, 15u };   /* ia ib ra rb */
static const u32 RANURA_CLAMP[1] = { 3u };

static u32 datos[N_MUESTRAS][N_CAN];

/* estado de los set points */
static u32 amp_q;                 /* Q8.24, vigente                          */
static u32 f_mhz;                 /* vigente                                 */
static u32 pend_amp_q, pend_f_mhz;
static int hay_pend_amp, hay_pend_f;
static int rechazo;

/* ------------------------------------------------- aritmetica
 * ESPEJO: visor_metricas.espejo_*. Sin libm: sin() por Taylor hasta x^5; con
 * f <= 100 Hz, x <= 0,064 rad y el error es ~1e-12, muy debajo del LSB de
 * Q1.24. Los tests de Python lo comparan contra sin() en todo el rango. */
static u32 amp_q824(u32 micro)
{
    return (u32)(((u64)micro * 16777216u + 500000u) / 1000000u);
}

static u32 paso_ref_de(u32 mhz)
{
    double p = (double)mhz * 4294967296.0 / 1e10;
    return ((u32)(p + 0.5)) * 2048u;
}

static u32 k_de(u32 mhz)
{
    double x = 3.14159265358979323846 * ((double)mhz / 1000.0) * (2048.0 / 10e6);
    double x2 = x * x;
    double s = x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0));
    return (u32)(2.0 * s * 16777216.0 + 0.5);
}

/* ------------------------------------------------- comandos
 * ESPEJO: visor_trama.parsear_micro / interpretar_comando.
 * "<1..3 digitos>[.<1..6 digitos>]" a entero escalado por 1e6. */
static int parsear_micro(const char *s, u32 *out)
{
    u32 ent = 0u, frac = 0u;
    int nd = 0, nf = 0;

    while (*s == ' ') { s++; }
    while (*s >= '0' && *s <= '9') {
        if (++nd > 3) { return -1; }
        ent = ent * 10u + (u32)(*s - '0');
        s++;
    }
    if (nd == 0) { return -1; }
    if (*s == '.') {
        s++;
        while (*s >= '0' && *s <= '9') {
            if (++nf > 6) { return -1; }
            frac = frac * 10u + (u32)(*s - '0');
            s++;
        }
        if (nf == 0) { return -1; }
    }
    while (*s == ' ' || *s == '\r') { s++; }
    if (*s != '\0') { return -1; }
    for (; nf < 6; nf++) { frac *= 10u; }
    *out = ent * 1000000u + frac;
    return 0;
}

static void procesar_linea(const char *l)
{
    u32 v;

    if (l[0] == '\0' || l[1] != ' ' || parsear_micro(&l[2], &v) != 0) {
        rechazo = 1;
    } else if (l[0] == 'A' && v <= A_MAX_MICRO) {
        pend_amp_q = amp_q824(v);
        hay_pend_amp = 1;
    } else if (l[0] == 'F' && v >= F_MIN_MICRO && v <= F_MAX_MICRO) {
        pend_f_mhz = v / 1000u;
        hay_pend_f = 1;
    } else {
        rechazo = 1;
    }
}

/* Vacia el FIFO de RX (64 bytes) armando lineas. Se llama una vez por trama;
 * un comando son ~12 bytes, asi que entran cinco antes de desbordar. */
static void leer_comandos(void)
{
    static char linea[24];
    static u32 largo;
    static int desbordada;

    while ((Xil_In32(UART_CONSOLA + UART_SR) & UART_SR_RXEMPTY) == 0u) {
        char c = (char)(Xil_In32(UART_CONSOLA + UART_FIFO) & 0xFFu);
        if (c == '\n') {
            linea[largo] = '\0';
            if (desbordada) {
                rechazo = 1;
            } else {
                procesar_linea(linea);
            }
            largo = 0u;
            desbordada = 0;
        } else if (largo < sizeof(linea) - 1u) {
            linea[largo++] = c;
        } else {
            desbordada = 1;
        }
    }
}

/* ------------------------------------------------- envio */
static u32 suma;

static void tx_u32(u32 v)
{
    uart_putc(UART_CONSOLA, (char)(v & 0xFFu));
    uart_putc(UART_CONSOLA, (char)((v >> 8) & 0xFFu));
    uart_putc(UART_CONSOLA, (char)((v >> 16) & 0xFFu));
    uart_putc(UART_CONSOLA, (char)((v >> 24) & 0xFFu));
}

static void tx_sum(u32 v)
{
    suma += v;
    tx_u32(v);
}

/* ------------------------------------------------- arranque */
static int arrancar(void)
{
    u32 clamp;

    /* Autoverificacion de la aritmetica contra los valores YA VALIDADOS en la
     * placa (medir_criterios.c). Es la unica prueba posible del lado C sin un
     * compilador de host. */
    if (amp_q824(A_INI_MICRO) != 1006633u || paso_ref_de(F_INI_MHZ) != 43980800u
            || k_de(F_INI_MHZ) != 1079257u) {
        con_str("# ERROR: la aritmetica de set points no da los valores validados\r\n");
        return -1;
    }
    amp_q = amp_q824(A_INI_MICRO);
    f_mhz = F_INI_MHZ;

    /* Igual que medir_criterios.c: modulador habilitado ANTES del commit (el
     * commit cae en o_trg_calculo, que lo genera el modulador) y datapath en
     * reset para que el lazo no corra con los defaults. */
    ctrl = B_RST | B_EN;
    ctrl_aplicar();
    Xil_Out32(CTRL_BASE + GPIO2_DATA, 0u);
    Xil_Out32(DATA_BASE + GPIO2_DATA, 0u);

    sp_escribir(SP_FREC_IN,  V_FREC_IN);
    sp_escribir(SP_PASO_REF, paso_ref_de(f_mhz));
    sp_escribir(SP_AMP_REF,  amp_q);
    sp_escribir(SP_K,        k_de(f_mhz));
    sp_escribir(SP_KP,       V_KP);
    sp_escribir(SP_B,        V_B);
    sp_escribir(SP_PHI_I,    0u);
    sp_escribir(SP_Q_MAX,    V_Q_MAX);
    sp_escribir(SP_INV_VI,   V_INV_VI);
    sp_escribir(SP_FREEZE,   1u);         /* anti-windup habilitado          */
    /* i_alfa/i_beta y ref_* son valores del lazo, uno por Ts: no dependen de
     * en que punto de la ventana de PWM se mire. */
    sp_escribir(SP_RETARDO,  0u);
    sp_commit();

    ctrl &= ~B_RST;
    ctrl_aplicar();
    usleep(300000);                       /* regimen: 60 ms de sobra         */

    if (capturar_sel(&clamp, RANURA_CLAMP, 1u) != 0) {
        con_str("# ERROR: no llego ningun o_trg_calculo.\r\n");
        return -1;
    }
    if ((clamp & 0xFFFFu) != 0u) {
        con_str("# ERROR: clamp = ");
        con_hex(clamp & 0xFFFFu);
        con_str(" -- CtrlRegs rechazo un set point.\r\n");
        return -1;
    }
    return 0;
}

/* ------------------------------------------------- una trama */
static int capturar_trama(u32 *flags, u32 *amp_prev, u32 *f_prev)
{
    u32 n;
    int escalon;

    leer_comandos();
    escalon = hay_pend_amp || hay_pend_f;
    *amp_prev = amp_q;
    *f_prev = f_mhz;
    *flags = 0u;

    for (n = 0u; n < N_MUESTRAS; n++) {
        if (escalon && n == MUESTRA_ESCALON) {
            /* Sin usleep: el commit cae en el proximo o_trg_calculo, el mismo
             * que dispara la captura siguiente. paso_ref y k van juntos en el
             * mismo commit, que es para lo que existe el shadow. */
            if (hay_pend_amp) {
                amp_q = pend_amp_q;
                sp_escribir(SP_AMP_REF, amp_q);
            }
            if (hay_pend_f) {
                f_mhz = pend_f_mhz;
                sp_escribir(SP_PASO_REF, paso_ref_de(f_mhz));
                sp_escribir(SP_K, k_de(f_mhz));
            }
            sp_escribir(SP_COMMIT, 0u);
            hay_pend_amp = 0;
            hay_pend_f = 0;
            *flags |= FL_ESCALON;
        }
        if (capturar_sel(datos[n], RANURAS, N_CAN) != 0) {
            con_str("\r\n# ERROR: se corto el disparo en la muestra ");
            con_dec(n);
            con_str("\r\n");
            return -1;
        }
    }
    if (rechazo) {
        *flags |= FL_RECHAZO;
        rechazo = 0;
    }
    return 0;
}

static void enviar_trama(u32 contador, u32 flags, u32 amp_prev, u32 f_prev, u32 clamp)
{
    u32 n, c;

    suma = 0u;
    tx_u32(SYNC);
    tx_sum(contador);
    tx_sum(amp_q);
    tx_sum(f_mhz);
    tx_sum(flags);
    tx_sum((flags & FL_ESCALON) ? MUESTRA_ESCALON : 0u);
    tx_sum(amp_prev);
    tx_sum(f_prev);
    tx_sum(clamp & 0xFFFFu);
    tx_sum(N_MUESTRAS);
    for (n = 0u; n < N_MUESTRAS; n++) {
        for (c = 0u; c < N_CAN; c++) {
            tx_sum(datos[n][c]);
        }
    }
    tx_u32(suma);
}

int main(void)
{
    u32 contador = 0u;
    u32 flags, amp_prev, f_prev, clamp;

    uart_puts(UART0_BASE, "\r\n# ---- visor_corriente ---- UART0 (MIO 14..15)\r\n");
    uart_puts(UART1_BASE, "\r\n# ---- visor_corriente ---- UART1 (MIO 48..49)\r\n");

    if (arrancar() != 0) {
        return 1;
    }
    con_str("# en regimen, mandando tramas\r\n");

    for (;;) {
        if (capturar_trama(&flags, &amp_prev, &f_prev) != 0) {
            usleep(1000000);
            continue;
        }
        if (capturar_sel(&clamp, RANURA_CLAMP, 1u) != 0) {
            clamp = 0xFFFFu;      /* imposible en regimen: que se vea en rojo */
        }
        enviar_trama(contador, flags, amp_prev, f_prev, clamp);
        contador++;
    }
}
