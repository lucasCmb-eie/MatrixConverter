# ============================================================================
# Construye el block design design_testPSPLComm desde cero.
#
#   vivado -mode batch -source HW/src/bd/design_testPSPLComm/create_bd.tcl
#
# Banco de pruebas del puente PS<->PL: el datapath del conversor en lazo
# abierto sobre la PL, expuesto al PS por dos AXI GPIO.
#
#   axi_gpio_ctrl  ch1 out : bit0    rst
#                            bit1    enable SVM
#                            bit2    arm (captura)
#                            bit3    wr_stb  (strobe de escritura a CtrlRegs)
#                            bits7-4 wr_idx  (indice de registro de CtrlRegs)
#                            bit8    rst_reg (reset SOLO del banco CtrlRegs)
#                  ch2 out : wr_data (dato de escritura a CtrlRegs)
#   axi_gpio_data  ch1 in  : dato capturado (indice 13 = estado)
#                  ch2 out : selector de ranura de CaptureBank (5 b utiles)
#
# OJO, cambio del hito 5: i_frec YA NO sale de ch2. Ahora es un registro de
# CtrlRegs (indice 0) y llega por CtrlRegs_0/o_frec_in; ch2 es wr_data. Escribir
# la frecuencia en ch2 sin levantar wr_stb con wr_idx=0 no hace nada.
#
# Y ch1 es un unico registro de 32 bits: todo cambio tiene que ser
# read-modify-write PRESERVANDO el bit 0, o se resetea el datapath.
#
# La captura la pide el PS (arm) pero la dispara el modulador
# (o_trg_calculo), asi la foto cae siempre en el mismo punto de la ventana
# de PWM. CaptureBank/o_listo avisa por GPIO y por IRQ_F2P.
#
# IMPORTANTE: cerrar la GUI de Vivado antes de correrlo, el batch necesita el
# lock del proyecto.
#
# Ver docs/superpowers/specs/2026-08-24-bd-test-comunicplps-design.md
# ============================================================================

# ---------------------------------------------------------------------------
# CONFIGURACION: planta RL simulada
#
#   1 = con planta (default). Banco de LAZO CERRADO completo: RL_wrapper_0
#       realimenta las corrientes al lazo.
#   0 = sin planta. Se omite RL_wrapper_0 y las corrientes medidas entran en
#       cero. OJO: eso NO valida el control -- el error queda en ref-0 siempre,
#       los resonantes se van a windup y q satura. Sirve solo para el modulador
#       (lazo abierto) y el puente PS<->PL.
#
# AREA. Con los coeficientes de la planta entrando por PUERTO, como en esta
# rama, RL_fase cuesta 12 DSP48E1 por fase (tres productos Q8.24xQ8.24) y son
# 36 en las tres; el diseno completo pide 89 DSP. Eso entra holgado en el
# XC7Z020 de la ALINX AX7Z020B (220 DSP) pero NO en los 66 del xc7z007s de la
# Blackboard, donde la implementacion aborta en DRC UTLZ-1 al 134,85%.
#
# Esta rama es el proyecto GENERAL: coeficientes variables en runtime y
# precision completa, apuntando al 7020. Para correrlo en la Blackboard esta la
# rama implementacion_BlackBoard, que los pasa a generic de RL_bd para que la
# sintesis fuera de contexto los pliegue a sumas desplazadas -- medido, la
# planta baja de 36 DSP a 6 y el total a 57 de 66. El canje es que ahi los
# coeficientes dejan de poder cambiarse sin re-sintetizar.
set con_planta 1

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

# NOTA: los comandos de Vivado que reciben *listas* de archivos (add_files,
# get_files) parten el string en espacios, asi que esas rutas van envueltas en
# [list ...] por si el repo llega a colgar de una ruta con espacios. Los
# argumentos de valor unico (open_project, create_bd_design -dir) no lo necesitan.

# Sin esto los module references se ignoran en silencio
# (CRITICAL WARNING [filemgmt 56-176]).
set_property source_mgmt_mode All [current_project]

