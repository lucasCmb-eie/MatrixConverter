# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "FRAC_BITS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "INT_BITS" -parent ${Page_0}


}

proc update_PARAM_VALUE.FRAC_BITS { PARAM_VALUE.FRAC_BITS } {
	# Procedure called to update FRAC_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FRAC_BITS { PARAM_VALUE.FRAC_BITS } {
	# Procedure called to validate FRAC_BITS
	return true
}

proc update_PARAM_VALUE.INT_BITS { PARAM_VALUE.INT_BITS } {
	# Procedure called to update INT_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INT_BITS { PARAM_VALUE.INT_BITS } {
	# Procedure called to validate INT_BITS
	return true
}


proc update_MODELPARAM_VALUE.INT_BITS { MODELPARAM_VALUE.INT_BITS PARAM_VALUE.INT_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INT_BITS}] ${MODELPARAM_VALUE.INT_BITS}
}

proc update_MODELPARAM_VALUE.FRAC_BITS { MODELPARAM_VALUE.FRAC_BITS PARAM_VALUE.FRAC_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FRAC_BITS}] ${MODELPARAM_VALUE.FRAC_BITS}
}

