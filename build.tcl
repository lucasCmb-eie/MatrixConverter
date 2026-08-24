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
  [file normalize "${origin_dir}/HW/src/hdl/Modulador.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/AC_Source.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/matrixConmut.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/RL_fase.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/TransformadaClark.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/CORDIC_atan2.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/util/red_sector.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/util/sine_generator.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/util/sine_lut_pkg.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/util/Declaraciones.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/util/DienteSierraGen.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/wrappers/AC_Source_wrapper.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/wrappers/RL_wrapper.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/wrappers/SVM_wrapper.vhd"] \
  [file normalize "${origin_dir}/HW/src/hdl/wrappers/TClark_wrapper.vhd"] \
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
# NOTA: HW/src/constrs/ quedo sin archivos de restricciones versionados.
# Al agregar uno, listarlo aca; los que falten se omiten con aviso en vez de abortar.
set files [list]
foreach f $files {
  if {[file exists $f]} {
    add_files -norecurse -fileset $obj $f
  } else {
    puts "WARNING: constraint no encontrado, se omite: $f"
  }
}

# Set 'constrs_1' fileset properties
set obj [get_filesets constrs_1]

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]
set files [list \
 [file normalize "${origin_dir}/HW/src/tb/Tb_Modulador.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/ncoLUT_tb.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_RL.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/matrixConmut_tb.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/sine_generator_tb.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_TransformadaClark.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_CORDIC_atan2.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_SVM_Wrapper.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_SVM_FoutVar.vhd"] \
 [file normalize "${origin_dir}/HW/src/tb/tb_SVM_FinVar.vhd"] \
]
add_files -norecurse -fileset $obj $files

# Set 'sim_1' fileset properties
set obj [get_filesets sim_1]
set_property -name "top" -value "ncoLUT_tb" -objects $obj
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

# # Create block design
# # HW/src/bd/ ya no contiene scripts .tcl de block design. Lo unico presente es
# # HW/src/bd/test_ComunicPLPS/test_ComunicPLPS.bd (BD guardado, no script generador).
# # Para reincorporarlo:
# #   add_files -norecurse -fileset [get_filesets sources_1] \
# #     [file normalize "$origin_dir/HW/src/bd/test_ComunicPLPS/test_ComunicPLPS.bd"]

# # Generate the wrapper
# set design_name [get_bd_designs]
# make_wrapper -files [get_files $design_name.bd] -top -import