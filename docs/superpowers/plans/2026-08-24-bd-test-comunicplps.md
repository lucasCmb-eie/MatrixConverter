# BD `test_ComunicPLPS` — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir un block design con el datapath del conversor en lazo abierto sobre la PL, expuesto al PS por dos AXI GPIO, para ejercitar el muestreo y el control PS↔PL.

**Architecture:** Cinco bloques del datapath se instancian en el BD como *RTL modules* (nunca como los IP obsoletos de `HW/src/ip/SinAXI/`), más dos `axi_gpio` y un `processing_system7`. Un módulo nuevo `CaptureBank` congela 13 señales del mismo ciclo de reloj para que el PS las lea de a una por un selector. Todo en un dominio único de 10 MHz.

**Tech Stack:** VHDL-93 y VHDL-2008, Vivado 2025.2 (Tcl batch), GHDL 0.29 para pruebas unitarias, Zynq-7000 `xc7z007sclg400-1`, board `realdigital.org:blackboard_d:part0:1.2`.

**Spec:** `docs/superpowers/specs/2026-08-24-bd-test-comunicplps-design.md`

## Global Constraints

- **Part:** `xc7z007sclg400-1`. **Board:** `realdigital.org:blackboard_d:part0:1.2`.
- **Reloj único: 10 MHz.** `FCLK_CLK0 = 10`, sin cruce de dominios. El datapath no cierra timing a 100 MHz (camino crítico medido: 10,27 ns).
- **VHDL-2008 SOLO en:** `Declaraciones.vhd`, `TransformadaClark.vhd`, `matrixConmut.vhd`, `RL_fase.vhd`, `RL_wrapper.vhd`. Todo otro archivo queda VHDL-93. Un RTL module con top 2008 es rechazado por Vivado (`ERROR: [filemgmt 56-195]`).
- **`set_property source_mgmt_mode All [current_project]`** es obligatorio antes de crear module references, o se ignoran silenciosamente (`CRITICAL WARNING: [filemgmt 56-176]`).
- **Prohibido** usar los IP de `HW/src/ip/SinAXI/`: son copias obsoletas.
- **VLNV verificados** contra el catálogo: `xilinx.com:ip:processing_system7:5.5`, `xilinx.com:ip:axi_gpio:2.0`, `xilinx.com:inline_hdl:ilconstant:1.0`.
- **Constantes:** `Q = 180` (9 b), `Phi_I = 0` (11 b), `a0 = a1 = 0x00001B4D`, `b1 = 0x00FFFF58`, `i_frec` inicial `0x000053E3` (50 Hz).
- **GHDL** está en `F:\Program Files (x86)\Ghdl\Bin` (no está en PATH) y **falla con rutas que tienen espacios**: copiar los fuentes a un directorio sin espacios antes de analizar.
- **Vivado** está en `F:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat`.

---

## Task 1: `CaptureBank.vhd`

Módulo que congela 13 señales de 32 bits en un mismo ciclo y las devuelve de a una según un selector.

**Files:**
- Create: `HW/src/hdl/util/CaptureBank.vhd`
- Test: `HW/src/tb/tb_CaptureBank.vhd`

**Interfaces:**
- Consumes: nada.
- Produces: `entity CaptureBank` con puertos `i_clk`, `i_rst`, `i_capture`, `i_sel : std_logic_vector(31 downto 0)`, `i_d00`..`i_d12 : std_logic_vector(31 downto 0)`, `o_data : std_logic_vector(31 downto 0)`. Task 4 lo instancia en el BD como referencia `CaptureBank`.

- [ ] **Step 1: Escribir el testbench que falla**

Crear `HW/src/tb/tb_CaptureBank.vhd`. VHDL-93 puro para que GHDL 0.29 lo corra.

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_CaptureBank is
end entity tb_CaptureBank;

architecture sim of tb_CaptureBank is
    constant PER2 : time := 50 ns;              -- 10 MHz
    signal clk, rst, capture : std_logic := '0';
    signal sel  : std_logic_vector(31 downto 0) := (others => '0');
    signal d    : std_logic_vector(31 downto 0);
    signal done : boolean := false;

    type slv32_t is array (0 to 12) of std_logic_vector(31 downto 0);
    signal src : slv32_t := (others => (others => '0'));

    procedure check (signal   got : in std_logic_vector(31 downto 0);
                     constant exp : in std_logic_vector(31 downto 0);
                     constant msg : in string) is
    begin
        assert got = exp
            report msg & ": esperado " & integer'image(to_integer(unsigned(exp))) &
                   " y se leyo " & integer'image(to_integer(unsigned(got)))
            severity failure;
    end procedure;
