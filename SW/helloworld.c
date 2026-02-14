/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * helloworld.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <stdint.h>
#include <stdio.h>
#include <xgpio_l.h>
#include <xstatus.h>
#include <stdbool.h>
#include <math.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_io.h"
#include "xgpio.h"
#include "xgpiops.h"
#include "xuartps.h"

//Constantes para comunicacionAXI
#define INTC_DEVICE_BaseAddr          XPAR_INTC_BASEADDR

#define UART_MEDICIONES_ADRR          XPAR_UART1_BASEADDR
#define GPIO_CONTROLES_ADDR           XPAR_XGPIO_0_BASEADDR
#define GPIO_SVM                      1

#define PL_INTERRUPT_ID               61 //Sale del Technical manual del Zynq7000 - IRQ_F2P[0:0]

#define AXI_TENSIONES_ENT          0x43c30000
#define AXI_CORRIENTES             0x43c10000
#define AXI_PARAMETROS_SVM         XPAR_AXI_SVM_V2_0_BASEADDR //
#define AXI_COEFICIENTES_RL        XPAR_AXI_RL_BASEADDR

#define SVM_ALFA_O    0x00
#define SVM_BETA_I    0x04
#define SVM_Q_I     0x08
#define SVM_PHI_I   0x0C
#define SVM_FASE_U  0x10
#define SVM_FASE_V  0x14
#define SVM_FASE_W  0x18

#define RL_COEF_a0  0x00
#define RL_COEF_a1  0x04
#define RL_COEF_b0  0x08
#define RL_CORR_U   0x0C
#define RL_CORR_V   0x10
#define RL_CORR_W   0x14

//Constantes matematicas

// Formato Q8.24
// 1 / sqrt(3) ~= 0.577350269
// 0.577350269 * 2^24 = 9686330
#define INV_SQRT3_Q24   9686330 

// Factor de Amplificacion de Clark (2/3) en Q24 = 0.66666 * 2^24
#define AMPL_CLARK_Q24  11184810

// 1.0/3.0 ~= 0.333333333 * 2^24
#define ONE_THIRD_Q24   5592405

// CORDIC: Iteraciones
#define CORDIC_ITERATIONS 14 
#define BAUD_RATE_PC    115200
// #define CANTD_MUESTRAS       10
// #define TWO_PI      (6.2831853071795864769f)
// #define INV_TWO_PI  (1.0f / TWO_PI)
// #define ANGLE_SCALE (2048.0f)

typedef union 
{
    float f;
    u8    b[4];
} FloatUnion;

typedef union 
{
    int32_t i;
    u8    b[4];
} Int32Union;

typedef struct 
{
    int32_t faseU;
    int32_t faseV;
    int32_t faseW;

    int32_t alphaClark;
    int32_t betaClark;
    int32_t zeroClark; 
    
} MedicionTrifasica;

typedef struct
{
    MedicionTrifasica TensionesEntrada;
    MedicionTrifasica CorrientesCargas;
    
    int32_t alfaOSVM;
    int32_t betaISVM;
    

} SistemaSVM;

//GPIOS de control en el PL
XGpio ControlesPL;
//SVM Canal 1 -- 1 -> Esta prendido
//Fuente AC y la RL Canal 2 -- 0 -> Esta prendido


//Controlador de Interrupciones 
XScuGic IntcInstance;

//Comunicacion UART
XUartPs UartPcInst;

// Buffer para envío UART (Cabecera + 2 Floats = 10 bytes)
u8 SendBuffer[14];
uint8_t contador = 0;
volatile bool leerDato_Flag = false;

void ISR_Handler(void *CallbackRef);
void Send_Trifasica_A_PC(SistemaSVM *medicion);
void CalculoTClark(MedicionTrifasica *medicion);
void LeerSignalsPL(SistemaSVM *sistema);
uint32_t Cordic_Atan2_Fixed(int32_t x, int32_t y);

