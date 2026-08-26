# ============================================================================
# Construye el block design design_testPSPLComm desde cero.
#
#   vivado -mode batch -source HW/src/bd/design_testPSPLComm/create_bd.tcl
#
# Banco de pruebas del puente PS<->PL: el datapath del conversor en lazo
# abierto sobre la PL, expuesto al PS por dos AXI GPIO.
#
#   axi_gpio_ctrl  ch1 out : bit0 rst, bit1 enable SVM, bit2 capture
#                  ch2 out : i_frec (step del NCO de AC_Source)
#   axi_gpio_data  ch1 in  : dato capturado
#                  ch2 out : selector de registro
#
# IMPORTANTE: cerrar la GUI de Vivado antes de correrlo, el batch necesita el
# lock del proyecto.
#
# Ver docs/superpowers/specs/2026-08-24-bd-test-comunicplps-design.md
# ============================================================================

set bd_name  "design_testPSPLComm"
set bd_dir   [file normalize [file dirname [info script]]/..]
set repo_dir [file normalize [file dirname [info script]]/../../../..]
set hdl_dir  "$repo_dir/HW/src/hdl"
set xpr      "$repo_dir/project_ConmutMatrix/project_ConmutMatrix.xpr"

puts "INFO: repo    = $repo_dir"
puts "INFO: BD dir  = $bd_dir"

# ---------------------------------------------------------------- proyecto
if {![file exists $xpr]} {
    error "No existe $xpr. Corre primero:  vivado -mode batch -source build.tcl"
}
open_project $xpr

# NOTA: la ruta del repo tiene espacios. Los comandos de Vivado que reciben
# *listas* de archivos (add_files, get_files) parten el string en espacios, asi
# que esas rutas van envueltas en [list ...]. Los argumentos de valor unico
# (open_project, create_bd_design -dir) no necesitan el envoltorio.

# Sin esto los module references se ignoran en silencio
# (CRITICAL WARNING [filemgmt 56-176]).
set_property source_mgmt_mode All [current_project]

# Fuentes que pueden faltar en proyectos creados antes de este BD.
foreach nuevo {util/CaptureBank.vhd wrappers/RL_bd.vhd} {
    set base [file tail $nuevo]
    if {[llength [get_files -quiet "*$base"]] == 0} {
        puts "INFO: agrego $base al fileset sources_1"
        add_files -norecurse -fileset [get_filesets sources_1] [list "$hdl_dir/$nuevo"]
    }
}
update_compile_order -fileset sources_1

# Version de VHDL por archivo. Las dos listas importan:
#
#  - Los que llaman to_sfixed() sobre std_logic_vector NECESITAN VHDL 2008: en
#    VHDL-93 slv y std_ulogic_vector son tipos distintos, no matchea ningun
#    overload y Vivado cae en el de INTEGER
#    (ERROR [Synth 8-11234] type error near 'i_c_a0'; expected type 'integer').
#
#  - Los tops de module reference NO pueden ser VHDL 2008
#    (ERROR [filemgmt 56-195]). Sus dependencias si pueden serlo, y de hecho lo
#    son: TClark_wrapper (93) instancia TransformadaClark (2008), y RL_bd (93)
#    instancia RL_wrapper (2008).
set archivos_2008 {TransformadaClark.vhd matrixConmut.vhd RL_fase.vhd wrappers/RL_wrapper.vhd util/Declaraciones.vhd util/DienteSierraGen.vhd}
set archivos_93   {AC_Source.vhd CORDIC_atan2.vhd Modulador.vhd wrappers/TClark_wrapper.vhd wrappers/SVM_wrapper.vhd wrappers/RL_bd.vhd util/CaptureBank.vhd util/sine_generator.vhd util/sine_lut_pkg.vhd util/red_sector.vhd}