begin
    clk <= not clk after PER2 when not done else '0';

    uut : entity work.CaptureBank
        port map (i_clk => clk, i_rst => rst, i_capture => capture, i_sel => sel,
                  i_d00 => src(0),  i_d01 => src(1),  i_d02 => src(2),
                  i_d03 => src(3),  i_d04 => src(4),  i_d05 => src(5),
                  i_d06 => src(6),  i_d07 => src(7),  i_d08 => src(8),
                  i_d09 => src(9),  i_d10 => src(10),
                  i_d11 => src(11), i_d12 => src(12),
                  o_data => d);

    estimulo : process
    begin
        -- 1) reset deja los registros en cero
        rst <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);
        rst <= '0';
        wait for 1 ns;
        check(d, x"00000000", "tras reset, sel=0");

        -- 2) captura: 13 valores distintos, un pulso, y se leen todos
        for k in 0 to 12 loop
            src(k) <= std_logic_vector(to_unsigned(16#A0# + k, 32));
        end loop;
        wait until rising_edge(clk);
        capture <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        capture <= '0';
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)), "lectura sel=" & integer'image(k));
        end loop;
        report "CAPTURA OK: los 13 registros se leen";

        -- 3) coherencia: cambiar las fuentes NO cambia lo capturado
        for k in 0 to 12 loop
            src(k) <= std_logic_vector(to_unsigned(16#5000# + k, 32));
        end loop;
        wait until rising_edge(clk); wait until rising_edge(clk);
        for k in 0 to 12 loop
            sel <= std_logic_vector(to_unsigned(k, 32));
            wait for 1 ns;
            check(d, std_logic_vector(to_unsigned(16#A0# + k, 32)),
                  "coherencia sel=" & integer'image(k));
        end loop;
        report "COHERENCIA OK: los registros no siguen a la entrada";

        -- 4) selector fuera de rango devuelve cero, incluso con el bit 31 en 1
        for v in 0 to 2 loop
            case v is
                when 0 => sel <= std_logic_vector(to_unsigned(13, 32));
                when 1 => sel <= std_logic_vector(to_unsigned(100, 32));
                when others => sel <= x"FFFFFFFF";
            end case;
            wait for 1 ns;
            check(d, x"00000000", "fuera de rango");
        end loop;
        report "FUERA DE RANGO OK";

        report "TODAS LAS VERIFICACIONES OK";
        done <= true;
        wait;
    end process;
end architecture sim;
```

- [ ] **Step 2: Correr el test y verificar que falla**

```bash
export PATH="/f/Program Files (x86)/Ghdl/Bin:$PATH"
W=/tmp/cb && rm -rf $W && mkdir -p $W
cp "HW/src/tb/tb_CaptureBank.vhd" $W/
cd $W && ghdl -a --workdir=. tb_CaptureBank.vhd
```

Esperado: FALLA con `unit "capturebank" not found` (el módulo todavía no existe).

> El directorio de trabajo NO puede tener espacios: GHDL 0.29 no recarga rutas con espacios. Usar el scratchpad de la sesión o `/tmp`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `HW/src/hdl/util/CaptureBank.vhd`:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--!
-- Banco de captura para el puente PS<->PL.
--
-- Al flanco ascendente de i_capture congela las 13 entradas en registros, todas
-- del mismo ciclo de reloj. Despues el PS barre i_sel y lee o_data, con la
-- garantia de que las 13 muestras son coherentes entre si.
--
-- VHDL-93 a proposito: es el archivo top de un module reference del block design
-- y Vivado rechaza tops en VHDL-2008 (ERROR [filemgmt 56-195]).
entity CaptureBank is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_capture : in  std_logic;                      --! nivel; se detecta el flanco ascendente
        i_sel     : in  std_logic_vector(31 downto 0);  --! indice de registro (0..12)

        i_d00, i_d01, i_d02 : in std_logic_vector(31 downto 0);  --! v_U, v_V, v_W
        i_d03, i_d04, i_d05 : in std_logic_vector(31 downto 0);  --! vsw_U, vsw_V, vsw_W
        i_d06, i_d07, i_d08 : in std_logic_vector(31 downto 0);  --! i_U, i_V, i_W
        i_d09, i_d10        : in std_logic_vector(31 downto 0);  --! alfa, beta
        i_d11, i_d12        : in std_logic_vector(31 downto 0);  --! theta_vi, direcciones

        o_data    : out std_logic_vector(31 downto 0)
    );
end entity CaptureBank;

architecture rtl of CaptureBank is

    constant N_REGS : integer := 13;
    type reg_array_t is array (0 to N_REGS - 1) of std_logic_vector(31 downto 0);

    signal regs   : reg_array_t := (others => (others => '0'));
    signal cap_z1 : std_logic := '0';

begin

    captura : process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                regs   <= (others => (others => '0'));
                cap_z1 <= '0';
            else
                cap_z1 <= i_capture;
                if i_capture = '1' and cap_z1 = '0' then
                    regs(0)  <= i_d00;  regs(1)  <= i_d01;  regs(2)  <= i_d02;
                    regs(3)  <= i_d03;  regs(4)  <= i_d04;  regs(5)  <= i_d05;
                    regs(6)  <= i_d06;  regs(7)  <= i_d07;  regs(8)  <= i_d08;
                    regs(9)  <= i_d09;  regs(10) <= i_d10;
                    regs(11) <= i_d11;  regs(12) <= i_d12;
                end if;
            end if;
        end if;
    end process captura;

    -- Se compara como unsigned y recien despues se indexa con los 4 bits bajos:
    -- convertir i_sel entero de 32 bits a integer desbordaria con el bit 31 en 1.
    seleccion : process (i_sel, regs)
    begin
        if unsigned(i_sel) < N_REGS then
            o_data <= regs(to_integer(unsigned(i_sel(3 downto 0))));
        else
            o_data <= (others => '0');
        end if;
    end process seleccion;

end architecture rtl;
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
export PATH="/f/Program Files (x86)/Ghdl/Bin:$PATH"
W=/tmp/cb && rm -rf $W && mkdir -p $W
cp "HW/src/hdl/util/CaptureBank.vhd" "HW/src/tb/tb_CaptureBank.vhd" $W/
cd $W && ghdl -a --workdir=. CaptureBank.vhd tb_CaptureBank.vhd \
  && ghdl -e --workdir=. tb_CaptureBank \
  && ghdl -r --workdir=. tb_CaptureBank --stop-time=10us
```

Esperado: PASA, con las cuatro líneas `CAPTURA OK`, `COHERENCIA OK`, `FUERA DE RANGO OK` y `TODAS LAS VERIFICACIONES OK`. Sin `severity failure`.

> Este código ya se corrió con GHDL 0.29 al escribir el plan y pasa las cuatro comprobaciones
> (la última a los 666 ns simulados). Si falla, es por una diferencia de transcripción, no de
> diseño. El caso `0xFFFFFFFF` del test es el que verifica que `unsigned(i_sel) < N_REGS` se
> compare **antes** de convertir a `integer`: convertir 32 bits con el bit 31 en 1 desbordaría.

- [ ] **Step 5: Commit**

```bash
git add HW/src/hdl/util/CaptureBank.vhd HW/src/tb/tb_CaptureBank.vhd
git commit -m "Agrega CaptureBank, banco de captura coherente para el puente PS-PL"
```

---

## Task 2: `RL_bd.vhd` y registro de los fuentes nuevos

`RL_wrapper` usa `to_sfixed` en su architecture, así que es VHDL-2008 y Vivado no lo acepta como top de un RTL module. Hace falta un wrapper VHDL-93 encima. Esta tarea además registra los dos archivos nuevos en `build.tcl`.

**Files:**
- Create: `HW/src/hdl/wrappers/RL_bd.vhd`
- Modify: `build.tcl` (lista `files` del fileset `sources_1`)

**Interfaces:**
- Consumes: `CaptureBank` de Task 1 (solo para registrarlo en `build.tcl`).
- Produces: `entity RL_bd` con puertos `i_clk`, `i_rst`, `i_c_a0`, `i_c_a1`, `i_c_b1`, `i_U`, `i_V`, `i_W`, `o_Iu`, `o_Iv`, `o_Iw`, todos `std_logic_vector(31 downto 0)` salvo los dos primeros. Task 4 lo instancia como referencia `RL_bd`.

- [ ] **Step 1: Escribir `RL_bd.vhd`**

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--!
-- Envoltorio VHDL-93 de RL_wrapper para poder instanciarlo en el block design.
--
-- RL_wrapper usa to_sfixed en su architecture, o sea que es VHDL-2008, y Vivado
-- rechaza un top VHDL-2008 en un module reference (ERROR [filemgmt 56-195]).
-- Las dependencias si pueden ser 2008: solo el archivo top tiene que ser 93.
--
-- Fija los genericos en Q8.24, el formato que usa el resto del datapath.
entity RL_bd is
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;

        i_c_a0 : in  std_logic_vector(31 downto 0);
        i_c_a1 : in  std_logic_vector(31 downto 0);
        i_c_b1 : in  std_logic_vector(31 downto 0);

        i_U    : in  std_logic_vector(31 downto 0);
        i_V    : in  std_logic_vector(31 downto 0);
        i_W    : in  std_logic_vector(31 downto 0);

        o_Iu   : out std_logic_vector(31 downto 0);
        o_Iv   : out std_logic_vector(31 downto 0);
        o_Iw   : out std_logic_vector(31 downto 0)
    );
end entity RL_bd;

architecture rtl of RL_bd is
begin

    nucleo : entity work.RL_wrapper
        generic map (
            INT_BITS  => 8,
            FRAC_BITS => 24
        )
        port map (
            i_clk => i_clk, i_rst => i_rst,
            i_c_a0 => i_c_a0, i_c_a1 => i_c_a1, i_c_b1 => i_c_b1,
            i_U => i_U, i_V => i_V, i_W => i_W,
            o_Iu => o_Iu, o_Iv => o_Iv, o_Iw => o_Iw
        );

end architecture rtl;
```

- [ ] **Step 2: Agregar los dos archivos nuevos a `build.tcl`**

En la lista `files` del fileset `sources_1`, después de la línea de `DienteSierraGen.vhd`, agregar:

```tcl
  [file normalize "${origin_dir}/HW/src/hdl/util/CaptureBank.vhd"] \
```

y después de la línea de `TClark_wrapper.vhd`, agregar:

```tcl
  [file normalize "${origin_dir}/HW/src/hdl/wrappers/RL_bd.vhd"] \
```

- [ ] **Step 3: Verificar que ambos cargan como RTL module en un BD**

Crear un script temporal y correrlo. Es la prueba que importa: que Vivado los acepte como referencia.

```tcl
# probe_rtlmod.tcl
set R "F:/FPGA/Potencia FPGA/MatrixConverter/HW/src/hdl"
create_project -in_memory -part xc7z007sclg400-1
set_property board_part realdigital.org:blackboard_d:part0:1.2 [current_project]
set_property source_mgmt_mode All [current_project]
add_files -norecurse [list \
  $R/util/Declaraciones.vhd $R/util/CaptureBank.vhd $R/RL_fase.vhd \
  $R/wrappers/RL_wrapper.vhd $R/wrappers/RL_bd.vhd ]
set_property file_type {VHDL 2008} [get_files [list \
  $R/util/Declaraciones.vhd $R/RL_fase.vhd $R/wrappers/RL_wrapper.vhd ]]
create_bd_design probe
foreach m {CaptureBank RL_bd} {
    if {[catch {create_bd_cell -type module -reference $m c_$m}]} {
        puts "MODULO|$m|FALLA"
    } else {
        puts "MODULO|$m|OK|[llength [get_bd_pins -of [get_bd_cells c_$m]]] pines"
    }
}
```

```bash
"/f/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -nojournal -nolog \
  -source probe_rtlmod.tcl 2>&1 | grep -E "^MODULO\|"
```

Esperado exactamente:
```
MODULO|CaptureBank|OK|18 pines
MODULO|RL_bd|OK|11 pines
```

Si alguno dice `FALLA`, revisar que el archivo NO esté marcado como `VHDL 2008`.

- [ ] **Step 4: Verificar que `build.tcl` sigue siendo Tcl válido**

```bash
tclsh -c 'set f [open "build.tcl" r]; set b [read $f]; close $f; \
  if {[info complete $b]} {puts "SINTAXIS OK"} else {puts "INCOMPLETO"; exit 1}'
```

Esperado: `SINTAXIS OK`. Y que las rutas nuevas existan:

```bash
grep -o 'HW/src/[^"]*\.vhd' build.tcl | while read f; do \
  [ -e "$f" ] || echo "FALTA $f"; done; echo "chequeo terminado"
```

Esperado: ningún `FALTA`.

- [ ] **Step 5: Commit**

```bash
git add HW/src/hdl/wrappers/RL_bd.vhd build.tcl
git commit -m "Agrega RL_bd, envoltorio VHDL-93 de RL_wrapper para el block design"
```

---

## Task 3: `create_bd.tcl` — infraestructura PS↔PL

Primera mitad del script: PS7 a 10 MHz y los dos `axi_gpio`, sin datapath. Al terminar esta tarea el puente PS↔PL ya es un BD válido y sintetizable — el objetivo declarado del banco.

**Files:**
- Create: `HW/src/bd/test_ComunicPLPS/create_bd.tcl`

**Interfaces:**
- Consumes: nada del proyecto; solo IP del catálogo.
- Produces: el BD `test_ComunicPLPS` con las celdas `ps7`, `axi_gpio_ctrl`, `axi_gpio_data` y la red de reloj `clk_10m`. Task 4 agrega el datapath a este mismo script.

- [ ] **Step 1: Escribir el script**

Crear `HW/src/bd/test_ComunicPLPS/create_bd.tcl`:

```tcl
# Construye el block design test_ComunicPLPS desde cero.
#   vivado -mode batch -source HW/src/bd/test_ComunicPLPS/create_bd.tcl
#
# Banco de pruebas del puente PS<->PL. Ver
# docs/superpowers/specs/2026-08-24-bd-test-comunicplps-design.md

set origin_dir [file normalize [file dirname [info script]]/../../../..]
set hdl        "$origin_dir/HW/src/hdl"
set bd_name    "test_ComunicPLPS"

puts "INFO: raiz del repo: $origin_dir"

create_project -in_memory -part xc7z007sclg400-1
set_property board_part realdigital.org:blackboard_d:part0:1.2 [current_project]

# Obligatorio: sin esto los module references se ignoran en silencio
# (CRITICAL WARNING [filemgmt 56-176]).
set_property source_mgmt_mode All [current_project]

# ---------------------------------------------------------------- fuentes
set fuentes [list \
  $hdl/util/Declaraciones.vhd  $hdl/util/sine_lut_pkg.vhd \
  $hdl/util/sine_generator.vhd $hdl/util/red_sector.vhd \
  $hdl/util/CaptureBank.vhd \
  $hdl/AC_Source.vhd           $hdl/TransformadaClark.vhd \
  $hdl/CORDIC_atan2.vhd        $hdl/Modulador.vhd \
  $hdl/matrixConmut.vhd        $hdl/RL_fase.vhd \
  $hdl/wrappers/SVM_wrapper.vhd  $hdl/wrappers/TClark_wrapper.vhd \
  $hdl/wrappers/RL_wrapper.vhd   $hdl/wrappers/RL_bd.vhd ]
add_files -norecurse $fuentes

# VHDL-2008 SOLO donde hace falta. Un module reference con top 2008 es
# rechazado por Vivado (ERROR [filemgmt 56-195]).
set_property file_type {VHDL 2008} [get_files [list \
  $hdl/util/Declaraciones.vhd $hdl/TransformadaClark.vhd \
  $hdl/matrixConmut.vhd $hdl/RL_fase.vhd $hdl/wrappers/RL_wrapper.vhd ]]

# ---------------------------------------------------------------- el BD
create_bd_design $bd_name

# --- Zynq PS, con FCLK0 a 10 MHz ---
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} $ps
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {10} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} ] $ps

