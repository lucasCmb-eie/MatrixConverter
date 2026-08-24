# Lazo de corriente PR en la PL — diseño

Fecha: 2026-08-24
Estado: propuesta, pendiente de aprobación
Subproyecto: **A** (de A/B/C — ver "Descomposición")

---

## 1. Objetivo

Cerrar un lazo de control de la corriente de carga del conversor matricial, ejecutándose
enteramente en la PL (lógica programable), sobre la carga RL simulada dentro de la propia FPGA.

El ángulo de entrada `be_i` queda esclavo de los 50 Hz de la fuente, sin control. El lazo actúa
sobre los otros dos pomos del modulador: `q` (relación de transferencia de tensión) y `al_o`
(ángulo del vector de tensión de salida).

### Criterio de éxito

Un escalón en la amplitud de la referencia de corriente — 2 A → 4 A → 2 A — seguido con:

- error de régimen permanente nulo en amplitud y fase,
- transitorio sin sobrepaso excesivo,
- todo medido en XSIM y comparado contra un modelo de referencia bit-exacto.

Es el mismo ensayo de la Fig. 3 del ECCE 2021 de Mirzaeva/Seron/Goodwin, así que hay contra
qué comparar la forma del transitorio.

### Fuera de alcance

- Puente PS↔PL, AXI, block design (subproyecto B).
- Frecuencia de salida variable (subproyecto C).
- Observador de estados del docx del ingeniero.
- Control del lado de entrada, amortiguamiento del filtro, factor de potencia.
- ADC, sensores, hardware de potencia real.

---

## 2. Descomposición del trabajo

| | Subproyecto | Contenido | Estado |
|---|---|---|---|
| **A** | Lazo PR en PL | Este documento | Propuesto |
| **B** | Puente PS↔PL | PS7 + AXI-Lite desde cero, registros de consigna y coeficientes, buffer de captura, IRQ | Pendiente |
| **C** | Frecuencia variable | FTW de 32 bits en `AC_Source`, NCO de 11 bits reemplazando `PhaseSawGen`, unificación del camino de ángulo | Pendiente |

**A va primero**, y la razón no es que sea más importante: es que **B no se puede diseñar antes
que A**. El mapa de registros de B *es* la lista de coeficientes y consignas que A necesita, y esa
lista no existe hasta que A esté diseñado. Armar el mapa primero es adivinarlo.

Además A se valida entera en XSIM con el flujo que ya existe (testbench → CSV por `textio` →
`SW/matlab/LecturaDatosVivado.m`): cero hardware, cero AXI, cero síntesis.

---

## 3. Contexto: qué hay hoy

### Parámetros temporales

`estado` es un contador libre de 11 bits (`HW/src/hdl/Modulador.vhd:197-199`), así que el período
de conmutación son 2048 ciclos de reloj. Con los 10 MHz del testbench
(`HW/src/tb/tb_SVM_Wrapper.vhd:16`):

```
Ts   = 2048 / 10 MHz = 204,8 µs
f_sw = 4882,81 Hz
```

Ancho de banda razonable del lazo: 200–300 Hz, o sea 4–6× la fundamental de 50 Hz.

Presupuesto del secuenciador: **2048 ciclos de reloj por Ts**. Sobra ampliamente (ver §7).

### Bloques reutilizables

| Bloque | Archivo | Rol en el lazo |
|---|---|---|
| `TransformadaClark` | `HW/src/hdl/TransformadaClark.vhd` | abc → αβ, para `i_o` y `v_i`. Q8.24 (`sfixed`) |
| `CORDIC_atan2` | `HW/src/hdl/CORDIC_atan2.vhd` | Vectoring: entra Q8.24, sale ángulo de 11 bits. **Hay que agregarle salida de magnitud** |
| `RL_fase` | `HW/src/hdl/RL_fase.vhd` | Planta. IIR de primer orden con coeficientes `i_c_a0/a1/b1` en runtime |
| `SVM_wrapper` | `HW/src/hdl/wrappers/SVM_wrapper.vhd` | Modulador + matriz. Consume `i_q_i`, `i_al_o`, `i_be_i`, `i_phi_i` |