# Fuentes que pueden faltar en proyectos creados antes de este BD.
foreach nuevo {util/CaptureBank.vhd util/TrgRetardo.vhd wrappers/RL_bd.vhd} {
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
set archivos_93   {AC_Source.vhd CORDIC_atan2.vhd Modulador.vhd wrappers/TClark_wrapper.vhd wrappers/SVM_wrapper.vhd wrappers/RL_bd.vhd util/CaptureBank.vhd util/TrgRetardo.vhd util/sine_generator.vhd util/sine_lut_pkg.vhd util/red_sector.vhd}

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

# HP0 viene habilitado del preset de la Blackboard y quedaria suelto: se apaga
# para que la validacion pase limpia. IRQ_F2P en cambio SI se usa: lo maneja
# CaptureBank/o_listo. Es una sola fuente, asi que no hace falta xlconcat.
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {10} CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {0} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_NUM_F2P_INTR_INPUTS {1}] [get_bd_cells processing_system7_0]

set clk_10m [get_bd_pins processing_system7_0/FCLK_CLK0]

# --- GPIO de control (PS -> PL) -------------------------------------------
# C_DOUT_DEFAULT 0x1 -> arranca con rst=1, modulador deshabilitado, sin arm y
# con wr_stb en 0 (asi que el valor de ch2 no entra a ningun registro).
# El bit 8 (rst_reg) arranca en 0 A PROPOSITO: CtrlRegs inicializa shadow y
# activo con DEFAULTS en la declaracion (CtrlRegs.vhd:83-84), asi que los FF ya
# vienen con los defaults en el bitstream y no hace falta pulsar el reset. Si
# arrancara en 1 el banco ignoraria las escrituras hasta que el PS lo baje, que
# es justo el tipo de paso que uno se olvida.
# C_DOUT_DEFAULT_2 0x53E3 -> valor de encendido de wr_data. Es inofensivo
# justamente porque wr_stb arranca en 0; NO es el step del NCO, que desde el
# hito 5 vive en CtrlRegs (indice 0, default 0x53E3 = 50 Hz).
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
mk_slice sl_arm 2

# Puerto indexado de set points, montado sobre los bits libres de ctrl/ch1.
# No hace falta un tercer AXI GPIO: ch1 usaba 3 de 32 bits.
mk_slice sl_wrstb 3

# Reset PROPIO del banco de set points, separado del reset del datapath.
#
# Por que no comparte sl_rst: CtrlRegs recarga shadow y activo con DEFAULTS en
# el reset, y los defaults son INERTES a proposito (amp_ref = Kp = b = 0). Con
# el reset compartido, un reset para reiniciar el modulador borraba los 10 set
# points y el clamp sticky, y el convertidor volvia generando cero con el PS
# creyendo que su sintonia seguia cargada -- sin ninguna indicacion, porque el
# clamp que lo explicaria se borraba tambien. En un conversor de potencia ese
# es el escenario del operador que resetea para salir de una falla.
#
# Ahora son independientes: se puede resetear el datapath sin perder la
# sintonia, y se puede limpiar el banco (y el clamp) sin tocar el datapath.
mk_slice sl_rstreg 8
# wr_idx son cuatro bits, asi que no sirve mk_slice, que saca uno solo.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_wridx
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {7} \
    CONFIG.DIN_TO {4} CONFIG.DOUT_WIDTH {4}] [get_bd_cells sl_wridx]
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins sl_wridx/Din]

# --- constantes del datapath ----------------------------------------------
proc mk_const {nombre ancho valor} {
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 $nombre
    set_property -dict [list CONFIG.CONST_WIDTH $ancho CONFIG.CONST_VAL $valor] [get_bd_cells $nombre]
}
# Q y Phi_I salieron: i_q_i viene del lazo y i_phi_i de CtrlRegs.
# Carga RL discretizada por Tustin a T = 100 ns (RL_fase no tiene enable:
# avanza en cada flanco del reloj, no una vez por Ts):
#   R = 1,2 ohm, L = 12 mH, tau = L/R = 10 ms
#   a0 = a1 = T/(2L + R*T) = 4,16666e-6 -> 70 en Q8.24        (0x00000046)
#   b1 = (2L - R*T)/(2L + R*T) = 0,99998999 -> 16777048       (0x00FFFF58)
# Regenerar con: python SW/python/ModeloControlPR.py params
#
# CAMBIO 2026-09-26: antes decia a0 = a1 = 6989, que corresponde a
# R = 12 mOhm y L = 120 uH. Misma tau -- por eso b1 no cambia, solo depende
# de L/R -- pero 100x la ganancia, y no coincidia con el R = 1,2 / L = 12 mH
# de SW/matlab/LecturaDatosVivado.m. Se unifica en el valor de MATLAB por dos
# razones: el post-procesado offline y la simulacion tienen que modelar la
# misma carga, y con L = 120 uH el coeficiente b = Kr*Ts del resonante queda
# en 41 cuentas de Q8.24 (1,2 % de error de cuantizacion) contra 4123 con
# L = 12 mH (0,012 %).
#
# OJO: el encabezado de RL_fase.vhd dice "- b1*I[n-1]" pero la implementacion
# (linea 94) suma, asi que b1 va POSITIVO.
if {$con_planta} {
    mk_const Coef_a0 32 70
    mk_const Coef_a1 32 70
    mk_const Coef_b1 32 16777048
}
# Cero32 existe SOLO sin planta, donde alimenta las corrientes medidas (las
# ranuras 06, 07, 08). Con planta las 19 ranuras tienen senal real y esta
# constante se queda sin uso: dejarla creada hace que su dout quede colgado y
# el assert de salidas sueltas aborta, con razon -- una celda muerta en el BD es
# ruido que despues cuesta distinguir de un cable que falta.
if {!$con_planta} {
    mk_const Cero32  32 0
}

