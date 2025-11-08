
################################################################
# This is a generated script based on design: test_Trifa_Clark_PhaseSaw
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2023.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source test_Trifa_Clark_PhaseSaw_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z007sclg400-1
   set_property BOARD_PART realdigital.org:blackboard_d:part0:1.2 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name test_Trifa_Clark_PhaseSaw

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:user:AC_Source_wrapper:1.0\
xilinx.com:user:TClark_wrapper:1.0\
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:user:SVM_wrapper:1.0\
xilinx.com:user:RL_wrapper:1.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports

  # Create ports
  set pl_clock [ create_bd_port -dir I -type clk -freq_hz 100000000 pl_clock ]
  set_property -dict [ list \
   CONFIG.PHASE {0.0} \
 ] $pl_clock
  set reset_rtl [ create_bd_port -dir I -type rst reset_rtl ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $reset_rtl
  set alfa_Vi [ create_bd_port -dir O -from 31 -to 0 alfa_Vi ]
  set i_al_o_0 [ create_bd_port -dir I -from 10 -to 0 i_al_o_0 ]
  set i_be_i_0 [ create_bd_port -dir I -from 10 -to 0 i_be_i_0 ]
  set i_q_i_0 [ create_bd_port -dir I -from 8 -to 0 i_q_i_0 ]
  set i_phi_i_0 [ create_bd_port -dir I -from 10 -to 0 i_phi_i_0 ]
  set i_c_a0_0 [ create_bd_port -dir I -from 31 -to 0 i_c_a0_0 ]
  set i_c_a1_0 [ create_bd_port -dir I -from 31 -to 0 i_c_a1_0 ]
  set i_c_b1_0 [ create_bd_port -dir I -from 31 -to 0 i_c_b1_0 ]
  set alfa_Io [ create_bd_port -dir O -from 31 -to 0 alfa_Io ]
  set beta_Io [ create_bd_port -dir O -from 31 -to 0 beta_Io ]
  set o_U_0 [ create_bd_port -dir O -from 31 -to 0 o_U_0 ]
  set o_V_0 [ create_bd_port -dir O -from 31 -to 0 o_V_0 ]
  set o_W_0 [ create_bd_port -dir O -from 31 -to 0 o_W_0 ]

  # Create instance: AC_Source_wrapper_0, and set properties
  set AC_Source_wrapper_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:AC_Source_wrapper:1.0 AC_Source_wrapper_0 ]

  # Create instance: TClark_wrapper_Vi, and set properties
  set TClark_wrapper_Vi [ create_bd_cell -type ip -vlnv xilinx.com:user:TClark_wrapper:1.0 TClark_wrapper_Vi ]

  # Create instance: clk_wiz, and set properties
  set clk_wiz [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz ]
  set_property -dict [list \
    CONFIG.CLK_IN1_BOARD_INTERFACE {pl_clock} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $clk_wiz


  # Create instance: rst_clk_wiz_100M, and set properties
  set rst_clk_wiz_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_100M ]

  # Create instance: SVM_wrapper_0, and set properties
  set SVM_wrapper_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:SVM_wrapper:1.0 SVM_wrapper_0 ]

  # Create instance: TClark_wrapper_Io, and set properties
  set TClark_wrapper_Io [ create_bd_cell -type ip -vlnv xilinx.com:user:TClark_wrapper:1.0 TClark_wrapper_Io ]

  # Create instance: RL_wrapper_0, and set properties
  set RL_wrapper_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:RL_wrapper:1.0 RL_wrapper_0 ]

  # Create port connections
  connect_bd_net -net AC_Source_wrapper_0_o_U [get_bd_pins AC_Source_wrapper_0/o_U] [get_bd_pins TClark_wrapper_Vi/i_U] [get_bd_pins SVM_wrapper_0/i_U]
  connect_bd_net -net AC_Source_wrapper_0_o_V [get_bd_pins AC_Source_wrapper_0/o_V] [get_bd_pins TClark_wrapper_Vi/i_V] [get_bd_pins SVM_wrapper_0/i_V]
  connect_bd_net -net AC_Source_wrapper_0_o_W [get_bd_pins AC_Source_wrapper_0/o_W] [get_bd_pins TClark_wrapper_Vi/i_W] [get_bd_pins SVM_wrapper_0/i_W]
  connect_bd_net -net Net [get_bd_pins clk_wiz/clk_out1] [get_bd_pins AC_Source_wrapper_0/i_clk] [get_bd_pins rst_clk_wiz_100M/slowest_sync_clk] [get_bd_pins SVM_wrapper_0/i_clk] [get_bd_pins RL_wrapper_0/i_clk]
  connect_bd_net -net RL_wrapper_0_o_U [get_bd_pins RL_wrapper_0/o_U] [get_bd_ports o_U_0] [get_bd_pins TClark_wrapper_Io/i_U]
  connect_bd_net -net RL_wrapper_0_o_V [get_bd_pins RL_wrapper_0/o_V] [get_bd_ports o_V_0] [get_bd_pins TClark_wrapper_Io/i_V]
  connect_bd_net -net RL_wrapper_0_o_W [get_bd_pins RL_wrapper_0/o_W] [get_bd_ports o_W_0] [get_bd_pins TClark_wrapper_Io/i_W]
  connect_bd_net -net SVM_wrapper_0_o_U [get_bd_pins SVM_wrapper_0/o_U] [get_bd_pins RL_wrapper_0/i_U]
  connect_bd_net -net SVM_wrapper_0_o_V [get_bd_pins SVM_wrapper_0/o_V] [get_bd_pins RL_wrapper_0/i_V]
  connect_bd_net -net SVM_wrapper_0_o_W [get_bd_pins SVM_wrapper_0/o_W] [get_bd_pins RL_wrapper_0/i_W]
  connect_bd_net -net TClark_wrapper_0_o_alfa [get_bd_pins TClark_wrapper_Vi/o_alfa] [get_bd_ports alfa_Vi]
  connect_bd_net -net TClark_wrapper_Io_o_alfa [get_bd_pins TClark_wrapper_Io/o_alfa] [get_bd_ports alfa_Io]
  connect_bd_net -net TClark_wrapper_Io_o_beta [get_bd_pins TClark_wrapper_Io/o_beta] [get_bd_ports beta_Io]
  connect_bd_net -net clk_wiz_locked [get_bd_pins clk_wiz/locked] [get_bd_pins rst_clk_wiz_100M/dcm_locked]
  connect_bd_net -net i_al_o_0_1 [get_bd_ports i_al_o_0] [get_bd_pins SVM_wrapper_0/i_al_o]
  connect_bd_net -net i_be_i_0_1 [get_bd_ports i_be_i_0] [get_bd_pins SVM_wrapper_0/i_be_i]
  connect_bd_net -net i_c_a0_0_1 [get_bd_ports i_c_a0_0] [get_bd_pins RL_wrapper_0/i_c_a0]
  connect_bd_net -net i_c_a1_0_1 [get_bd_ports i_c_a1_0] [get_bd_pins RL_wrapper_0/i_c_a1]
  connect_bd_net -net i_c_b1_0_1 [get_bd_ports i_c_b1_0] [get_bd_pins RL_wrapper_0/i_c_b1]
  connect_bd_net -net i_phi_i_0_1 [get_bd_ports i_phi_i_0] [get_bd_pins SVM_wrapper_0/i_phi_i]
  connect_bd_net -net i_q_i_0_1 [get_bd_ports i_q_i_0] [get_bd_pins SVM_wrapper_0/i_q_i]
  connect_bd_net -net pl_clock_1 [get_bd_ports pl_clock] [get_bd_pins clk_wiz/clk_in1]
  connect_bd_net -net reset_rtl_1 [get_bd_ports reset_rtl] [get_bd_pins clk_wiz/reset] [get_bd_pins rst_clk_wiz_100M/ext_reset_in]
  connect_bd_net -net rst_clk_wiz_100M_peripheral_aresetn [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn] [get_bd_pins AC_Source_wrapper_0/i_rst] [get_bd_pins SVM_wrapper_0/i_enable] [get_bd_pins RL_wrapper_0/i_rst]

  # Create address segments


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


