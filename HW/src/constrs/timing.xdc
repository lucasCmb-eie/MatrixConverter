# En tu archivo .xdc
# Ignorar timing desde el registro de salida del RL hacia el promediador

set_false_path -from [get_cells -hierarchical -filter {NAME =~ *TriRL* && IS_SEQUENTIAL}] -to [get_cells -hierarchical -filter {NAME =~ *Promediador* && IS_SEQUENTIAL}]
set_false_path -from [get_clocks clk_fpga_1] -to [get_clocks clk_fpga_0]