static inline float q8_24_to_float(int32_t q)
{
    return (float)q * (1.0f / 16777216.0f);
}


/**************** TABLA CORDIC (Ángulos en Binary Degrees) ****************/
// Ángulos representados en un espacio donde 360 grados = 2^32 (4294967296)
// atan(2^-0) = 45.000 deg = 0x20000000
// atan(2^-1) = 26.565 deg = 0x12E4051D
// ...
static const int32_t cordic_atan_table[14] = {
    0x20000000, 0x12E4051D, 0x09FB385B, 0x051111D4,
    0x028B0D43, 0x0145D7E1, 0x00A2F983, 0x00517CC1,
    0x0028BE60, 0x00145F30, 0x000A2F98, 0x000517CC,
    0x00028BE6, 0x000145F3
};

MedicionTrifasica test;

int main()
{
    int Status;
    
    XUartPs_Config *ConfigUartMediciones;
    XScuGic_Config *ConfigIntc;
    SistemaSVM sistemaPL;
    
    init_platform();

    xil_printf("Inicializando la Configuracion\n\r");

    #pragma region GPIO
        //Inicializacion de GPIO
        Status = XGpio_Initialize(&ControlesPL, GPIO_CONTROLES_ADDR);
        if (Status != XST_SUCCESS) xil_printf("Fallo GPIO MUESTREO\n\r");
        XGpio_SetDataDirection(&ControlesPL, GPIO_SVM, 0x00); // Canal 1 como Salida
    #pragma endregion

    #pragma region UART
        //Inicializacion de PS UART - Para enviar valores muestreados
        ConfigUartMediciones = XUartPs_LookupConfig(UART_MEDICIONES_ADRR);
        Status = XUartPs_CfgInitialize(&UartPcInst, ConfigUartMediciones, ConfigUartMediciones -> BaseAddress);
        if (Status != XST_SUCCESS) xil_printf("Fallo config UART Mediciones\n\r");
        
        // Deshabilita todas las interrupciones del UART para evitar saltos inesperados
        XUartPs_SetInterruptMask(&UartPcInst, 0);

        // Limpia las banderas de estado pendientes
        XUartPs_WriteReg(UartPcInst.Config.BaseAddress, XUARTPS_ISR_OFFSET, XUARTPS_IXR_MASK);
        
        XUartPs_SetBaudRate(&UartPcInst, BAUD_RATE_PC);
        XUartPs_SetOperMode(&UartPcInst, XUARTPS_OPER_MODE_NORMAL);

        
    #pragma endregion UART

    #pragma region PL -> PS Interrupt
    //Inciailizacion de las Interrupciones del PL
    ConfigIntc = XScuGic_LookupConfig(INTC_DEVICE_BaseAddr);
    Status = XScuGic_CfgInitialize(&IntcInstance, ConfigIntc, ConfigIntc -> CpuBaseAddress);
    if (Status != XST_SUCCESS) xil_printf("Fallo config Interrupciones PL\n\r");
    
    XScuGic_SetPriorityTriggerType(&IntcInstance, PL_INTERRUPT_ID, 0xA0, 0x3);

    //Conectar Interrupciones al GIC
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, 
                                (Xil_ExceptionHandler)XScuGic_InterruptHandler, 
                                &IntcInstance);

    
    // C. Conectar TU interrupción (PL) a TU función (ISR_Handler)
    Status = XScuGic_Connect(&IntcInstance, PL_INTERRUPT_ID, 
                            (Xil_ExceptionHandler)ISR_Handler, 
                            (void *)NULL);
    if (Status != XST_SUCCESS) xil_printf("Fallo al conectar Gic con el Handler\n\r"); 

    // D. Habilitar la interrupción específica (Trigger por flanco o nivel se define en Vivado)
    XScuGic_Enable(&IntcInstance, PL_INTERRUPT_ID);

    // E. Habilitar interrupciones globalmente en el procesador
    Xil_ExceptionEnable();
    #pragma endregion

    //InitPL();
    XGpio_DiscreteWrite(&ControlesPL, GPIO_SVM, 0x00);
    
    xil_printf("Sistema iniciado, comenzando enviode datos\n\r");
    
    //Activar SVM
    //XGpio_DiscreteWrite(&ControlesPL, GPIO_SVM, 0x01); // Al poner 1 se enciende el SVM

    // //Por el momento ponemos a Qi y Phi con los valores
    // Xil_Out32(AXI_PARAMETROS_SVM + SVM_PHI_I, 0x00);
    // Xil_Out32(AXI_PARAMETROS_SVM + SVM_Q_I, 0b000100000);

    while (true) 
    {
        int32_t test_U, test_V, test_W;

        test_U = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_U);
        test_V = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_V);
        test_W = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_W); 

        contador++;
        if (leerDato_Flag) 
        {
            leerDato_Flag = false;
               

            
            //Lectura de valores
            //LeerSignalsPL(&sistemaPL);
            
            // //Transformada de Clark + arctang2
            // CalculoTClark(&(sistemaPL.TensionesEntrada));
            // CalculoTClark(&(sistemaPL.TensionesEntrada));
            
            // //Cálculo de ángulo usando CORDIC
            // // CORDIC devuelve valor 0-2047 directamente
            // sistemaPL.alfaOSVM = Cordic_Atan2_Fixed(sistemaPL.CorrientesCargas.alphaClark, sistemaPL.CorrientesCargas.betaClark);
            // sistemaPL.betaISVM = Cordic_Atan2_Fixed(sistemaPL.TensionesEntrada.alphaClark, sistemaPL.TensionesEntrada.betaClark);

            // // 4. Escribir al PL
            // Xil_Out32(AXI_PARAMETROS_SVM + SVM_ALFA, sistemaPL.alfaOSVM);
            // Xil_Out32(AXI_PARAMETROS_SVM + SVM_BETA, sistemaPL.betaISVM);

            contador++;
            if(contador >= 20) // Envio datos cada 20 ciclos
            {
                //Envio de datos float
                Send_Trifasica_A_PC(&sistemaPL);
                //Reinicio de contadores
                contador = 0;   
            }
        }
    }
    
    cleanup_platform();
    return 0;
}

