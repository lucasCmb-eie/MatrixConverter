# BD `test_ComunicPLPS` — banco de pruebas PS↔PL — diseño

Fecha: 2026-08-24
Estado: propuesta, pendiente de aprobación
Subproyecto: **B** (de A/B/C — ver `2026-08-24-lazo-corriente-pr-design.md` §2)

---

## 1. Objetivo

Un block design mínimo que ponga el datapath del conversor en lazo abierto sobre la PL y lo
exponga al PS por AXI GPIO, para **ejercitar la comunicación PS↔PL**: muestrear datos del PL
desde el PS y controlar el PL desde el PS.

El objetivo NO es estudiar el conversor. Es tener un banco donde probar el puente. El datapath
está para producir señales reales y no constantes triviales.

### Criterio de éxito

- El BD se construye y pasa `validate_bd_design` sin errores.
- El PS puede: liberar el reset, habilitar el modulador, cambiar la frecuencia de la fuente
  escribiendo un registro, disparar una captura y leer los 13 valores capturados.
- Los valores leídos son coherentes entre sí (todos del mismo ciclo de reloj) y reconstruyen
  formas de onda al graficarlos.

### Fuera de alcance

- El lazo de control PR (subproyecto A).
- AXI-Lite propio, BRAM de captura, DMA, interrupciones. Acá solo AXI GPIO.
- Frecuencia de salida independiente de la de entrada (subproyecto C).
- Cierre de timing de implementación, bitstream, hardware real.

---

## 2. Relación con el subproyecto B del spec de control

El spec del lazo PR define B como "PS7 + AXI-Lite desde cero, registros de consigna y
coeficientes, buffer de captura, IRQ", y anota que **B no se puede diseñar antes que A** porque el
mapa de registros de B *es* la lista de consignas que A necesita.

Eso sigue siendo cierto y este documento no lo contradice: esto **no es** B, es un precursor de B.
No define ningún mapa de registros de control del lazo, porque no hay lazo. Define un banco de
GPIO para validar el puente antes de que exista la lista de registros definitiva.

---

## 3. Arquitectura

```
   i_frec (del PS) ──→ AC_Source ──┬──→ v_abc ─────────────────────────────┐
                        (50 Hz)    │                                       │
                                   └──→ TClark_Vi ──→ α,β ──→ CORDIC_atan2 │
                                            ▲                      │ θ_vi  │
                                       trg_calculo                 │       │
                                            │           ┌──────────┴───────┴──┐
                                            │        i_al_o = i_be_i = θ_vi   │
                                            │                    ↓            │
                     Q, Phi_I (ilconstant) ─┼───────→  SVM_wrapper  ←─────────┘
                                            │                ↓ v conmutada
                                            └──── o_trg_calculo
                                                             ↓
                    a0, a1, b1 (ilconstant) ──────→  RL_wrapper
                                                             ↓ i_abc
                                                       CaptureBank ──→ axi_gpio_data
```

### Decisiones y su porqué

**Los cinco bloques van sueltos en el BD como RTL modules**, no como IP empaquetados. Los IP de
`HW/src/ip/SinAXI/` son copias obsoletas (ver `CLAUDE.md`): su `Modulador.vhd` es de 2026-02-14 y
no tiene los arreglos de agosto, y su `AC_Source.vhd` no tiene el `i_frec` de 32 bits. Usarlos
sintetizaría RTL viejo. Un RTL module toma el archivo directamente del fileset, así que el BD
siempre ve `HW/src/hdl/`, que es la fuente de verdad.

**Ambos ángulos del modulador salen de la tensión de entrada.** `i_al_o` e `i_be_i` se conectan
los dos a la salida del mismo `CORDIC_atan2`, que vectoriza el `α,β` de la tensión de entrada.

> Consecuencia a tener presente al mirar los datos: con `al_o = be_i` la tensión de salida queda
> enganchada en frecuencia y fase a la de entrada, o sea ~50 Hz. El conversor **no** hace
> conversión de frecuencia en este banco. Es determinístico y estable, que es lo que conviene para
> validar comunicación, pero no es un ensayo de conversión.