foreach f $archivos_2008 {
    set obj [get_files -quiet [list "$hdl_dir/$f"]]
    if {[llength $obj]} { set_property file_type {VHDL 2008} $obj }
}
foreach f $archivos_93 {
    set obj [get_files -quiet [list "$hdl_dir/$f"]]
    if {[llength $obj] && [string equal [get_property file_type $obj] "VHDL 2008"]} {
        puts "INFO: $f estaba marcado VHDL 2008, lo paso a VHDL"
        set_property file_type VHDL $obj
    }
}

# ---------------------------------------------------------------- limpieza
foreach d [get_bd_designs -quiet $bd_name] { close_bd_design $d }
foreach f [get_files -quiet "$bd_name.bd"] { remove_files $f }
foreach f [get_files -quiet "${bd_name}_wrapper.vhd"] { remove_files $f }
foreach item [list "$bd_dir/$bd_name/$bd_name.bd" "$bd_dir/$bd_name/$bd_name.bda" "$bd_dir/$bd_name/$bd_name.bxml" "$bd_dir/$bd_name/ui" "$bd_dir/$bd_name/ip" "$bd_dir/$bd_name/hdl"] {
    if {[file exists $item]} { file delete -force $item }
}

# ---------------------------------------------------------------- el BD
create_bd_design -dir $bd_dir $bd_name
current_bd_design [get_bd_designs $bd_name]

# --- Zynq PS7, FCLK0 a 10 MHz ---------------------------------------------
# El datapath NO cierra timing a 100 MHz: camino critico medido 10,27 ns
# (division restauradora del Modulador + 20 iteraciones del CORDIC).
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} [get_bd_cells processing_system7_0]

# HP0 e IRQ_F2P vienen habilitados del preset de la Blackboard y quedarian
# sueltos: se apagan para que la validacion pase limpia.
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {10} CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {0} CONFIG.PCW_USE_FABRIC_INTERRUPT {0} CONFIG.PCW_IRQ_F2P_INTR {0}] [get_bd_cells processing_system7_0]

set clk_10m [get_bd_pins processing_system7_0/FCLK_CLK0]

# --- GPIO de control (PS -> PL) -------------------------------------------
# C_DOUT_DEFAULT 0x1 -> arranca con rst=1 y el modulador deshabilitado.
# C_DOUT_DEFAULT_2 0x53E3 -> step de 50 Hz, util sin que el PS escriba nada.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_DOUT_DEFAULT {0x00000001} CONFIG.C_DOUT_DEFAULT_2 {0x000053E3}] [get_bd_cells axi_gpio_ctrl]

# --- GPIO de sensado (PL -> PS) -------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_data
set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_INPUTS {1} CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_GPIO2_WIDTH {32}] [get_bd_cells axi_gpio_data]

# --- interconexion AXI, todo en el mismo dominio de 10 MHz ----------------
# Crea el interconnect, el proc_sys_reset y conecta M_AXI_GP0_ACLK.
foreach g {axi_gpio_ctrl axi_gpio_data} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"] [get_bd_intf_pins $g/S_AXI]
}

# ======================= datapath en lazo abierto =========================

# --- separacion de los bits de control ------------------------------------
proc mk_slice {nombre bit} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 $nombre
    set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM $bit CONFIG.DIN_TO $bit CONFIG.DOUT_WIDTH {1}] [get_bd_cells $nombre]
    connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins $nombre/Din]
}
mk_slice sl_rst 0
mk_slice sl_en  1
mk_slice sl_cap 2