**Nota:** no espejar nada de esto en `HW/src/ip/SinAXI/` — esa copia está vieja y no se usa.

---

## 4. Arquitectura del lazo

```
AC_Source (50 Hz) ──┬──→ T_Clark_Vi ──→ |v_i|  (constante conocida → coeficiente 1/|v_i|)
                    └──→ camino de ángulo ──→ be_i   (esclavo, sin control)

  Generador de referencia (NCO a ω_o, amplitud A)
              │
              ↓  i_ref(αβ)
             (+)
              │ ─────────────────────────────┐
              ↓                              │
            e(αβ)                            │
              │                              │
              ↓                              │
     ┌──────────────────┐                    │
     │  Kp + resonador  │  ×2 (α y β)        │
     └──────────────────┘                    │
              │                              │
              ↓  v_o*(αβ)                    │
     ┌──────────────────┐                    │
     │ CORDIC vectoring │                    │
     └────┬────────┬────┘                    │
     |v_o*|        θ_o                       │
          │         └──────────→ i_al_o      │
          ↓                                  │
    × (1/(K·|v_i|))                          │
          ↓                                  │
   sat [0 , 0,866]  ──────────→ i_q_i        │
          │                                  │
          ↓                                  │
    ┌─────────────────────────────┐          │
    │ Modulador → matrixConmut    │          │
    └─────────────┬───────────────┘          │
                  ↓ v_o conmutada            │
              RL_fase ×3                     │
                  ↓ i_o(abc)                 │
             T_Clark_Io ──→ i_o(αβ) ─────────┘
                            (muestreada 1×/Ts)
```

Puntos a destacar:

- **No hay Park ni Park inversa.** El lazo vive entero en αβ, que es donde `TransformadaClark`
  ya entrega las señales, y el CORDIC hace el paso a polares que el modulador necesita.
- **El CORDIC entrega las dos salidas de una pasada.** En modo vectoring, al converger, el
  registro `x` contiene `K·√(x²+y²)` y el registro `z` el ángulo. Hoy solo se expone el ángulo.
- **`q` no necesita divisor.** `|v_i|` es constante y conocida, así que `1/|v_i|` es un
  coeficiente y la normalización es una multiplicación.

---

## 5. El controlador PR

### Forma continua

```
G(s) = Kp + Ki · (2·ω_c·s) / (s² + 2·ω_c·s + ω_o²)
```

El término resonante tiene ganancia muy grande (finita, por el amortiguamiento `ω_c`)
exactamente en `ω_o`. Eso es el principio del modelo interno: para seguir una referencia
senoidal con error cero, el lazo tiene que contener un modelo del generador de esa senoidal.

### Forma discreta: rotación exacta

**Esta es la decisión de diseño más importante del documento.** No discretizar con Euler.

Se implementa el resonador como un oscilador en forma rotante, discretizado exactamente:

```
┌   ┐        ┌                  ┐ ┌   ┐        ┌   ┐
│x₁│      = ρ│ cos θ    −sin θ  │ │x₁│      + │b₁│ · e[n]
│x₂│[n+1]    │ sin θ     cos θ  │ │x₂│[n]     │b₂│
└   ┘        └                  ┘ └   ┘        └   ┘

  θ = ω_o · Ts          ρ = exp(−ω_c · Ts)
  y[n] = x₁[n]
```

Tres razones, todas concretas:

1. **Rango dinámico constante.** El vector de estado rota con módulo casi constante, así que
   `x₁` y `x₂` tienen siempre la misma escala. En punto fijo eso significa que se puede elegir
   un formato Q y no volver a pensarlo. Con formas canónicas (directa I/II) los estados internos
   toman valores muy distintos entre sí y ahí es donde aparecen los desbordes.