set clk_10m [get_bd_pins ps7/FCLK_CLK0]

# --- GPIO de control: bits de control + step de frecuencia ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_OUTPUTS {1}   CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_DOUT_DEFAULT {0x00000001} \
    CONFIG.C_DOUT_DEFAULT_2 {0x000053E3} ] [get_bd_cells axi_gpio_ctrl]

# --- GPIO de datos: dato capturado (in) + selector (out) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_data
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_INPUTS {1}    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_GPIO2_WIDTH {32} ] [get_bd_cells axi_gpio_data]

# --- interconexion AXI, en el mismo dominio de 10 MHz ---
foreach g {axi_gpio_ctrl axi_gpio_data} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config [list Master "/ps7/M_AXI_GP0" Clk "Auto"] \
        [get_bd_intf_pins $g/S_AXI]
}

assign_bd_address
regenerate_bd_layout
validate_bd_design -force
save_bd_design

puts "INFO: BD $bd_name construido y validado"
```

`C_DOUT_DEFAULT 0x00000001` deja `rst = 1` al arrancar; `C_DOUT_DEFAULT_2 0x000053E3` deja el step en 50 Hz. Así el sistema arranca en reset y con frecuencia útil, sin depender de que el PS escriba nada.

- [ ] **Step 2: Correr el script y verificar que construye y valida**

```bash
cd "F:/FPGA/Potencia FPGA/MatrixConverter"
"/f/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -nojournal -nolog \
  -source HW/src/bd/test_ComunicPLPS/create_bd.tcl 2>&1 | tail -30