# --- bloques del datapath (RTL modules, nunca los IP de HW/src/ip/) -------
create_bd_cell -type module -reference AC_Source      AC_Source_0
create_bd_cell -type module -reference TClark_wrapper TClark_wrapper_0
create_bd_cell -type module -reference CORDIC_atan2   CORDIC_atan2_0
create_bd_cell -type module -reference SVM_wrapper    SVM_wrapper_0
if {$con_planta} {
    create_bd_cell -type module -reference RL_bd      RL_wrapper_0
}
create_bd_cell -type module -reference CaptureBank    CaptureBank_0
create_bd_cell -type module -reference TrgRetardo     TrgRetardo_0

# --- banco de set points y lazo de corriente ------------------------------
# ControlLazo entra como module reference DIRECTO: esta escrito en VHDL-93, y
# que sus hijos sean VHDL-2008 no importa -- Vivado solo rechaza un archivo
# 2008 como TOP de un module reference. Mismo patron que SVM_wrapper, que ya
# funciona aca instanciando matrixConmut.
create_bd_cell -type module -reference CtrlRegs    CtrlRegs_0
create_bd_cell -type module -reference ControlLazo ControlLazo_0

connect_bd_net $clk_10m [get_bd_pins CtrlRegs_0/i_clk] [get_bd_pins ControlLazo_0/i_clk]
# ControlLazo si resetea con el datapath: el lazo tiene que arrancar de cero
# junto con el modulador. CtrlRegs NO, va por su propio bit (ver mas arriba).
connect_bd_net [get_bd_pins sl_rst/Dout]    [get_bd_pins ControlLazo_0/i_rst]
connect_bd_net [get_bd_pins sl_rstreg/Dout] [get_bd_pins CtrlRegs_0/i_rst]
connect_bd_net [get_bd_pins sl_en/Dout]  [get_bd_pins ControlLazo_0/i_en]

connect_bd_net [get_bd_pins sl_wrstb/Dout] [get_bd_pins CtrlRegs_0/i_wr_stb]
connect_bd_net [get_bd_pins sl_wridx/Dout] [get_bd_pins CtrlRegs_0/i_wr_idx]
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] [get_bd_pins CtrlRegs_0/i_wr_data]

# El mismo pulso del modulador es la batuta de todo: dispara el Clark, la
# captura, el commit de los set points y el lazo.
connect_bd_net [get_bd_pins SVM_wrapper_0/o_trg_calculo] \
    [get_bd_pins CtrlRegs_0/i_trg] [get_bd_pins ControlLazo_0/i_trg]

# set points -> lazo
connect_bd_net [get_bd_pins CtrlRegs_0/o_paso_ref] [get_bd_pins ControlLazo_0/i_paso_ref]
connect_bd_net [get_bd_pins CtrlRegs_0/o_amp_ref]  [get_bd_pins ControlLazo_0/i_amp_ref]
connect_bd_net [get_bd_pins CtrlRegs_0/o_k]        [get_bd_pins ControlLazo_0/i_k]
connect_bd_net [get_bd_pins CtrlRegs_0/o_kp]       [get_bd_pins ControlLazo_0/i_kp]
connect_bd_net [get_bd_pins CtrlRegs_0/o_b]        [get_bd_pins ControlLazo_0/i_b]
connect_bd_net [get_bd_pins CtrlRegs_0/o_inv_vi]   [get_bd_pins ControlLazo_0/i_inv_vi]
connect_bd_net [get_bd_pins CtrlRegs_0/o_q_max]    [get_bd_pins ControlLazo_0/i_q_max]
connect_bd_net [get_bd_pins CtrlRegs_0/o_freeze]   [get_bd_pins ControlLazo_0/i_freeze]

