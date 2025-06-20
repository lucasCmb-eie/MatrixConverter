# Check the version of Vivado used
set version_required "2023.2"
set ver [lindex [split $::env(XILINX_VIVADO) /] 3]
if {![string equal $ver $version_required]} {
  puts "###############################"
  puts "### Failed to build project ###"
  puts "###############################"
  puts "This project was designed for use with Vivado $version_required."
  puts "You are using Vivado $ver. Please install Vivado $version_required,"
  puts "or download the project sources from a commit of the Git repository"
  puts "that was intended for your version of Vivado ($ver)."
  return
}

set _xil_proj_name_ "project_ConmutMatrix"

set origin_dir [file dirname [info script]]
set orig_proj_dir "[file normalize "$origin_dir/$_xil_proj_name_"]"

puts "Direccion origen: $origin_dir"
puts "Direccion origen de projecto: $orig_proj_dir"

# Create project
create_project ${_xil_proj_name_} ./${_xil_proj_name_} -part xc7z007sclg400-1

# Set the directory path for the new project
set proj_dir [get_property directory [current_project]]

# Set project properties
set obj [current_project]
set_property -name "board_part" -value "realdigital.org:blackboard_d:part0:1.2" -objects $obj
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "enable_vhdl_2008" -value "1" -objects $obj
set_property -name "feature_set" -value "FeatureSet_Classic" -objects $obj
set_property -name "ip_cache_permissions" -value "read write" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${_xil_proj_name_}.cache/ip" -objects $obj
set_property -name "platform.board_id" -value "blackboard_d" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj
set_property -name "target_language" -value "VHDL" -objects $obj

# Set 'sources_1' fileset object
set obj [get_filesets sources_1]
set files [list \
  [file normalize "${origin_dir}/HW/src/hdl/red_sector.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/Modulador.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/Declaraciones.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/SENO_LT.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/AC_Source.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/matrixConmut_model.vhd"] \
 ]
 add_files -norecurse -fileset $obj $files

# Set IP repository paths
set obj [get_filesets sources_1]
set_property "ip_repo_paths" "[file normalize "$origin_dir/HW/src/ip/"]" $obj

# Rebuild user ip_repo's index before adding any source files
update_ip_catalog -rebuild


# Set 'sources_1' fileset properties
set obj [get_filesets sources_1]
set_property -name "top" -value "modulador" -objects $obj

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set obj [get_filesets constrs_1]

# # Empty (no sources present)

# Set 'constrs_1' fileset properties
set obj [get_filesets constrs_1]

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]
set files [list \
 [file normalize "${origin_dir}/HW/src/tb/Tb_Modulador_1.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/ncoLUT_tb.vhd"] \
]
add_files -norecurse -fileset $obj $files

# Set 'sim_1' fileset properties
set obj [get_filesets sim_1]
set_property -name "top" -value "tb_modulador" -objects $obj
set_property -name "top_lib" -value "xil_defaultlib" -objects $obj

# Create 'synth_1' run (if not found)
if {[string equal [get_runs -quiet synth_1] ""]} {
    create_run -name synth_1 -part xc7z007sclg400-1 -flow {Vivado Synthesis 2023} -strategy "Vivado Synthesis Defaults" -report_strategy {No Reports} -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2023" [get_runs synth_1]
}

set obj [get_runs synth_1]

# set the current synth run
current_run -synthesis [get_runs synth_1]

# Create 'impl_1' run (if not found)
if {[string equal [get_runs -quiet impl_1] ""]} {
    create_run -name impl_1 -part xc7z007sclg400-1 -flow {Vivado Implementation 2023} -strategy "Vivado Implementation Defaults" -report_strategy {No Reports} -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2023" [get_runs impl_1]
}
set obj [get_runs impl_1]

set_property -name "steps.write_bitstream.args.readback_file" -value "0" -objects $obj
set_property -name "steps.write_bitstream.args.verbose" -value "0" -objects $obj

# set the current impl run
current_run -implementation [get_runs impl_1]

puts "INFO: Project created:${_xil_proj_name_}"