

proc generate {drv_handle} {
	xdefine_include_file $drv_handle "xparameters.h" "AXI_Promediador" "NUM_INSTANCES" "DEVICE_ID"  "C_S0_AXI_PROMEDIOS_BASEADDR" "C_S0_AXI_PROMEDIOS_HIGHADDR"
}