# corrientes medidas -> lazo
# Sin planta las tres entran en cero: el lazo no realimenta, pero sus entradas
# quedan con driver (que es lo que exige la auditoria de mas abajo) y los
# integradores del PR se dejan quietos con i_freeze, que arranca en 1.
if {$con_planta} {
    set src_iu [get_bd_pins RL_wrapper_0/o_Iu]
    set src_iv [get_bd_pins RL_wrapper_0/o_Iv]
    set src_iw [get_bd_pins RL_wrapper_0/o_Iw]
} else {
    set src_iu [get_bd_pins Cero32/dout]
    set src_iv [get_bd_pins Cero32/dout]
    set src_iw [get_bd_pins Cero32/dout]
}
connect_bd_net $src_iu [get_bd_pins ControlLazo_0/i_iU]
connect_bd_net $src_iv [get_bd_pins ControlLazo_0/i_iV]
connect_bd_net $src_iw [get_bd_pins ControlLazo_0/i_iW]

# lazo -> modulador
connect_bd_net [get_bd_pins ControlLazo_0/o_q]    [get_bd_pins SVM_wrapper_0/i_q_i]
connect_bd_net [get_bd_pins ControlLazo_0/o_al_o] [get_bd_pins SVM_wrapper_0/i_al_o]
connect_bd_net [get_bd_pins CtrlRegs_0/o_phi_i]   [get_bd_pins SVM_wrapper_0/i_phi_i]

# --- reloj ----------------------------------------------------------------
if {$con_planta} {
    set clk_planta [list [get_bd_pins RL_wrapper_0/i_clk]]
    set rst_planta [list [get_bd_pins RL_wrapper_0/i_rst]]
} else {
    set clk_planta {}
    set rst_planta {}
}
connect_bd_net $clk_10m [get_bd_pins AC_Source_0/i_clk] [get_bd_pins TClark_wrapper_0/i_clk] [get_bd_pins CORDIC_atan2_0/clk] [get_bd_pins SVM_wrapper_0/i_clk] {*}$clk_planta [get_bd_pins CaptureBank_0/i_clk] [get_bd_pins TrgRetardo_0/i_clk]

# --- reset del datapath: lo maneja el PS por el bit 0 ---------------------
# NO se usa peripheral_aresetn del proc_sys_reset: es activo BAJO y todos
# estos resets son activos ALTOS (sine_generator.vhd:57, CORDIC_atan2.vhd:70,
# TransformadaClark.vhd:66, RL_fase.vhd:113). Conectarlo dejaria el datapath
# en reset permanente.
connect_bd_net [get_bd_pins sl_rst/Dout] [get_bd_pins AC_Source_0/i_rst] [get_bd_pins TClark_wrapper_0/i_rst] [get_bd_pins CORDIC_atan2_0/rst] {*}$rst_planta [get_bd_pins CaptureBank_0/i_rst] [get_bd_pins TrgRetardo_0/i_rst]

# --- resto del control ----------------------------------------------------
connect_bd_net [get_bd_pins sl_en/Dout]  [get_bd_pins SVM_wrapper_0/i_enable]
connect_bd_net [get_bd_pins sl_arm/Dout] [get_bd_pins CaptureBank_0/i_arm]

# --- fuente trifasica: la frecuencia la fija el PS ------------------------
#   i_frec = round(f_o * 2**32 / 10 MHz) = round(f_o * 429,4967)
connect_bd_net [get_bd_pins CtrlRegs_0/o_frec_in] [get_bd_pins AC_Source_0/i_frec]