2. **Los polos caen donde deben, por construcción.** Euler hacia adelante sobre un sistema
   rotante empuja los polos fuera del círculo unidad (`|1 + jω_oTs| > 1`) y desestabiliza; Euler
   hacia atrás los mete demasiado adentro y corre la frecuencia de resonancia. La rotación exacta
   no tiene ese error.
3. **`ω_o` entra por dos coeficientes y nada más.** `cos θ` y `sin θ`. Cuando llegue el
   subproyecto C, cambiar la frecuencia de salida es escribir dos registros — no re-sintetizar.

### Coeficientes para Ts = 204,8 µs y f_o = 50 Hz

| Símbolo | Expresión | Valor |
|---|---|---|
| `θ` | `2π·50·Ts` | 0,064340 rad |
| `cos θ` | | 0,997931 |
| `sin θ` | | 0,064295 |
| `ρ` | `exp(−ω_c·Ts)`, con `ω_c` = 5 rad/s | 0,998977 |
| `ρ·cos θ` | | 0,996910 |
| `ρ·sin θ` | | 0,064229 |

`ω_c` = 5 rad/s da un pico resonante alto pero finito, sobre una banda de ±0,8 Hz alrededor de
50 Hz. Es un punto de partida; se ajusta en simulación.

**Vector de entrada.** El error entra por un solo estado: `b = [1, 0]ᵀ`. Ese `1` fija la ganancia
global del término resonante, así que no hace falta un coeficiente aparte — la escala la lleva
`Ki`. Queda un multiplicador menos y un coeficiente menos que sintonizar.

### Ley de control

Dos instancias idénticas, una por eje:

```
v_o*_α[n] = Kp · e_α[n] + Ki · x₁_α[n]
v_o*_β[n] = Kp · e_β[n] + Ki · x₁_β[n]
```

### Sintonía inicial

De la regla IMC de Harnefors & Nee (1998), para una planta `1/(Ls+R)` y ancho de banda
deseado `α_bw` en rad/s:

```
Kp = α_bw · L
Ki = α_bw · R
```

Con `α_bw` = 2π·250 ≈ 1571 rad/s. Los valores numéricos salen de los `R` y `L` que se
escriban en `RL_fase`, así que se calculan una vez fijada la carga de ensayo. `Ki` se
termina de ajustar en simulación: la regla IMC es exacta para el PI y solo aproximada
para el término resonante.

---

## 6. Estrategia de puesta en marcha: andamio deadbeat primero

Antes de conectar el PR, se cierra el lazo con una ley deadbeat:

```
v_o*(k) = R · i_ref(k) + L · (i_ref(k) − i_o(k)) / Ts
```

Tres multiplicaciones, sin estado, sin windup.

**No es el control definitivo.** La planta es un modelo RL cuyos parámetros se escriben a mano,
así que un deadbeat con `R` y `L` exactos sigue la referencia por construcción — demostraría que
el cableado anda, no que el control anda.

Su valor es de diagnóstico. El riesgo real de este subproyecto no está en la ley de control, está
en el datapath: escalas de punto fijo, instante de muestreo, la ganancia del CORDIC, la
normalización a `q`. Con deadbeat, si el lazo no cierra, **el bug está en el datapath sí o sí**.
Después se reemplaza la ley por el PR y cualquier problema nuevo es del resonador. Separa dos
clases de bugs que de otro modo se mezclan y se tapan entre sí.

---

## 7. Datapath y presupuesto

El lazo corre **una vez por Ts**, no a la frecuencia de reloj. Con 2048 ciclos disponibles no
hay que construir un datapath paralelo: alcanza un secuenciador con **un solo multiplicador**
time-multiplexado, en el mismo estilo que `Modulador.vhd` ya usa para su división restauradora.

| Operación | Multiplicaciones |
|---|---|
| Resonador α (rotación + entrada) | 6 |
| Resonador β | 6 |
| `Kp·e` en ambos ejes | 2 |
| `Ki·x₁` en ambos ejes | 2 |
| Normalización `1/(K·|v_i|)` | 1 |
| **Total** | **17** |

