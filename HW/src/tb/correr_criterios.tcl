# Corre los criterios 1 a 4 del spec 7.4 en XSIM, en modo batch.
#
#   cd <dir de trabajo vacio>
#   vivado -mode batch -source <repo>/HW/src/tb/correr_criterios.tcl -tclargs <repo>
#
# Cada escenario escribe control_corriente.csv en su subdirectorio. Analizar con:
#   python SW/python/AnalizarTransitorios.py <dir>
#
# Los criterios 5 y 6 NO estan aca: se miden sobre la placa.

set repo [lindex $argv 0]
if {$repo eq ""} { set repo [pwd] }

set fuentes {
    HW/src/hdl/util/Declaraciones.vhd
    HW/src/hdl/util/sine_lut_pkg.vhd
    HW/src/hdl/util/red_sector.vhd
    HW/src/hdl/util/sine_generator.vhd
    HW/src/hdl/AC_Source.vhd
    HW/src/hdl/CORDIC_atan2.vhd
    HW/src/hdl/Modulador.vhd
    HW/src/hdl/TransformadaClark.vhd
    HW/src/hdl/matrixConmut.vhd
    HW/src/hdl/RL_fase.vhd
    HW/src/hdl/control/PR_2int.vhd
    HW/src/hdl/control/RefGen.vhd
    HW/src/hdl/wrappers/TClark_wrapper.vhd
    HW/src/hdl/wrappers/RL_wrapper.vhd
    HW/src/hdl/wrappers/SVM_wrapper.vhd
    HW/src/hdl/control/ControlLazo.vhd
    HW/src/tb/tb_ControlCorriente.vhd
    HW/src/tb/tb_criterios.vhd
}

# Todo se compila como VHDL-2008: la restriccion de VHDL-93 vale para los
# module references del block design, no para simular.
foreach f $fuentes {
    exec xvhdl -2008 [file join $repo $f]
}

# escenario -> milisegundos de simulacion
# El criterio 1 (regimen) se extrae de la cola del escenario del criterio 2,
# que pasa 150 ms en regimen a 0,10 pu despues del escalon. No necesita
# corrida propia.
set casos {
    crit2_amplitud       tb_crit2_escalon_amplitud   250
    crit3_frecuencia     tb_crit3_escalon_frecuencia 300
    crit4a_freeze        tb_crit4a_freeze            300
    crit4b_sin_freeze    tb_crit4b_sin_freeze        300
}

foreach {dir top ms} $casos {
    file mkdir $dir
    cd $dir
    exec xelab -debug off work.$top -s lazo
    set fh [open run.tcl w]
    puts $fh "run $ms ms"
    puts $fh "quit"
    close $fh
    exec xsim lazo -t run.tcl
    puts "LISTO $dir ($top, $ms ms)"
    cd ..
}
puts "Todos los escenarios corridos. Analizar con AnalizarTransitorios.py"
