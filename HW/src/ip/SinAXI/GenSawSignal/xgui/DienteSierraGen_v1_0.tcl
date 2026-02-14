# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  ipgui::add_page $IPINST -name "Page 0"


}

proc update_PARAM_VALUE.FRAC_BITS { PARAM_VALUE.FRAC_BITS } {
	# Procedure called to update FRAC_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FRAC_BITS { PARAM_VALUE.FRAC_BITS } {
	# Procedure called to validate FRAC_BITS
	return true
}

proc update_PARAM_VALUE.G_CLK_FREQ { PARAM_VALUE.G_CLK_FREQ } {
	# Procedure called to update G_CLK_FREQ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_CLK_FREQ { PARAM_VALUE.G_CLK_FREQ } {
	# Procedure called to validate G_CLK_FREQ
	return true
}

proc update_PARAM_VALUE.G_SAW_FREQ { PARAM_VALUE.G_SAW_FREQ } {
	# Procedure called to update G_SAW_FREQ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_SAW_FREQ { PARAM_VALUE.G_SAW_FREQ } {
	# Procedure called to validate G_SAW_FREQ
	return true
}

proc update_PARAM_VALUE.INT_BITS { PARAM_VALUE.INT_BITS } {
	# Procedure called to update INT_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INT_BITS { PARAM_VALUE.INT_BITS } {
	# Procedure called to validate INT_BITS
	return true
}


proc update_MODELPARAM_VALUE.G_CLK_FREQ { MODELPARAM_VALUE.G_CLK_FREQ PARAM_VALUE.G_CLK_FREQ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_CLK_FREQ}] ${MODELPARAM_VALUE.G_CLK_FREQ}
}

proc update_MODELPARAM_VALUE.G_SAW_FREQ { MODELPARAM_VALUE.G_SAW_FREQ PARAM_VALUE.G_SAW_FREQ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_SAW_FREQ}] ${MODELPARAM_VALUE.G_SAW_FREQ}
}

proc update_MODELPARAM_VALUE.INT_BITS { MODELPARAM_VALUE.INT_BITS PARAM_VALUE.INT_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INT_BITS}] ${MODELPARAM_VALUE.INT_BITS}
}

proc update_MODELPARAM_VALUE.FRAC_BITS { MODELPARAM_VALUE.FRAC_BITS PARAM_VALUE.FRAC_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FRAC_BITS}] ${MODELPARAM_VALUE.FRAC_BITS}
}

