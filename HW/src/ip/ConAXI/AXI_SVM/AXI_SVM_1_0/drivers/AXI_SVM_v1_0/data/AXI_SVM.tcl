

proc generate {drv_handle} {
	xdefine_include_file $drv_handle "xparameters.h" "AXI_SVM" "NUM_INSTANCES" "DEVICE_ID"  "C_S0_AXI_PARAMETROS_BASEADDR" "C_S0_AXI_PARAMETROS_HIGHADDR" "C_S1_AXI_CTRL_MUESTREO_BASEADDR" "C_S1_AXI_CTRL_MUESTREO_HIGHADDR"
}