# --- constantes del datapath ----------------------------------------------
proc mk_const {nombre ancho valor} {
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 $nombre
    set_property -dict [list CONFIG.CONST_WIDTH $ancho CONFIG.CONST_VAL $valor] [get_bd_cells $nombre]
}
# q = 180/256 = 0,703125, por debajo del limite teorico 0,866
mk_const Q       9  180
# sin desfase entre corriente de salida y tension de entrada
mk_const Phi_I   11 0
# Carga RL discretizada por Tustin a Ts = 100 ns:
#   R = 0,012002 ohm, L = 1,200191e-4 H, tau = L/R = 10 ms
#   a0 = a1 = 1/(R + 2L/Ts) = 4,16597e-4 -> 6989 en Q8.24     (0x00001B4D)
#   b1 = (2L/Ts - R)/(2L/Ts + R) = 0,99998999 -> 16777048     (0x00FFFF58)
# OJO: el encabezado de RL_fase.vhd dice "- b1*I[n-1]" pero la implementacion
# (linea 94) suma, asi que b1 va POSITIVO.
mk_const Coef_a0 32 6989
mk_const Coef_a1 32 6989
mk_const Coef_b1 32 16777048
# relleno de las ranuras de CaptureBank que no se usan en este banco
mk_const Cero32  32 0

# --- bloques del datapath (RTL modules, nunca los IP de HW/src/ip/) -------
create_bd_cell -type module -reference AC_Source      AC_Source_0
create_bd_cell -type module -reference TClark_wrapper TClark_wrapper_0
create_bd_cell -type module -reference CORDIC_atan2   CORDIC_atan2_0
create_bd_cell -type module -reference SVM_wrapper    SVM_wrapper_0
create_bd_cell -type module -reference RL_bd          RL_wrapper_0
create_bd_cell -type module -reference CaptureBank    CaptureBank_0

# --- reloj ----------------------------------------------------------------
connect_bd_net $clk_10m [get_bd_pins AC_Source_0/i_clk] [get_bd_pins TClark_wrapper_0/i_clk] [get_bd_pins CORDIC_atan2_0/clk] [get_bd_pins SVM_wrapper_0/i_clk] [get_bd_pins RL_wrapper_0/i_clk] [get_bd_pins CaptureBank_0/i_clk]

# --- reset del datapath: lo maneja el PS por el bit 0 ---------------------
# NO se usa peripheral_aresetn del proc_sys_reset: es activo BAJO y todos
# estos resets son activos ALTOS (sine_generator.vhd:57, CORDIC_atan2.vhd:70,
# TransformadaClark.vhd:66, RL_fase.vhd:113). Conectarlo dejaria el datapath
# en reset permanente.
connect_bd_net [get_bd_pins sl_rst/Dout] [get_bd_pins AC_Source_0/i_rst] [get_bd_pins TClark_wrapper_0/i_rst] [get_bd_pins CORDIC_atan2_0/rst] [get_bd_pins RL_wrapper_0/i_rst] [get_bd_pins CaptureBank_0/i_rst]

# --- resto del control ----------------------------------------------------
connect_bd_net [get_bd_pins sl_en/Dout]  [get_bd_pins SVM_wrapper_0/i_enable]
connect_bd_net [get_bd_pins sl_cap/Dout] [get_bd_pins CaptureBank_0/i_capture]

# --- fuente trifasica: la frecuencia la fija el PS ------------------------
#   i_frec = round(f_o * 2**32 / 10 MHz) = round(f_o * 429,4967)
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] [get_bd_pins AC_Source_0/i_frec]

# --- Clark de la tension de entrada, disparado por el modulador -----------
connect_bd_net [get_bd_pins AC_Source_0/o_U] [get_bd_pins TClark_wrapper_0/i_U] [get_bd_pins SVM_wrapper_0/i_U] [get_bd_pins CaptureBank_0/i_d00]
connect_bd_net [get_bd_pins AC_Source_0/o_V] [get_bd_pins TClark_wrapper_0/i_V] [get_bd_pins SVM_wrapper_0/i_V] [get_bd_pins CaptureBank_0/i_d01]
connect_bd_net [get_bd_pins AC_Source_0/o_W] [get_bd_pins TClark_wrapper_0/i_W] [get_bd_pins SVM_wrapper_0/i_W] [get_bd_pins CaptureBank_0/i_d02]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_trg_calculo] [get_bd_pins TClark_wrapper_0/i_start]