# --- Clark de la tension de entrada, disparado por el modulador -----------
connect_bd_net [get_bd_pins AC_Source_0/o_U] [get_bd_pins TClark_wrapper_0/i_U] [get_bd_pins SVM_wrapper_0/i_U] [get_bd_pins CaptureBank_0/i_d00]
connect_bd_net [get_bd_pins AC_Source_0/o_V] [get_bd_pins TClark_wrapper_0/i_V] [get_bd_pins SVM_wrapper_0/i_V] [get_bd_pins CaptureBank_0/i_d01]
connect_bd_net [get_bd_pins AC_Source_0/o_W] [get_bd_pins TClark_wrapper_0/i_W] [get_bd_pins SVM_wrapper_0/i_W] [get_bd_pins CaptureBank_0/i_d02]
# El mismo pulso es la batuta del muestreo: dispara el Clark y la captura.
# El disparo de CaptureBank pasa por TrgRetardo, NO va directo.
#
# o_trg_calculo cae siempre en la misma ranura del patron SSVM, y medido en la
# placa el 03/10/2026 esa ranura es un VECTOR NULO: las 300 fotos de la primera
# corrida dieron 0x124 o 0x049, las tres salidas a la misma entrada, sin una
# excepcion. Un vector nulo no tiene angulo, asi que no servia para validar el
# signo de seq0. Con el retardo el punto de muestreo se barre por los 2048
# clocks del Ts. Ver HW/src/hdl/util/TrgRetardo.vhd.
#
# TClark y el commit de CtrlRegs siguen con el disparo SIN retardar: el lazo
# tiene que calcular en el borde del Ts, no en un punto arbitrario.
connect_bd_net [get_bd_pins SVM_wrapper_0/o_trg_calculo] \
    [get_bd_pins TClark_wrapper_0/i_start] [get_bd_pins TrgRetardo_0/i_trg]
connect_bd_net [get_bd_pins CtrlRegs_0/o_retardo] [get_bd_pins TrgRetardo_0/i_retardo]
connect_bd_net [get_bd_pins TrgRetardo_0/o_trg]   [get_bd_pins CaptureBank_0/i_trigger]

# --- CORDIC: alfa/beta -> angulo ------------------------------------------
connect_bd_net [get_bd_pins TClark_wrapper_0/o_alfa]   [get_bd_pins CORDIC_atan2_0/x_in]
connect_bd_net [get_bd_pins TClark_wrapper_0/o_beta]   [get_bd_pins CORDIC_atan2_0/y_in]
connect_bd_net [get_bd_pins TClark_wrapper_0/o_valido] [get_bd_pins CORDIC_atan2_0/start]

# --- modulador: al_o del LAZO, be_i del angulo de red --------------------
# al_o viene del LAZO, be_i del angulo de red. Esto es lo que rompe el
# enganche que ataba la frecuencia de salida a la de entrada: el banco pasa a
# hacer conversion de frecuencia.
#
# be_i deberia ser theta_v - phi_f, con phi_f el desfasaje del filtro de
# entrada MAS el retardo de transporte del CORDIC. Medido en simulacion, ese
# retardo solo ya vale -17,4 grados a 50 Hz (Control/INVESTIGACION_MODULADOR.md,
# sonda 7). Con phi_f = 0 queda ese error de desplazamiento, que es lo que hay
# que calibrar en la placa: por eso be_i va directo por ahora.
connect_bd_net [get_bd_pins CORDIC_atan2_0/angle_out] [get_bd_pins SVM_wrapper_0/i_be_i]

# --- carga RL sobre la tension conmutada ----------------------------------
# Sin planta, o_U/o_V/o_W del SVM quedan sin carga. Son SALIDAS, asi que la
# auditoria no las marca; se las sigue viendo por CaptureBank si algun dia se
# cablean a una ranura.
if {$con_planta} {
    connect_bd_net [get_bd_pins Coef_a0/dout] [get_bd_pins RL_wrapper_0/i_c_a0]
    connect_bd_net [get_bd_pins Coef_a1/dout] [get_bd_pins RL_wrapper_0/i_c_a1]
    connect_bd_net [get_bd_pins Coef_b1/dout] [get_bd_pins RL_wrapper_0/i_c_b1]
    connect_bd_net [get_bd_pins SVM_wrapper_0/o_U] [get_bd_pins RL_wrapper_0/i_U]
    connect_bd_net [get_bd_pins SVM_wrapper_0/o_V] [get_bd_pins RL_wrapper_0/i_V]
    connect_bd_net [get_bd_pins SVM_wrapper_0/o_W] [get_bd_pins RL_wrapper_0/i_W]
}