/************************** RUTINA DE INTERRUPCIÓN (ISR) **********************/
void ISR_Handler(void *CallbackRef)
{
    leerDato_Flag = true;
}

void Send_Trifasica_A_PC(SistemaSVM *sistema)
{
    // Int32Union floatU, floatV, floatW;
    FloatUnion floatU, floatV, floatW;
    // // Conversión "perezosa" (Lazy conversion): Solo convertimos cuando vamos a enviar
    floatU.f = q8_24_to_float(sistema->CorrientesCargas.faseU);
    floatV.f = q8_24_to_float(sistema->CorrientesCargas.faseV);
    floatW.f = q8_24_to_float(sistema->CorrientesCargas.faseW);
    
    xil_printf("Fase U:\n");
    printf("%f", floatU.f);
    xil_printf("Fase V:\n");
    printf("%f", floatV.f);
    xil_printf("Fase W:\n");
    printf("%f", floatW.f);
    // SendBuffer[0] = 0xAA;
    // SendBuffer[1] = 0xBB;

    // SendBuffer[2] = floatU.b[0];
    // SendBuffer[3] = floatU.b[1]; 
    // SendBuffer[4] = floatU.b[2];
    // SendBuffer[5] = floatU.b[3];

    // SendBuffer[6] = floatV.b[0]; SendBuffer[7] = floatV.b[1]; 
    // SendBuffer[8] = floatV.b[2]; SendBuffer[9] = floatV.b[3];

    // SendBuffer[10] = floatW.b[0]; SendBuffer[11] = floatW.b[1]; 
    // SendBuffer[12] = floatW.b[2]; SendBuffer[13] = floatW.b[3];

    // XUartPs_Send(&UartPcInst, SendBuffer, 6);
}