```

Esperado: la línea `INFO: BD test_ComunicPLPS construido y validado`, y **ningún** `ERROR:` ni `CRITICAL WARNING:` en la salida.

- [ ] **Step 3: Verificar que el reloj quedó realmente en 10 MHz**

Agregar al final del script, antes del `puts` final:

```tcl
set f_real [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]
puts "RELOJ|FCLK_CLK0 = $f_real MHz"
if {$f_real != 10} {
    puts "AVISO: FCLK0 quedo en $f_real MHz, no 10. Recalcular i_frec y los coeficientes del RL."
}
```

Volver a correr. Esperado: `RELOJ|FCLK_CLK0 = 10 MHz` sin el aviso.

> Si Vivado reporta otra frecuencia, es el riesgo 1 del spec: hay que recalcular `i_frec` (`round(f_out·2³²/f_clk)`) y los coeficientes del RL, que dependen de `Ts`.

- [ ] **Step 4: Commit**

```bash
git add HW/src/bd/test_ComunicPLPS/create_bd.tcl
git commit -m "Agrega el script del BD test_ComunicPLPS con PS7 a 10 MHz y los dos AXI GPIO"
```

---

## Task 4: `create_bd.tcl` — datapath y cableado

Segunda mitad: los cinco bloques del datapath, las constantes y `CaptureBank`, todo cableado.

**Files:**
- Modify: `HW/src/bd/test_ComunicPLPS/create_bd.tcl` (agregar antes de `assign_bd_address`)

**Interfaces:**
- Consumes: `CaptureBank` (Task 1), `RL_bd` (Task 2), la infraestructura de Task 3 (`clk_10m`, `axi_gpio_ctrl`, `axi_gpio_data`).
- Produces: el BD completo y su wrapper HDL `test_ComunicPLPS_wrapper`.

- [ ] **Step 1: Agregar el datapath al script**

Insertar **antes** de la línea `assign_bd_address`:

```tcl
# ============================ datapath en lazo abierto ============================

