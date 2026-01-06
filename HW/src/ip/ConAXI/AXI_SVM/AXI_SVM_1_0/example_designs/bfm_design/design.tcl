proc create_ipi_design { offsetfile design_name } {
	create_bd_design $design_name
	open_bd_design $design_name

	# Create Clock and Reset Ports
	set ACLK [ create_bd_port -dir I -type clk ACLK ]
	set_property -dict [ list CONFIG.FREQ_HZ {100000000} CONFIG.PHASE {0.000} CONFIG.CLK_DOMAIN "${design_name}_ACLK" ] $ACLK
	set ARESETN [ create_bd_port -dir I -type rst ARESETN ]
	set_property -dict [ list CONFIG.POLARITY {ACTIVE_LOW}  ] $ARESETN
	set_property CONFIG.ASSOCIATED_RESET ARESETN $ACLK

	# Create instance: AXI_SVM_0, and set properties
	set AXI_SVM_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:AXI_SVM:1.0 AXI_SVM_0]

	# Create instance: master_0, and set properties
	set master_0 [ create_bd_cell -type ip -vlnv  xilinx.com:ip:axi_vip master_0]
	set_property -dict [ list CONFIG.PROTOCOL {AXI4LITE} CONFIG.INTERFACE_MODE {MASTER} ] $master_0

	# Create interface connections
	connect_bd_intf_net [get_bd_intf_pins master_0/M_AXI ] [get_bd_intf_pins AXI_SVM_0/S0_AXI_PARAMETROS]

	# Create port connections
	connect_bd_net -net aclk_net [get_bd_ports ACLK] [get_bd_pins master_0/ACLK] [get_bd_pins AXI_SVM_0/S0_AXI_PARAMETROS_ACLK]
	connect_bd_net -net aresetn_net [get_bd_ports ARESETN] [get_bd_pins master_0/ARESETN] [get_bd_pins AXI_SVM_0/S0_AXI_PARAMETROS_ARESETN]
	make_bd_intf_pins_external  [get_bd_intf_pins AXI_SVM_0/M0_AXIS_TENSIONES_ENTRADA]
	# Create port connections
	connect_bd_net -net aclk_net [get_bd_ports ACLK] [get_bd_pins AXI_SVM_0/M0_AXIS_TENSIONES_ENTRADA_ACLK]
	connect_bd_net -net aresetn_net [get_bd_ports ARESETN] [get_bd_pins AXI_SVM_0/M0_AXIS_TENSIONES_ENTRADA_ARESETN]

	# Create instance: master_1, and set properties
	set master_1 [ create_bd_cell -type ip -vlnv  xilinx.com:ip:axi_vip master_1]
	set_property -dict [ list CONFIG.PROTOCOL {AXI4LITE} CONFIG.INTERFACE_MODE {MASTER} ] $master_1

	# Create interface connections
	connect_bd_intf_net [get_bd_intf_pins master_1/M_AXI ] [get_bd_intf_pins AXI_SVM_0/S1_AXI_CTRL_MUESTREO]

	# Create port connections
	connect_bd_net -net aclk_net [get_bd_ports ACLK] [get_bd_pins master_1/ACLK] [get_bd_pins AXI_SVM_0/S1_AXI_CTRL_MUESTREO_ACLK]
	connect_bd_net -net aresetn_net [get_bd_ports ARESETN] [get_bd_pins master_1/ARESETN] [get_bd_pins AXI_SVM_0/S1_AXI_CTRL_MUESTREO_ARESETN]
set_property target_simulator XSim [current_project]
set_property -name {xsim.simulate.runtime} -value {100ms} -objects [get_filesets sim_1]

	# Auto assign address
	assign_bd_address

	# Copy all address to interface_address.vh file
	set bd_path [file dirname [get_property NAME [get_files ${design_name}.bd]]]
	upvar 1 $offsetfile offset_file
	set offset_file "${bd_path}/AXI_SVM_tb_include.svh"
	set fp [open $offset_file "w"]
	puts $fp "`ifndef AXI_SVM_tb_include_vh_"
	puts $fp "`define AXI_SVM_tb_include_vh_\n"
	puts $fp "//Configuration current bd names"
	puts $fp "`define BD_NAME ${design_name}"
	puts $fp "`define BD_INST_NAME ${design_name}_i"
	puts $fp "`define BD_WRAPPER ${design_name}_wrapper\n"
	puts $fp "//Configuration address parameters"

	puts $fp "`endif"
	close $fp
}

set ip_path [file dirname [file normalize [get_property XML_FILE_NAME [ipx::get_cores xilinx.com:user:AXI_SVM:1.0]]]]
set test_bench_file ${ip_path}/example_designs/bfm_design/AXI_SVM_tb.sv
set interface_address_vh_file ""

# Set IP Repository and Update IP Catalogue 
set repo_paths [get_property ip_repo_paths [current_fileset]] 
if { [lsearch -exact -nocase $repo_paths $ip_path ] == -1 } {
	set_property ip_repo_paths "$ip_path [get_property ip_repo_paths [current_fileset]]" [current_fileset]
	update_ip_catalog
}

set design_name ""
set all_bd {}
set all_bd_files [get_files *.bd -quiet]
foreach file $all_bd_files {
set file_name [string range $file [expr {[string last "/" $file] + 1}] end]
set bd_name [string range $file_name 0 [expr {[string last "." $file_name] -1}]]
lappend all_bd $bd_name
}

for { set i 1 } { 1 } { incr i } {
	set design_name "AXI_SVM_bfm_${i}"
	if { [lsearch -exact -nocase $all_bd $design_name ] == -1 } {
		break
	}
}

create_ipi_design interface_address_vh_file ${design_name}
validate_bd_design

set wrapper_file [make_wrapper -files [get_files ${design_name}.bd] -top -force]
import_files -force -norecurse $wrapper_file
update_compile_order -fileset [current_fileset]
update_compile_order -fileset [current_fileset -simset]

set_property SOURCE_SET sources_1 [get_filesets sim_1]
import_files -fileset sim_1 -norecurse -force $test_bench_file
remove_files -quiet -fileset sim_1 AXI_SVM_tb_include.vh
import_files -fileset sim_1 -norecurse -force $interface_address_vh_file
set_property top AXI_SVM_tb [get_filesets sim_1]
set_property top_lib {} [get_filesets sim_1]
set_property top_file {} [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