# --- banco de captura -----------------------------------------------------
# Indices en uso:  0,1,2 = Vi (v_U,v_V,v_W)      6,7,8 = Io (i_U,i_V,i_W)
# Con con_planta=0 las ranuras 6,7,8 leen cero: no hay planta que las genere.
# Se dejan cableadas igual para que el software del PS no cambie de indices.
# El resto queda en cero, reservado: cablearlos despues no renumera nada.
connect_bd_net $src_iu [get_bd_pins CaptureBank_0/i_d06]
connect_bd_net $src_iv [get_bd_pins CaptureBank_0/i_d07]
connect_bd_net $src_iw [get_bd_pins CaptureBank_0/i_d08]
connect_bd_net [get_bd_pins ControlLazo_0/o_i_alfa]   [get_bd_pins CaptureBank_0/i_d09]
connect_bd_net [get_bd_pins ControlLazo_0/o_i_beta]   [get_bd_pins CaptureBank_0/i_d10]
connect_bd_net [get_bd_pins ControlLazo_0/o_ref_alfa] [get_bd_pins CaptureBank_0/i_d14]
connect_bd_net [get_bd_pins ControlLazo_0/o_ref_beta] [get_bd_pins CaptureBank_0/i_d15]
connect_bd_net [get_bd_pins ControlLazo_0/o_v_alfa]   [get_bd_pins CaptureBank_0/i_d16]
connect_bd_net [get_bd_pins ControlLazo_0/o_v_beta]   [get_bd_pins CaptureBank_0/i_d17]

# Ranura 18: q (9 b) + al_o (11 b) + sat (1 b) + relleno, en una palabra.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cat_q
set_property -dict [list CONFIG.NUM_PORTS {4}] [get_bd_cells cat_q]
mk_const Relleno11 11 0
connect_bd_net [get_bd_pins ControlLazo_0/o_q]    [get_bd_pins cat_q/In0]
connect_bd_net [get_bd_pins ControlLazo_0/o_al_o] [get_bd_pins cat_q/In1]
connect_bd_net [get_bd_pins ControlLazo_0/o_sat]  [get_bd_pins cat_q/In2]
connect_bd_net [get_bd_pins Relleno11/dout]       [get_bd_pins cat_q/In3]
connect_bd_net [get_bd_pins cat_q/dout] [get_bd_pins CaptureBank_0/i_d18]

# Ranura 03: el clamp sticky de CtrlRegs, para que el PS sepa si le rechazaron
# un set point.
#
# Va en la 03 y NO en la 19: el spec 6.4 reserva la 19 para x1_alfa, el estado
# del resonante, que es la sonda del criterio 6. Las ranuras 04, 05 y 11 siguen
# libres en cero, asi que el clamp no desaloja nada.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cat_clamp
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells cat_clamp]
mk_const Relleno16 16 0
connect_bd_net [get_bd_pins CtrlRegs_0/o_clamp] [get_bd_pins cat_clamp/In0]
connect_bd_net [get_bd_pins Relleno16/dout]     [get_bd_pins cat_clamp/In1]
connect_bd_net [get_bd_pins cat_clamp/dout] [get_bd_pins CaptureBank_0/i_d03]

# Ranura 19: x1_alfa, el estado del resonante alfa (spec 6.4). Son los 32 bits
# BAJOS de Q8.40, que es lo que el criterio 6 necesita -- pide acotar el ciclo
# limite a pocos LSB, y truncando a Q8.24 esos LSB desaparecen. La magnitud no
# se pierde: o_v_alfa (ranura 16) es u = kp*e + x1(47..16).
connect_bd_net [get_bd_pins ControlLazo_0/o_x1_alfa] [get_bd_pins CaptureBank_0/i_d19]

# Ranura 12: la palabra de conmutacion de la matriz, 18 b utiles.
#
# Sin esto el banco NO puede validar el arreglo de signo de seq0 que esta rama
# trae: o_direcciones_Matriz y o_U/o_V/o_W quedaban las cuatro colgadas, y
# entonces matrixConmut se recortaba ENTERO en sintesis -- medido, 0 celdas en
# el netlist implementado. Capturada en sincronismo con o_trg_calculo, esta
# palabra alcanza para reconstruir el vector aplicado ciclo a ciclo.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cat_dir
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells cat_dir]
mk_const Relleno14 14 0
connect_bd_net [get_bd_pins SVM_wrapper_0/o_direcciones_Matriz] [get_bd_pins cat_dir/In0]
connect_bd_net [get_bd_pins Relleno14/dout]                     [get_bd_pins cat_dir/In1]
connect_bd_net [get_bd_pins cat_dir/dout] [get_bd_pins CaptureBank_0/i_d12]