# --- separar los bits de control del GPIO ---
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_rst
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} \
                         CONFIG.DOUT_WIDTH {1}] [get_bd_cells sl_rst]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_en
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1} \
                         CONFIG.DOUT_WIDTH {1}] [get_bd_cells sl_en]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_cap
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2} \
                         CONFIG.DOUT_WIDTH {1}] [get_bd_cells sl_cap]

foreach s {sl_rst sl_en sl_cap} {
    connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins $s/Din]
}

# --- constantes del datapath ---
proc mk_const {nombre ancho valor} {
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 $nombre
    set_property -dict [list CONFIG.CONST_WIDTH $ancho CONFIG.CONST_VAL $valor] \
        [get_bd_cells $nombre]
}
mk_const Q       9  180        ;# 180/256 = 0,703125
mk_const Phi_I   11 0
mk_const Coef_a0 32 0x00001B4D ;# 0,000416577 en Q8.24
mk_const Coef_a1 32 0x00001B4D
mk_const Coef_b1 32 0x00FFFF58 ;# 0,999989986 en Q8.24

# --- bloques del datapath (RTL modules) ---
create_bd_cell -type module -reference AC_Source      AC_Source_0
create_bd_cell -type module -reference TClark_wrapper TClark_Vi
create_bd_cell -type module -reference CORDIC_atan2   CORDIC_0
create_bd_cell -type module -reference SVM_wrapper    SVM_0
create_bd_cell -type module -reference RL_bd          RL_0
create_bd_cell -type module -reference CaptureBank    Capture_0

