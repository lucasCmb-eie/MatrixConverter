

proc generate {drv_handle} {
	xdefine_include_file $drv_handle "xparameters.h" "AXI_Modulador" "NUM_INSTANCES" "DEVICE_ID"  "C_S_AXI_PARAMS_BASEADDR" "C_S_AXI_PARAMS_HIGHADDR"
}