# Ranuras 04, 05 y 11: la tension conmutada de salida, o_U/o_V/o_W.
#
# Esto NO es instrumentacion de lujo: es lo que mantiene a matrixConmut dentro
# del chip. o_direcciones_Matriz (ranura 12) sale del MODULADOR, no de la
# matriz -- SVM_wrapper.vhd:36 lo asigna desde w_direcciones, que es la salida
# de modulador_core. Las unicas salidas de matrixConmut_core son o_U/o_V/o_W, y
# con las tres colgadas opt_design la recortaba entera (medido: 0 celdas en el
# netlist implementado).
#
# Y de paso es el observable mas valioso del banco: sin planta, i_U/i_V/i_W
# vienen de AC_Source, asi que o_U/o_V/o_W es la forma de onda de tension de
# salida real del conversor, capturada en sincronismo con o_trg_calculo.
connect_bd_net [get_bd_pins SVM_wrapper_0/o_U] [get_bd_pins CaptureBank_0/i_d04]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_V] [get_bd_pins CaptureBank_0/i_d05]
connect_bd_net [get_bd_pins SVM_wrapper_0/o_W] [get_bd_pins CaptureBank_0/i_d11]

connect_bd_net [get_bd_pins axi_gpio_data/gpio2_io_o] [get_bd_pins CaptureBank_0/i_sel]
connect_bd_net [get_bd_pins CaptureBank_0/o_data]     [get_bd_pins axi_gpio_data/gpio_io_i]

# o_listo es nivel, no pulso: sirve para polear por el indice 13 del selector
# y a la vez para manejar IRQ_F2P, que el GIC toma sensible a nivel alto.
# El ack lo hace el propio i_arm='0', que limpia o_listo.
connect_bd_net [get_bd_pins CaptureBank_0/o_listo] [get_bd_pins processing_system7_0/IRQ_F2P]

# ============================ verificacion ================================

# --- 1) conectividad de las celdas que arma este script ------------------
# Se auditan solo las celdas propias: los pines libres del proc_sys_reset y
# del interconnect los deja asi la automatizacion, a proposito.
#
# Los pines escalares que son miembros de una interfaz (s_axi_awaddr, etc.)
# se excluyen del barrido: su conectividad vive en el interface net, no en un
# net comun, asi que se chequean aparte por la interfaz completa.
set celdas {AC_Source_0 TClark_wrapper_0 CORDIC_atan2_0 SVM_wrapper_0 CaptureBank_0 CtrlRegs_0 ControlLazo_0 axi_gpio_ctrl axi_gpio_data sl_rst sl_en sl_arm sl_wrstb sl_wridx sl_rstreg TrgRetardo_0 cat_q cat_clamp cat_dir Relleno11 Relleno16 Relleno14}
if {!$con_planta} {
    lappend celdas Cero32
}
if {$con_planta} {
    lappend celdas RL_wrapper_0 Coef_a0 Coef_a1 Coef_b1
}
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
# Salidas que PUEDEN quedar sin uso, y nada mas que esas. Esto es un ASSERT y
# no un puts informativo: una salida colgada nueva significa que algun bloque se
# quedo sin carga, y opt_design lo RECORTA ENTERO del bitstream sin que nada
# chille. Es lo que paso con matrixConmut -- las tres salidas o_U/o_V/o_W
# colgadas y 0 celdas en el netlist implementado -- y es invisible en el log de
# sintesis. Con o_U/o_V/o_W cableados la lista ya no depende de con_planta.
set esperadas [lsort {
    /CORDIC_atan2_0/done
    /CORDIC_atan2_0/mag_out
    /ControlLazo_0/o_listo
}]
set reales [lsort $salidas_sueltas]
puts "CHEQUEO|salidas sin uso: $reales"
if {$reales ne $esperadas} {
    puts "CHEQUEO|ESPERADAS: $esperadas"
    set nuevas {}
    foreach x $reales { if {[lsearch -exact $esperadas $x] < 0} { lappend nuevas $x } }
    set faltan {}
    foreach x $esperadas { if {[lsearch -exact $reales $x] < 0} { lappend faltan $x } }
    if {[llength $nuevas]} {
        error "Salidas colgadas NUEVAS: $nuevas -- el bloque que las genera se vaa recortar del bitstream. Cablealas a una ranura de CaptureBank o agregalas ala lista de esperadas si de verdad no se usan."
    }
    error "La lista de esperadas quedo vieja: ya tienen carga $faltan"
}
puts "CHEQUEO|las salidas sin uso son exactamente las esperadas"
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