# --- reloj y reset a todo el datapath ---
foreach par {AC_Source_0/i_clk TClark_Vi/i_clk CORDIC_0/clk SVM_0/i_clk
             RL_0/i_clk Capture_0/i_clk} {
    connect_bd_net $clk_10m [get_bd_pins $par]
}
foreach par {AC_Source_0/i_rst TClark_Vi/i_rst CORDIC_0/rst RL_0/i_rst
             Capture_0/i_rst} {
    connect_bd_net [get_bd_pins sl_rst/Dout] [get_bd_pins $par]
}

# --- fuente trifasica; la frecuencia la fija el PS por el canal 2 del GPIO ---
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio2_io_o] [get_bd_pins AC_Source_0/i_frec]

# --- Clark de la tension de entrada, disparado por el trigger del modulador ---
foreach {a b} {AC_Source_0/o_U TClark_Vi/i_U  AC_Source_0/o_V TClark_Vi/i_V
               AC_Source_0/o_W TClark_Vi/i_W} {
    connect_bd_net [get_bd_pins $a] [get_bd_pins $b]
}
connect_bd_net [get_bd_pins SVM_0/o_trg_calculo] [get_bd_pins TClark_Vi/i_start]

# --- CORDIC: alfa/beta -> angulo ---
connect_bd_net [get_bd_pins TClark_Vi/o_alfa]   [get_bd_pins CORDIC_0/x_in]
connect_bd_net [get_bd_pins TClark_Vi/o_beta]   [get_bd_pins CORDIC_0/y_in]
connect_bd_net [get_bd_pins TClark_Vi/o_valido] [get_bd_pins CORDIC_0/start]