# --- CORDIC: alfa/beta -> angulo ------------------------------------------
connect_bd_net [get_bd_pins TClark_wrapper_0/o_alfa]   [get_bd_pins CORDIC_atan2_0/x_in]
connect_bd_net [get_bd_pins TClark_wrapper_0/o_beta]   [get_bd_pins CORDIC_atan2_0/y_in]
connect_bd_net [get_bd_pins TClark_wrapper_0/o_valido] [get_bd_pins CORDIC_atan2_0/start]

# --- modulador: AMBOS angulos salen de la tension de entrada --------------
# Consecuencia deliberada: con al_o = be_i la tension de salida queda
# enganchada en frecuencia y fase a la de entrada. El banco NO hace
# conversion de frecuencia; eso es el subproyecto C.
connect_bd_net [get_bd_pins CORDIC_atan2_0/angle_out] [get_bd_pins SVM_wrapper_0/i_al_o] [get_bd_pins SVM_wrapper_0/i_be_i]
connect_bd_net [get_bd_pins Q/dout]     [get_bd_pins SVM_wrapper_0/i_q_i]
connect_bd_net [get_bd_pins Phi_I/dout] [get_bd_pins SVM_wrapper_0/i_phi_i]

# --- carga RL sobre la tension conmutada ----------------------------------
connect_bd_net [get_bd_pins Coef_a0/dout] [get_bd_pins RL_wrapper_0/i_c_a0]
connect_bd_net [get_bd_pins Coef_a1/dout] [get_bd_pins RL_wrapper_0/i_c_a1]
connect_bd_net [get_bd_pins Coef_b1/dout] [get_bd_pins RL_wrapper_0/i_c_b1]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_U] [get_bd_pins RL_wrapper_0/i_U]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_V] [get_bd_pins RL_wrapper_0/i_V]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_W] [get_bd_pins RL_wrapper_0/i_W]

# --- banco de captura -----------------------------------------------------
# Indices en uso:  0,1,2 = Vi (v_U,v_V,v_W)      6,7,8 = Io (i_U,i_V,i_W)
# El resto queda en cero, reservado: cablearlos despues no renumera nada.
connect_bd_net [get_bd_pins RL_wrapper_0/o_Iu] [get_bd_pins CaptureBank_0/i_d06]
connect_bd_net [get_bd_pins RL_wrapper_0/o_Iv] [get_bd_pins CaptureBank_0/i_d07]
connect_bd_net [get_bd_pins RL_wrapper_0/o_Iw] [get_bd_pins CaptureBank_0/i_d08]
connect_bd_net [get_bd_pins Cero32/dout] [get_bd_pins CaptureBank_0/i_d03] [get_bd_pins CaptureBank_0/i_d04] [get_bd_pins CaptureBank_0/i_d05] [get_bd_pins CaptureBank_0/i_d09] [get_bd_pins CaptureBank_0/i_d10] [get_bd_pins CaptureBank_0/i_d11] [get_bd_pins CaptureBank_0/i_d12]

connect_bd_net [get_bd_pins axi_gpio_data/gpio2_io_o] [get_bd_pins CaptureBank_0/i_sel]
connect_bd_net [get_bd_pins CaptureBank_0/o_data]     [get_bd_pins axi_gpio_data/gpio_io_i]

# ============================ verificacion ================================