void LeerSignalsPL(SistemaSVM *sistema)
{
    sistema->TensionesEntrada.faseU = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_U);
    sistema->TensionesEntrada.faseV = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_V);
    sistema->TensionesEntrada.faseW = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_W);

    test.faseU = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_U);
    test.faseV = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_V);
    test.faseW = Xil_In32(AXI_TENSIONES_ENT + SVM_FASE_W); 

    // sistema->CorrientesCargas.faseU = Xil_In32(AXI_CORRIENTES + REG_FaseU);
    // sistema->CorrientesCargas.faseV = Xil_In32(AXI_CORRIENTES + REG_FaseV);
    // sistema->CorrientesCargas.faseW = Xil_In32(AXI_CORRIENTES + REG_FaseW);
    
}

void CalculoTClark(MedicionTrifasica *medicion)
{
    int64_t accum; // Usamos 64 bits para evitar desbordes en las sumas intermedias

    // Calculo de Componente Zero (Homopolar)
    // Formula: (U + V + W) / 3
    accum = (int64_t)medicion->faseU + medicion->faseV + medicion->faseW;
    medicion->zeroClark = (int32_t)((accum * ONE_THIRD_Q24) >> 24);

    // Calculo de Alpha (Completo)
    // Formula: 1/3 * (2*U - V - W)
    accum = ((int64_t)medicion->faseU << 1) - medicion->faseV - medicion->faseW; 
    // (U << 1) es igual a U * 2, pero más rápido y explícito
    
    medicion->alphaClark = (int32_t)((accum * ONE_THIRD_Q24) >> 24);

    //Calculo de Beta
    // Formula: 1/sqrt(3) * (V - W)
    accum = (int64_t)medicion->faseV - medicion->faseW;
    medicion->betaClark  = (int32_t)((accum * INV_SQRT3_Q24) >> 24);
}

/**************** ALGORITMO CORDIC (Fixed Point) ****************/
/* * Calcula atan2(y, x) y devuelve un ángulo escalado a 11 bits (0 a 2047)
 * Entrada: x, y en cualquier formato Q (mientras sean consistentes entre sí)
 */
uint32_t Cordic_Atan2_Fixed(int32_t x, int32_t y)
{
    int32_t angle_acc = 0;
    int32_t x_temp, y_temp;
    
    // 1. Pre-rotación para manejar cuadrantes (CORDIC trabaja bien en +/- 90)
    // Queremos llevar el vector al semiplano derecho (x > 0)
    if (x < 0) {
        // Rotar 180 grados
        x = -x;
        y = -y;
        angle_acc = 0x80000000; // Sumar 180 grados (bit más significativo)
    }

    // 2. Iteraciones CORDIC
    for (int i = 0; i < CORDIC_ITERATIONS; i++) {
        if (y >= 0) {
            // Rotar en sentido horario (restar ángulo) para acercar y a 0
            x_temp = x + (y >> i);
            y_temp = y - (x >> i);
            angle_acc += cordic_atan_table[i];
        } else {
            // Rotar en sentido antihorario (sumar ángulo)
            x_temp = x - (y >> i);
            y_temp = y + (x >> i);
            angle_acc -= cordic_atan_table[i];
        }
        x = x_temp;
        y = y_temp;
    }

    // angle_acc ahora tiene el ángulo en formato de 32 bits (todo el rango uint32)
    // Mapeo: 0x00000000 = 0 rad, 0xFFFFFFFF = 2pi rad aprox
    
    // 3. Escalar a 0-2047 (11 bits)
    // Desplazamos a la derecha 21 bits (32 - 11 = 21)
    // Usamos cast a unsigned para shift lógico
    uint32_t result = ((uint32_t)angle_acc) >> 21;
    
    return (result & 0x7FF); // Máscara de seguridad de 11 bits
}