# --- modulador: AMBOS angulos salen de la tension de entrada ---
connect_bd_net [get_bd_pins CORDIC_0/angle_out] [get_bd_pins SVM_0/i_al_o]
connect_bd_net [get_bd_pins CORDIC_0/angle_out] [get_bd_pins SVM_0/i_be_i]
connect_bd_net [get_bd_pins Q/const]     [get_bd_pins SVM_0/i_q_i]
connect_bd_net [get_bd_pins Phi_I/const] [get_bd_pins SVM_0/i_phi_i]
connect_bd_net [get_bd_pins sl_en/Dout]  [get_bd_pins SVM_0/i_enable]
foreach {a b} {AC_Source_0/o_U SVM_0/i_U  AC_Source_0/o_V SVM_0/i_V
               AC_Source_0/o_W SVM_0/i_W} {
    connect_bd_net [get_bd_pins $a] [get_bd_pins $b]
}

# --- carga RL sobre la tension conmutada ---
connect_bd_net [get_bd_pins Coef_a0/const] [get_bd_pins RL_0/i_c_a0]
connect_bd_net [get_bd_pins Coef_a1/const] [get_bd_pins RL_0/i_c_a1]
connect_bd_net [get_bd_pins Coef_b1/const] [get_bd_pins RL_0/i_c_b1]
foreach {a b} {SVM_0/o_U RL_0/i_U  SVM_0/o_V RL_0/i_V  SVM_0/o_W RL_0/i_W} {
    connect_bd_net [get_bd_pins $a] [get_bd_pins $b]
}

# --- banco de captura: 13 senales del mismo ciclo ---
connect_bd_net [get_bd_pins sl_cap/Dout]            [get_bd_pins Capture_0/i_capture]
connect_bd_net [get_bd_pins axi_gpio_data/gpio2_io_o] [get_bd_pins Capture_0/i_sel]
connect_bd_net [get_bd_pins Capture_0/o_data]       [get_bd_pins axi_gpio_data/gpio_io_i]

foreach {pin fuente} {
    i_d00 AC_Source_0/o_U   i_d01 AC_Source_0/o_V   i_d02 AC_Source_0/o_W
    i_d03 SVM_0/o_U         i_d04 SVM_0/o_V         i_d05 SVM_0/o_W
    i_d06 RL_0/o_Iu         i_d07 RL_0/o_Iv         i_d08 RL_0/o_Iw
    i_d09 TClark_Vi/o_alfa  i_d10 TClark_Vi/o_beta
} {
    connect_bd_net [get_bd_pins $fuente] [get_bd_pins Capture_0/$pin]
}
```

- [ ] **Step 2: Cablear los dos registros de ancho distinto**

`i_d11` (ángulo, 11 bits) y `i_d12` (direcciones, 18 bits) son más angostos que los 32 bits del banco. Se extienden con `xlconcat` contra una constante de ceros. Agregar a continuación:

```tcl
# theta_vi: 11 bits utiles + 21 ceros
mk_const Cero21 21 0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cc_ang
set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {11} \
                         CONFIG.IN1_WIDTH {21}] [get_bd_cells cc_ang]