# --- chequeos propios del hito 5 -----------------------------------------
# i_q_i tiene que venir del LAZO, no de una constante.
set drv [get_bd_pins -quiet -of [get_bd_nets -of [get_bd_pins SVM_wrapper_0/i_q_i]] \
         -filter {DIR == O}]
if {![string match "*ControlLazo_0*" $drv]} {
    error "i_q_i no viene del lazo, viene de: $drv"
}
puts "CHEQUEO|i_q_i viene del lazo"

# al_o y be_i tienen que venir de fuentes DISTINTAS: si comparten driver,
# volvio el enganche que ata la frecuencia de salida a la de entrada.
set d_al [get_bd_pins -quiet -of [get_bd_nets -of [get_bd_pins SVM_wrapper_0/i_al_o]] -filter {DIR == O}]
set d_be [get_bd_pins -quiet -of [get_bd_nets -of [get_bd_pins SVM_wrapper_0/i_be_i]] -filter {DIR == O}]
if {$d_al eq $d_be} {
    error "al_o y be_i comparten driver: volvio el enganche de frecuencia"
}
puts "CHEQUEO|al_o y be_i tienen drivers distintos"

# --- los dos resets son independientes -----------------------------------
# Si CtrlRegs volviera a compartir el reset del datapath, un reset del
# modulador borraria los set points en silencio.
set n_dp  [get_bd_nets -of_objects [get_bd_pins ControlLazo_0/i_rst]]
set n_reg [get_bd_nets -of_objects [get_bd_pins CtrlRegs_0/i_rst]]
if {$n_dp eq $n_reg} {
    error "CtrlRegs/i_rst y ControlLazo/i_rst comparten el net $n_dp: un reset del datapath borraria los set points"
}
puts "CHEQUEO|CtrlRegs tiene reset propio ($n_reg) distinto del datapath ($n_dp)"

# --- el disparo de CaptureBank pasa por TrgRetardo -----------------------
# Si volviera a colgarse directo de o_trg_calculo, la captura caeria otra vez
# siempre en la ranura de vector nulo del patron SSVM y no habria angulo que
# medir. Es un error silencioso: el banco funciona, solo que no dice nada.
set n_cap [get_bd_nets -of_objects [get_bd_pins CaptureBank_0/i_trigger]]
set n_svm [get_bd_nets -of_objects [get_bd_pins SVM_wrapper_0/o_trg_calculo]]
if {$n_cap eq $n_svm} {
    error "CaptureBank/i_trigger cuelga directo de o_trg_calculo ($n_cap): la captura va a caer siempre en el vector nulo. Tiene que pasar por TrgRetardo."
}
puts "CHEQUEO|el disparo de captura pasa por TrgRetardo ($n_cap)"

# Las 19 ranuras cableadas de CaptureBank (la 13 es el estado, no tiene pin).
foreach n {00 01 02 03 04 05 06 07 08 09 10 11 12 14 15 16 17 18 19} {
    if {[llength [get_bd_nets -quiet -of [get_bd_pins CaptureBank_0/i_d$n]]] == 0} {
        error "CaptureBank/i_d$n quedo sin cablear"
    }
}
puts "CHEQUEO|las 19 ranuras de CaptureBank estan cableadas"

# --- variante construida: la planta esta si y solo si se la pidio ---------
set hay_planta [llength [get_bd_cells -quiet RL_wrapper_0]]
if {$hay_planta != $con_planta} {
    error "con_planta=$con_planta pero RL_wrapper_0 presente=$hay_planta"
}
if {$con_planta} {
    puts "CHEQUEO|variante CON planta RL (lazo cerrado, ~89 DSP: necesita XC7Z020)"
} else {
    puts "CHEQUEO|variante SIN planta RL (lazo abierto, ~53 DSP: entra en xc7z007s)"
}

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

# make_wrapper -import deja el wrapper en el fileset pero NO mueve el top:
# sources_1 se queda con el que fijo build.tcl (modulador). Sin esto, un
# proyecto recien regenerado sintetiza el modulo equivocado.
set_property top ${bd_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "INFO: BD $bd_name construido, validado y con wrapper generado"
close_project