Más el CORDIC, que es solo desplazamientos y sumas: 20 iteraciones ≈ 24 ciclos.

Con ~4 ciclos por multiplicación: **≈ 92 ciclos de 2048**, un 4,5 % del período. Un DSP48 para
todo el lazo, sobre los 66 que tiene el `xc7z007s`.

### Formatos de punto fijo

Se mantiene **Q8.24 (`sfixed(7 downto -24)`)** en todo el camino de señal, que es lo que ya usan
`TransformadaClark`, `RL_fase` y `CORDIC_atan2`. Coherencia sobre optimización: este proyecto ya
tuvo bugs de escala y no conviene introducir formatos nuevos sin necesidad.

Los coeficientes del resonador (`ρcos θ`, `ρsin θ`) están todos en (−1, 1), así que entran
holgados en Q8.24.

---

## 8. Modificación al CORDIC

`CORDIC_atan2.vhd` hoy expone solo `angle_out` (línea 20). Hay que agregar:

```vhdl
mag_out : out signed(31 downto 0);   -- Q8.24, con ganancia K sin compensar
```

Al terminar las iteraciones, `x_reg` contiene `K·√(x²+y²)` con:

```
K = Π √(1 + 2⁻²ⁱ)  para i = 0..19  =  1,64676026
1/K = 0,60725294
```

**La compensación es gratis:** se pliega `1/K` dentro del coeficiente de normalización, o sea
se usa `1/(K·|v_i|)` en vez de `1/|v_i|`. Cero hardware adicional.

**A verificar:** el estado `PRE_PROCESS` del CORDIC hace la pre-rotación de cuadrante. Mientras
sea una rotación de ±90° (intercambio de ejes con cambio de signo) el módulo no se altera y
`mag_out` es válida en los cuatro cuadrantes. Hay que confirmarlo leyendo ese estado antes de
confiar en la salida.

---

## 9. Muestreo de la corriente

`RL_fase` se alimenta de la salida **conmutada** de `matrixConmut`, así que `i_o` trae rizado de
conmutación. Se muestrea una vez por Ts, en un instante fijo del período.

Como la modulación es simétrica (SSVM: 25 % en los bordes, 50 % en el centro), muestrear
sincronizado con `o_inicio_ciclo` toma la señal en un punto donde el valor instantáneo es
prácticamente el promedio del período. Es el muestreo regular clásico y no necesita promediador.

**Consecuencia que hay que modelar, no ignorar:** el lazo tiene un retardo de un período entre
que muestrea `i_o` y que el nuevo `q`/`al_o` tiene efecto. Ese retardo tiene que estar en el
modelo de referencia de Python, o las comparaciones no van a cerrar.

---

## 10. Saturación y anti-windup

`q` satura en 0,866 — el límite intrínseco del conversor matricial trifásico. En este convertidor
se pega contra ese techo seguido, no ocasionalmente.

Estrategia: **integración condicional.** Cuando la salida está saturada y el error empujaría más
adentro de la saturación, se congela la actualización del estado del resonador (`x₁`, `x₂`
mantienen su valor). Cuando la salida vuelve al rango lineal, se reanuda.

Con un resonador esto es más delicado que con un integrador simple, porque congelar detiene
también la rotación y el estado se desfasa respecto de la referencia. Para transitorios cortos
es aceptable; si en simulación aparece un problema, la alternativa es back-calculation
(realimentar `(v_sat − v_o*)` al estado con una ganancia).

---

## 11. Riesgos conocidos

**Zona muerta de 8 LSB del PWM.** Está medida y documentada en `Modulador.vhd:212-216`: los
tiempos de vector más cortos que 8 cuentas se saltean, porque los estados de búsqueda de la
máquina se consumen del countdown del propio vector. Eso es una **no linealidad real cerca de
`q` chico**, y el lazo la va a ver como una zona muerta. Si el escalón de corriente baja lo
suficiente como para llevar `q` a esa región, el error de régimen no va a ser cero. Hay que
elegir las amplitudes del ensayo teniéndolo en cuenta, y documentar el `q` mínimo utilizable.