# --- 1) conectividad de las celdas que arma este script ------------------
# Se auditan solo las celdas propias: los pines libres del proc_sys_reset y
# del interconnect los deja asi la automatizacion, a proposito.
#
# Los pines escalares que son miembros de una interfaz (s_axi_awaddr, etc.)
# se excluyen del barrido: su conectividad vive en el interface net, no en un
# net comun, asi que se chequean aparte por la interfaz completa.
set celdas {AC_Source_0 TClark_wrapper_0 CORDIC_atan2_0 SVM_wrapper_0 RL_wrapper_0 CaptureBank_0 axi_gpio_ctrl axi_gpio_data sl_rst sl_en sl_cap Q Phi_I Coef_a0 Coef_a1 Coef_b1 Cero32}
set entradas_sueltas {}
set salidas_sueltas {}
set intf_sueltas {}
foreach c $celdas {
    set celda [get_bd_cells $c]

    # Interfaces. Hay dos formas validas de cablearlas y el chequeo acepta las dos:
    #   - como interfaz (S_AXI <-> interconnect): tiene interface net, y entonces
    #     sus pines miembro no se auditan de a uno.
    #   - pin a pin (GPIO/GPIO2 -> gpio_io_o, gpio_io_i): no tiene interface net,
    #     asi que sus miembros caen en el barrido escalar de mas abajo.
    # Solo es un error real una interfaz sin net Y sin miembros que auditar.
    set miembros {}
    foreach ip [get_bd_intf_pins -quiet -of $celda] {
        set mps [get_bd_pins -quiet -of $ip]
        if {[llength [get_bd_intf_nets -quiet -of $ip]] > 0} {
            foreach mp $mps { lappend miembros [get_property PATH $mp] }
        } elseif {[llength $mps] == 0} {
            lappend intf_sueltas [get_property PATH $ip]
        }
    }

    # pines escalares sueltos
    foreach p [get_bd_pins -quiet -of $celda] {
        set ruta [get_property PATH $p]
        if {[lsearch -exact $miembros $ruta] >= 0} { continue }
        if {[llength [get_bd_nets -quiet -of $p]] == 0} {
            if {[string equal [get_property DIR $p] "I"]} {
                lappend entradas_sueltas $ruta
            } else {
                lappend salidas_sueltas $ruta
            }
        }
    }
}
puts "CHEQUEO|salidas sin uso (esperado CORDIC/done y SVM/o_direcciones_Matriz): $salidas_sueltas"
if {[llength $intf_sueltas]} {
    puts "CHEQUEO|INTERFACES SUELTAS: $intf_sueltas"
    error "Hay interfaces sin conectar"
}
puts "CHEQUEO|todas las interfaces conectadas"
if {[llength $entradas_sueltas]} {
    puts "CHEQUEO|ENTRADAS SUELTAS: $entradas_sueltas"
    error "Hay entradas sin conectar en el datapath"
}
puts "CHEQUEO|no hay entradas sueltas"

# --- 2) el reset del datapath NO viene del proc_sys_reset ----------------
set net_rst [get_property NAME [get_bd_nets -of [get_bd_pins AC_Source_0/i_rst]]]
puts "CHEQUEO|net de AC_Source_0/i_rst = $net_rst"
if {[string match "*aresetn*" $net_rst]} {
    error "AC_Source_0/i_rst quedo colgado de un reset activo bajo"
}

# --- 3) i_frec quedo en 32 bits (no en los 2 de la entity vieja) ---------
set w_frec [expr {[get_property LEFT [get_bd_pins AC_Source_0/i_frec]] + 1}]
puts "CHEQUEO|ancho de AC_Source_0/i_frec = $w_frec bits"
if {$w_frec != 32} {
    error "AC_Source_0/i_frec quedo en $w_frec bits, se esperaban 32"
}

# --- 4) el reloj quedo realmente en 10 MHz -------------------------------
set f_real [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells processing_system7_0]]
puts "RELOJ|FCLK_CLK0 = $f_real MHz"
if {$f_real != 10} {
    puts "AVISO: FCLK0 quedo en $f_real MHz. Hay que recalcular i_frec y los coeficientes del RL, que dependen de Ts."
}

# ---------------------------------------------------------------- cierre
assign_bd_address
regenerate_bd_layout
validate_bd_design -force
save_bd_design

foreach s [get_bd_addr_segs -of [get_bd_addr_spaces processing_system7_0/Data]] {
    puts "DIRECCION|[get_property NAME $s] @ [get_property OFFSET $s] rango [get_property RANGE $s]"
}

make_wrapper -files [get_files $bd_name.bd] -top -import
generate_target all [get_files $bd_name.bd]

puts "INFO: BD $bd_name construido, validado y con wrapper generado"
close_project