connect_bd_net [get_bd_pins CORDIC_0/angle_out] [get_bd_pins cc_ang/In0]
connect_bd_net [get_bd_pins Cero21/const]       [get_bd_pins cc_ang/In1]
connect_bd_net [get_bd_pins cc_ang/dout]        [get_bd_pins Capture_0/i_d11]

# direcciones: 18 bits utiles + 14 ceros
mk_const Cero14 14 0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cc_dir
set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {18} \
                         CONFIG.IN1_WIDTH {14}] [get_bd_cells cc_dir]
connect_bd_net [get_bd_pins SVM_0/o_direcciones_Matriz] [get_bd_pins cc_dir/In0]
connect_bd_net [get_bd_pins Cero14/const]               [get_bd_pins cc_dir/In1]
connect_bd_net [get_bd_pins cc_dir/dout]                [get_bd_pins Capture_0/i_d12]
```

- [ ] **Step 3: Generar el wrapper HDL**

Reemplazar el bloque final del script (desde `assign_bd_address`) por:

```tcl
assign_bd_address
regenerate_bd_layout
validate_bd_design -force
save_bd_design

make_wrapper -files [get_files $bd_name.bd] -top -import
generate_target all [get_files $bd_name.bd]

puts "INFO: BD $bd_name construido, validado y con wrapper generado"
```

- [ ] **Step 4: Correr el script completo y verificar**

```bash
cd "F:/FPGA/Potencia FPGA/MatrixConverter"
"/f/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -nojournal -nolog \
  -source HW/src/bd/test_ComunicPLPS/create_bd.tcl 2>&1 \
  | grep -E "ERROR|CRITICAL|INFO: BD|RELOJ\|" | head -20
```

Esperado: `RELOJ|FCLK_CLK0 = 10 MHz` y `INFO: BD test_ComunicPLPS construido, validado y con wrapper generado`, sin ninguna línea `ERROR:` ni `CRITICAL WARNING:`.

Si aparece `[BD 41-237] Bus Interface property ... width mismatch`, es un ancho mal puesto en un `xlslice` o `xlconcat`: comparar contra los anchos reales (`angle_out` 11 bits, `o_direcciones_Matriz` 18 bits).

- [ ] **Step 5: Verificar que las 13 entradas del banco quedaron conectadas**

Agregar al script, antes del `puts` final:

```tcl
set sueltos {}
foreach n {00 01 02 03 04 05 06 07 08 09 10 11 12} {
    set p [get_bd_pins Capture_0/i_d$n]
    if {[llength [get_bd_nets -quiet -of $p]] == 0} { lappend sueltos i_d$n }
}
if {[llength $sueltos]} {
    puts "CAPTURA|SIN CONECTAR: $sueltos" ; error "faltan conexiones en CaptureBank"
} else {
    puts "CAPTURA|las 13 entradas conectadas"
}
```

Volver a correr. Esperado: `CAPTURA|las 13 entradas conectadas`.

- [ ] **Step 6: Commit**

```bash
git add HW/src/bd/test_ComunicPLPS/create_bd.tcl
git commit -m "Completa el BD test_ComunicPLPS con el datapath en lazo abierto y la captura"
```

---

## Notas para quien ejecute

- **No commitear** `test_ComunicPLPS.bd`, `.bda`, `.bxml` ni `ui/`: son artefactos generados. El BD se versiona como el script Tcl. Si aparecen en `git status`, agregarlos a `.gitignore`.
- **El banco no hace conversión de frecuencia.** Con `al_o = be_i` la salida queda enganchada a los 50 Hz de entrada. Es lo esperado, no un error.
- **`RL_fase` suma `b1·I[n-1]`** aunque el comentario de su encabezado diga que resta. Los coeficientes de este plan ya tienen el signo correcto.
- Después de Task 4, el paso natural (fuera de este plan) es el software del PS: barrer el selector y volcar los 13 valores.