**Un solo `TransformadaClark`.** El de tensión, que el CORDIC necesita. Las corrientes del RL se
capturan en `abc`; un segundo Clark para corriente no aporta nada a este banco y lo pide el
subproyecto A, no este.

**`o_trg_calculo` del `SVM_wrapper` dispara el `i_start` del Clark**, igual que en
`tb_SVM_Wrapper.vhd`. Es el mismo encadenamiento ya validado en simulación.

---

## 4. Reloj

**Dominio único de 10 MHz**: `FCLK_CLK0 = 10 MHz` alimenta el datapath, los AXI GPIO y
`M_AXI_GP0_ACLK`. No hay cruce de dominios, ni sincronizadores, ni constraints de cruce.

### Por qué no 100 MHz en el datapath

Medido con síntesis out-of-context de `SVM_wrapper` sobre `xc7z007sclg400-1` (speed grade −1):

| Objetivo | Camino crítico | WNS | Resultado |
|---|---|---|---|
| 10 MHz (100 ns) | 10,27 ns | +89,73 ns | cierra holgado |
| 100 MHz (10 ns) | 10,27 ns | −0,27 ns | **no cierra** |

`f_max ≈ 97,4 MHz`. Es una estimación post-síntesis, sin place & route: el número real de
implementación es peor, nunca mejor. El camino crítico está en el `Modulador` (división
restauradora bit-serial) y el `CORDIC_atan2` (20 iteraciones).

### Por qué tampoco AXI a 100 MHz con datapath a 10 MHz

Es técnicamente viable y no fue descartado por riesgo: las tres señales que cruzarían son estables
cuando se usan (`i_frec` y el selector los escribe el PS y quedan quietos; el dato capturado está
congelado mientras se lee), así que alcanzaría con sincronizadores de 2 FF en los bits de control y
`set_max_delay -datapath_only` en los buses, sin FIFOs.

Se descartó por costo/beneficio: la ganancia sería pasar de ~20 µs a ~2 µs por barrido de los 13
registros, irrelevante frente al overhead del software del PS que orquesta las lecturas. A cambio
agrega dos dominios, constraints de cruce y superficie de error a un banco cuyo propósito es
justamente que el puente sea confiable.

Si más adelante aparece captura masiva por BRAM o DMA, ahí sí conviene revisar esta decisión.

### Parámetros temporales resultantes

```
Ts (modulador) = 2048 / 10 MHz = 204,8 µs     f_sw = 4882,81 Hz
Ts (RL)        = 100 ns
```

---

## 5. Constantes del datapath

Se instancian como `xilinx.com:inline_hdl:ilconstant:1.0` en el BD, el mismo patrón que usaba
`design_Basico.tcl` para `Q`, `Phi_Entrada` y los coeficientes.

| Constante | Ancho | Valor | Origen |
|---|---|---|---|
| `Q` (`i_q_i`) | 9 | `0b010110100` = 180 → 0,703125 | el de `tb_SVM_Wrapper.vhd:21`; bajo el límite 0,866 |
| `Phi_I` (`i_phi_i`) | 11 | `0b00000000000` = 0 | sin desfase entre corriente de salida y tensión de entrada |
| `a0` = `a1` | 32 | `0x00001B4D` = 6989 → 0,000416577 | Tustin del RL a Ts = 100 ns |
| `b1` | 32 | `0x00FFFF58` = 16777048 → 0,999989986 | ídem |

### De dónde salen los coeficientes del RL

`RL_fase.vhd` implementa `I[n] = a0·U[n] + a1·U[n-1] + b1·I[n-1]`.

> **Ojo con el signo.** El comentario del encabezado del archivo (línea 8) dice `− b1·I[n-1]`, pero
> la implementación real (línea 94) hace `sum_final_v := sum_inputs + mult_b1`, o sea **suma**. El
> `b1` que hay que cargar es el coeficiente positivo de realimentación, cercano a +1. Por eso
> `tb_RL` usa `0,999999` y no un valor negativo.

Discretización bilineal de una carga RL:

```
a0 = a1 = 1 / (R + 2L/Ts)          b1 = (2L/Ts − R) / (2L/Ts + R)
```

Invirtiendo los coeficientes que `tb_RL` ya usaba (`a0 = 4,166e-5`, `b1 = 0,999999`, Ts = 10 ns) se
recupera la carga que el proyecto venía modelando:

```
R = 0,012002 Ω      L = 1,200191e-4 H      τ = L/R = 10,0 ms
```

Que τ dé 10,0 ms redondo confirma que la inversión es correcta y no una casualidad numérica. Con
esa misma carga a Ts = 100 ns salen los valores de la tabla. La carga no cambia; cambia el período
de muestreo.

---

## 6. Interfaz PS↔PL

Dos `axi_gpio`, ambos en modo dual channel, ambos a 10 MHz. Las direcciones base las asigna
`assign_bd_address`; el software del PS las toma de `xparameters.h`.

### `axi_gpio_ctrl` — control (PS → PL)

| Canal | Dir. | Ancho | Contenido |
|---|---|---|---|
| GPIO (ch1) | out | 32 | bit 0 `rst`, bit 1 `enable_SVM`, bit 2 `capture`, bits 31:3 sin uso |
| GPIO2 (ch2) | out | 32 | `i_frec` — step del NCO de `AC_Source` |

`i_frec = round(f_out · 2³² / 10 MHz) = round(f_out · 429,4967)`. Para 50 Hz: `21475`
(`0x000053E3`). Que la frecuencia sea escribible desde el PS es posible gracias al commit
`cb29ec1`, que convirtió `i_frec` en step de 32 bits.

`capture` no necesita ser un pulso corto: el PS lo pone en alto y lo baja en dos transacciones AXI
distintas, con microsegundos en el medio. `CaptureBank` detecta el **flanco ascendente**, así que
una captura por escritura de 0→1.

### `axi_gpio_data` — muestreo (PL → PS)

| Canal | Dir. | Ancho | Contenido |
|---|---|---|---|
| GPIO (ch1) | in | 32 | dato del registro seleccionado |
| GPIO2 (ch2) | out | 32 | selector (0..12) |

### Secuencia de uso desde el PS

1. Escribir `rst = 1`, esperar, escribir `rst = 0`.
2. Escribir `i_frec` con el step deseado.
3. Escribir `enable_SVM = 1`.
4. Escribir `capture = 1`, luego `capture = 0`.
5. Para cada índice 0..12: escribir el selector, leer el dato.

Los 13 valores del paso 5 son todos del mismo ciclo de reloj, por el registro de captura.

---

## 7. `CaptureBank.vhd` — módulo nuevo

`HW/src/hdl/util/CaptureBank.vhd`. VHDL-93 (sin `fixed_pkg`), así que es simulable con el GHDL
local — ver la nota de verificación.

Los datos entran como **13 puertos escalares** y no como un array: los arrays no se conectan
bien en el canvas del BD, y este modulo existe justamente para ser cableado ahi.

```vhdl
entity CaptureBank is
    port (
        i_clk     : in  std_logic;
        i_rst     : in  std_logic;
        i_capture : in  std_logic;                      -- nivel; se detecta flanco ascendente
        i_sel     : in  std_logic_vector(31 downto 0);  -- indice de registro

        i_d00, i_d01, i_d02 : in std_logic_vector(31 downto 0);  -- v_U, v_V, v_W
        i_d03, i_d04, i_d05 : in std_logic_vector(31 downto 0);  -- vsw_U, vsw_V, vsw_W
        i_d06, i_d07, i_d08 : in std_logic_vector(31 downto 0);  -- i_U, i_V, i_W
        i_d09, i_d10        : in std_logic_vector(31 downto 0);  -- alfa, beta
        i_d11, i_d12        : in std_logic_vector(31 downto 0);  -- theta_vi, direcciones

        o_data    : out std_logic_vector(31 downto 0)   -- registro seleccionado
    );
end entity;
```

Comportamiento:

- Flanco ascendente de `i_capture` → `regs(k) <= i_data(k)` para todo `k`, en un solo ciclo.
- `o_data <= regs(to_integer(unsigned(i_sel)))`, con `i_sel` fuera de rango devolviendo ceros
  (evita un índice ilegal si el PS escribe cualquier cosa).
- `i_rst` pone los registros en cero.

No se usa el tipo `vector` de `Declaraciones.vhd`: ese paquete importa `fixed_pkg` y arrastrarlo
obligaría a VHDL-2008, que es justo lo que se quiere evitar acá para poder simular el módulo con
el GHDL local.

### Mapa del selector

| Índice | Señal | Origen |
|---|---|---|
| 0, 1, 2 | `v_U`, `v_V`, `v_W` | `AC_Source.o_U/o_V/o_W` |
| 3, 4, 5 | `vsw_U`, `vsw_V`, `vsw_W` | `SVM_wrapper.o_U/o_V/o_W` |
| 6, 7, 8 | `i_U`, `i_V`, `i_W` | `RL_wrapper.o_Iu/o_Iv/o_Iw` |
| 9 | `alfa` | `TransformadaClark.o_alfa` |
| 10 | `beta` | `TransformadaClark.o_beta` |
| 11 | `theta_vi` | `CORDIC_atan2.angle_out`, 11 bits en 10:0, resto en cero |
| 12 | `direcciones` | `SVM_wrapper.o_direcciones_Matriz`, 18 bits en 17:0, resto en cero |

Los índices 0..10 son Q8.24 con signo; 11 y 12 son enteros sin signo.

---

## 8. Archivos

| Archivo | Estado | Contenido |
|---|---|---|
| `HW/src/hdl/util/CaptureBank.vhd` | nuevo | §7 |
| `HW/src/bd/test_ComunicPLPS/create_bd.tcl` | nuevo | script que construye el BD completo |
| `build.tcl` | modificar | agregar `CaptureBank.vhd` a `sources_1` |

El script **recrea** el BD desde cero. El `test_ComunicPLPS.bd` que existe hoy está vacío
(`design_tree: {}`), así que no se pierde trabajo. Los `.bda`, `.bxml` y `ui/` los regenera Vivado.

Decisión deliberada: el BD se versiona como **script Tcl**, no como `.bd`. El `.bd` es JSON
generado, ilegible en un diff y atado a la versión de la herramienta; el Tcl se revisa y se
reconstruye. Es el mismo criterio con el que existía `design_Basico.tcl`.

---

## 9. Verificación

| Qué | Cómo | ¿Se verifica? |
|---|---|---|
| El BD se construye | `vivado -mode batch -source create_bd.tcl` | sí |
| El BD es válido | `validate_bd_design -force` dentro del script | sí |
| El wrapper se genera | `make_wrapper` + `generate_target all` | sí |
| `CaptureBank` funciona | testbench GHDL: captura coherente, selector fuera de rango, reset | sí |
| Port maps del datapath | script de chequeo contra las entities | sí |
| Timing de implementación | — | **no**: requiere síntesis+implementación completas |
| Funcionamiento sobre hardware | — | **no**: requiere placa |

Las cinco primeras filas son verificación ejecutable, no revisión a ojo, y se corren como parte de
la implementación.

Vivado 2025.2 está en `F:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat` y corre en modo batch, así
que las cuatro primeras filas son verificación real, no revisión a ojo.

La síntesis OOC de §4 ya se corrió y es la que respalda la decisión de reloj.

---

## 10. Riesgos conocidos

1. **`FCLK_CLK0` a 10 MHz exactos.** El PLL del PS7 divide desde el IO PLL con divisores enteros;
   10 MHz es alcanzable, pero si Vivado reporta una frecuencia efectiva distinta hay que releer el
   valor real y recalcular `i_frec` y los coeficientes del RL, que dependen de `Ts`.
2. **El banco no valida conversión de frecuencia**, por lo dicho en §3. Si se quiere ver el
   conversor haciendo su trabajo, hace falta el subproyecto C.
3. **`CaptureBank` con 13 puertos escalares de 32 bits** es verboso de cablear en el BD. Es el
   precio de que los arrays no se conecten bien en el canvas.