**Resolución de `q`.** 9 bits sobre el rango útil dan un escalón de 1/512 ≈ 0,00195. Es el piso
del error de régimen alcanzable.

**Escalas de punto fijo.** El historial del proyecto (tres bugs, uno de ellos de escala) dice que
acá es donde se pierde el tiempo. Mitigación en §12.

**Ganancia del CORDIC.** Si se olvida `1/K`, todo el lazo queda con un 64,7 % de exceso de
ganancia. Es un error silencioso: el lazo va a andar, mal sintonizado.

---

## 12. Plan de verificación

1. **Modelo de referencia bit-exacto en Python** (`SW/python/`): mismos anchos, mismos
   truncamientos, mismo retardo de un ciclo. Se escribe **antes** que el VHDL.
2. **Testbench nuevo** `HW/src/tb/tb_lazo_corriente.vhd`, que escribe un CSV por `textio` con
   `i_ref(αβ)`, `i_o(αβ)`, `e(αβ)`, `v_o*(αβ)`, `q`, `al_o` — una fila por Ts.
3. **Comparación muestra a muestra** Python vs XSIM. Es el criterio de "el datapath está bien".
4. **Ensayo de escalón** 2 A → 4 A → 2 A: tiempo de establecimiento y error de régimen.
5. **Gráficos** con un script en `SW/matlab/`. Recordar: MATLAB anterior a R2018b (sin `yline`/
   `xline`) y sin acentos en los archivos.

Las rutas de salida de los CSV en los testbenches de este proyecto están hardcodeadas como
absolutas; seguir esa convención o cambiarla en todos a la vez.

---

## 13. Apéndice: recuperar Ts y ω_o del docx del ingeniero

Queda pendiente preguntarle al ingeniero con qué `Ts` y `ω_o` discretizó las matrices de
`Control/Datos del control de salida_V1r01.docx`. Pero se pueden inferir del propio `Ao`.

`Ao` contiene dos veces el bloque:

```
[ 0,9987   −0,0502 ]
[ 0,0502    0,9987 ]
```

Eso es exactamente la forma rotante de §5 — el modelo interno del oscilador dentro del
observador. De ahí:

```
θ = atan2(0,0502 , 0,9987) = 0,050223 rad = ω_o · Ts
módulo = 0,999961  →  ρ ≈ 1, oscilador sin amortiguar
```

Solo se recupera el **producto** `ω_o·Ts`. Pero si el lazo corre a 5 kHz (`Ts` = 200 µs, o sea
la mitad de los 10 kHz de conmutación que declara el paper), entonces:

```
ω_o = 0,050223 / 200 µs = 251,1 rad/s = 39,97 Hz ≈ 40 Hz
```

251,3 rad/s es exactamente 2π·40. El ajuste es muy bueno, así que la hipótesis
**`Ts` = 200 µs con `f_o` = 40 Hz** es fuerte. Hay que confirmarla, no darla por hecha.

Detalle lindo: 200 µs es casi idéntico a los 204,8 µs de este diseño. El lazo va a correr
prácticamente a la misma tasa que el del ingeniero.

---

## 14. Archivos

**Nuevos:**

- `HW/src/hdl/control/ResonadorSOGI.vhd` — un canal del resonador en forma rotante
- `HW/src/hdl/control/LazoCorriente.vhd` — secuenciador, dos resonadores, Kp/Ki, normalización, saturación
- `HW/src/hdl/control/RefGen.vhd` — generador de `i_ref(αβ)`
- `HW/src/tb/tb_lazo_corriente.vhd`
- `SW/python/modelo_lazo_corriente.py` — referencia bit-exacta
- `SW/matlab/GraficarLazoCorriente.m`

**Modificados:**

- `HW/src/hdl/CORDIC_atan2.vhd` — agregar `mag_out`
- `build.tcl` — agregar las fuentes nuevas
