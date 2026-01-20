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

#include <stdio.h>
#include <xstatus.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xil_io.h"
#include "xgpio.h"
#include "xgpiops.h"
#include "xuartps.h"

// 1. IDs de Dispositivos
#define INTC_DEVICE_BaseAddr               XPAR_INTC_BASEADDR

#define UART_MEDICIONES               XPS_UART0_BASEADDR
#define GPIO_ENABLE_MUESTREO          XPAR_AXI_GPIO_ENABLEMUESTREO_BASEADDR
#define GPIO_RST                      XPAR_AXI_GPIO_RST_BASEADDR
#define GPIO_ENABLE_SVM               XPAR_AXI_GPIO_ENABLESVM_BASEADDR

#define PL_INTERRUPT_ID               61 //Sale del Technical manual del Zynq7000 - IRQ_F2P[0:0]

// 3. Direcciones Base de tus IPs propios (AXI Lite)
#define AXI_TensionesEntrada          XPAR_AXI_PROMEDIADOR_0_BASEADDR
#define AXI_CorrientesCarga           XPAR_AXI_PROMEDIADOR_CORRIENTESRL_BASEADDR
#define AXI_ParamsSVM                 XPAR_AXI_SVM_0_BASEADDR
#define AXI_ParamsRL                  XPAR_AXI_TRIRL_0_BASEADDR

#define REG_FaseU            0   // slv_reg0
#define REG_FaseV            4   // slv_reg1
#define REG_FaseW            8   // slv_reg2

//Constantes matematicas
const float Q24_TO_FLOAT = 1.0f / 16777216.0f;

//GPIOS de control en el PL
XGpio EnableMuestreo;
XGpio EnableSVM;
XGpio RstACSource;

//Controlador de Interrupciones 
XScuGic IntcInstance;

//Comunicacion UART
XUartPs UartPcInst;

// Buffer para envío UART (Cabecera + 2 Floats = 10 bytes)
u8 SendBuffer[10];

void ISR_Handler(void *CallbackRef);

int main()
{
    int Status;
    XUartPs_Config *ConfigUartMediciones;
    XScuGic_Config *ConfigIntc;
    
    init_platform();

    print("Hello World\n\r");
    print("Successfully ran Hello World application");

#pragma region GPIO
    //Inicializacion de GPIO
    Status = XGpio_Initialize(&EnableMuestreo, GPIO_ENABLE_MUESTREO);
    if (Status != XST_SUCCESS) print("Fallo GPIO MUESTREO");
    XGpio_SetDataDirection(&EnableMuestreo, 1, 0x00); // Canal 1 como Salida


    Status = XGpio_Initialize(&EnableSVM, GPIO_ENABLE_SVM);
    if (Status != XST_SUCCESS) print("Fallo GPIO ENABLE SVM");
    XGpio_SetDataDirection(&EnableSVM, 1, 0x00);

    Status = XGpio_Initialize(&RstACSource, GPIO_RST);
    if (Status != XST_SUCCESS) print("Fallo GPIO RST SVM");
    XGpio_SetDataDirection(&RstACSource, 1, 0x00);
#pragma endregion

#pragma region UART
    //Inicializacion de PS UART - Para enviar valores muestreados
    ConfigUartMediciones = XUartPs_LookupConfig(UART_MEDICIONES);
    Status = XUartPs_CfgInitialize(&UartPcInst, ConfigUartMediciones, ConfigUartMediciones -> BaseAddress);
    if (Status != XST_SUCCESS) print("Fallo config UART Mediciones");
    XUartPs_SetBaudRate(&UartPcInst, 921600);
    XUartPs_SetOperMode(&UartPcInst, XUARTPS_OPER_MODE_NORMAL);
#pragma endregion UART

#pragma region PL -> PS Interrupt
    //Inciailizacion de las Interrupciones del PL
    ConfigIntc = XScuGic_LookupConfig(INTC_DEVICE_BaseAddr);
    Status = XScuGic_CfgInitialize(&IntcInstance, ConfigIntc, ConfigIntc -> CpuBaseAddress);
    if (Status != XST_SUCCESS) print("Fallo config Interrupciones PL");
    
    XScuGic_SetPriorityTriggerType(&IntcInstance, PL_INTERRUPT_ID, 0x00, XGPIOPS_IRQ_TYPE_LEVEL_HIGH);

    //Conectar Interrupciones al GIC
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, 
                                (Xil_ExceptionHandler)XScuGic_InterruptHandler, 
                                &IntcInstance);

    
    // C. Conectar TU interrupción (PL) a TU función (ISR_Handler)
    Status = XScuGic_Connect(&IntcInstance, PL_INTERRUPT_ID, 
                            (Xil_ExceptionHandler)ISR_Handler, 
                            (void *)NULL);
    if (Status != XST_SUCCESS) print("Fallo al conectar Gic con el Handler"); 

    // D. Habilitar la interrupción específica (Trigger por flanco o nivel se define en Vivado)
    XScuGic_Enable(&IntcInstance, PL_INTERRUPT_ID);

    // E. Habilitar interrupciones globalmente en el procesador
    Xil_ExceptionEnable();
#pragma endregion

    cleanup_platform();
    return 0;
}

/************************** RUTINA DE INTERRUPCIÓN (ISR) **********************/
// Esta función se ejecuta AUTOMÁTICAMENTE cuando el PL levanta la línea IRQ
void ISR_Handler(void *CallbackRef)
{
    XScuGic_Disable(&IntcInstance, PL_INTERRUPT_ID);

    XScuGic_Enable(&IntcInstance, PL_INTERRUPT_ID);
}