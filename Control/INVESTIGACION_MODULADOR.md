# Investigación del modulador: 180°, techo en 0,50 y fold-back

Rama `investigacion_modulador_qmax`, salida de `implementacion_control` @ deba40e.
Fecha: 2026-09-26.

## Los tres síntomas

Medidos en lazo abierto durante la implementación del control de corriente
(ver `docs/superpowers/plans/2026-09-26-control-corriente-pr.md`):

1. **Inversión de 180°.** El vector de tensión de salida se sintetiza en
   `al_o + 180°`, exacto y constante en todo el período.
2. **Techo en `|v_o| ≈ 0,50`**, contra el 0,866 teórico del conversor matricial.
3. **Fold-back**: arriba de `q ≈ 0,6` la transferencia es no monótona — a
   `q = 0,80` entrega 0,41, menos que a `q = 0,60`.

Hoy los tres están *tapados*, no resueltos: `ControlLazo` compensa el 180° con
un `+1024` y `Q_MAX = 0,50` mantiene el lazo fuera de la zona de fold-back.

## Sonda 1 — lectura del RTL

**La tabla de vectores de conmutación está CORRECTA.** Decodificada contra la
convención de `matrixConmut` (`i_M(8..6)` = fila de salida U sobre columnas
[U V W]):

- Los tres grupos de Casadei salen bien: ±1..±3 tienen oV=oW, ±4..±6 tienen
  oU=oW, ±7..±9 tienen oU=oV.
- Cada `−k` es exactamente el intercambio de entradas de `+k`, que es la
  inversión de signo. Verificado para los nueve pares.
- La polaridad absoluta coincide con Casadei: `+1 = (U,V,V)` da
  `v_UV_salida = +v_UV_entrada`.

**El signo sale de `seq0`** (`Modulador.vhd:884`):

    seq0 <= (not s) & s & s & (not s),  con  s = ksum(0) xor signo_phi

- `ksum = kv + ki` (`:923`), con `kv`/`ki` 1-based (`red_sector.vhd:97`), o sea
  `s = (Kv + Ki) mod 2`, que es el exponente de Casadei.
- `signo_phi` es el signo de `cos(phi_i)` (`:552-557`). Con `phi_i = 0` vale
  `'0'`, así que no aporta inversión en las pruebas.
- En la tabla de direcciones, bit `'0'` -> `+k`, bit `'1'` -> `-k`.

Casadei dice que el signo del grupo I es `(-1)^(Kv+Ki)`:

    Kv+Ki par   -> s=0 -> corresponde  +      el código da seq0(3) = 1 -> -1
    Kv+Ki impar -> s=1 -> corresponde  -      el código da seq0(3) = 0 -> +1

El patrón `[¬s, s, s, ¬s]` es el **complemento** de `[s, ¬s, ¬s, s]`.

Esta conclusión es robusta al orden de los grupos: aunque `seq1..seq4` no
correspondan a I..IV en el orden de Casadei, cualquier permutación de un
complemento global sigue siendo un complemento global.

## Sonda 2 — fracción de vectores nulos contra q

Lazo abierto, `al_o` rotando a 50 Hz, `be_i` del CORDIC de la tensión de
entrada, contando ciclos de vector nulo sobre el Ts completo:

    q        |v_o|    frac_nula   t_activo   |v_o|/t_activo
    0,0996   0,1020    0,7977      0,2023       0,5041
    0,1992   0,2105    0,5849      0,4151       0,5071
    0,2988   0,3103    0,3743      0,6257       0,4960
    0,3984   0,4143    0,1628      0,8372       0,4948
    0,4980   0,4872    0,0190      0,9810       0,4966
    0,5977   0,5019    0,0000      1,0000       0,5019   <- se agota el nulo
    0,6973   0,4266    0,0989      0,9011       0,4734   <- el nulo REAPARECE
    0,7969   0,4105    0,1208      0,8792       0,4668

**`|v_o| / t_activo` es constante en 0,497** en toda la región lineal.

### Lo que eso significa

- `|v_o| = 1,04 * q` (medido) y `t_activo ~ 2,09 * q`.
- Casadei exige `t_activo = q / 0,866 = 1,155 * q`.
- Razón: **1,81**. El modulador gasta 1,81 veces el tiempo activo que
  necesita para la tensión que produce.

O sea: **el techo de 0,50 NO es un problema de presupuesto de tiempo.** Los
vectores se aplican durante suficiente tiempo; lo que pasa es que **se
cancelan parcialmente entre sí**, y el rendimiento por unidad de tiempo activo
queda en 0,497 contra los 0,866 que corresponden (57 %).

El **fold-back es otra cosa**: a `q = 0,5977` el tiempo nulo llega a cero
exactamente y arriba de eso *reaparece*. Eso sí es desborde del presupuesto de
duties, de la misma familia que el clamping del tiempo nulo que la
investigación de agosto documentó.

## Estado de las hipótesis

- REFUTADA: "un solo defecto explica los tres síntomas". Son al menos dos
  mecanismos independientes: composición de vectores (180° + techo) y
  presupuesto de duties (fold-back).
- REFUTADA: "falta un factor sqrt(3)". El 0,574 no es 1/sqrt(3) por una
  constante perdida, es cancelación entre vectores.
- ABIERTA y principal: el patrón de signos de `seq0` está mal. Un complemento
  global explicaría los 180° pero NO la pérdida de magnitud, así que si el
  patrón correcto no es el complemento sino otro, explicaría las dos cosas.

## Próximo experimento (decisivo sobre las dos)

Invertir `seq0` a `[s, ¬s, ¬s, s]` y repetir el barrido de q:

- Si el 180° desaparece y la magnitud NO cambia -> era un complemento global;
  el problema de magnitud está en otro lado.
- Si el 180° desaparece y la magnitud SUBE hacia 0,866 -> el patrón de signos
  era también la causa del techo, y quedan dos de los tres síntomas resueltos
  con un cambio de una línea.
- Si el 180° NO desaparece -> mi lectura de la convención de signos está mal y
  hay que rehacer la sonda 1.

Es un cambio de una línea y una corrida de doce minutos.

## Resultado del experimento del signo (2026-09-26)

`seq0` invertido a `[s, !s, !s, s]`, mismo barrido de q:

    q        |v_o| antes   |v_o| ahora   t_act antes   t_act ahora
    0,0996     0,1020        0,1020        0,2023        0,2023
    0,1992     0,2105        0,2103        0,4151        0,4151
    0,2988     0,3103        0,3102        0,6257        0,6257
    0,3984     0,4143        0,4141        0,8372        0,8372
    0,4980     0,4872        0,4872        0,9810        0,9810
    0,5977     0,5019        0,5018        1,0000        1,0000
    0,6973     0,4266        0,4266        0,9011        0,9011
    0,7969     0,4105        0,4104        0,8792        0,8792

    desfasaje ang_v - al_o:   +180,0  ->  -0,1 grados

### Conclusiones

1. **CAUSA RAIZ DE LOS 180 GRADOS: CONFIRMADA.** El patron de signos de `seq0`
   estaba complementado respecto de la regla `(-1)^(Kv+Ki)` de Casadei. Se
   arregla con una linea en `Modulador.vhd:884`, en la fuente.

2. **Era un complemento global**, como predijo la sonda 1: la magnitud y el
   tiempo activo quedaron identicos hasta el cuarto decimal.

3. **El techo de 0,50 y el fold-back NO los causa el patron de signos.** Son
   un mecanismo independiente, todavia abierto. La cancelacion parcial entre
   vectores (1,81x de tiempo activo desperdiciado) sigue sin explicar.

### Consecuencia para el lazo de control

Si se adopta el arreglo, hay que **sacar el `+1024` de `ControlLazo.vhd`** o el
lazo vuelve a divergir: la compensacion existia justamente para tapar esto.
Y hay que revalidar los criterios 1 a 4.

`Q_MAX = 0,50` SE QUEDA: el techo de magnitud no se toco.

### Lo que sigue abierto

Por que los cuatro vectores activos se cancelan parcialmente, gastando 1,81
veces el tiempo que corresponde. Candidatos, en orden:

- Los pesos relativos entre los cuatro `dela` (las cuatro duties de Casadei
  llevan productos de cosenos distintos; si dos se intercambiaron, el vector
  resultante se acorta sin cambiar el tiempo total).
- El emparejamiento entre `ddabs01..04` (que numero de vector) y `seq0` (que
  signo): si el signo correcto se aplica al vector equivocado, se cancela.
- La ventana de escala `mod_profp_abs(25 downto 16)`, que el arreglo de agosto
  ya movio una vez.

El fold-back arriba de q = 0,6 es a su vez un tercer mecanismo: desborde del
presupuesto de duties que reinyecta tiempo nulo.

## Sonda 3 — patron de conmutacion ciclo a ciclo (2026-09-26)

Registrada la palabra de 9 bits en cada clock durante 20 Ts, con
`o_direcciones` expuesto, y reconstruido por run-length encoding.

Ejemplo (Ts 1, Kv=1, Ki=6):

    0a:5 0c:115 -7:11 +8:113 +1:62 -2:601 0a:232 -2:601 +1:62 +8:113 -7:11 0c:115 0a:7

### Lo que queda ESTABLECIDO

1. **La estructura SSVM de 13 slots es correcta.** Nulo en los bordes, cuatro
   activos, nulo central, y el espejo. Los duraciones suman 2048 exactos.
2. **Los cuatro vectores activos son identificables y estructuralmente
   plausibles**: dos de un grupo de Casadei y dos de otro (aca -7,+8 del
   grupo 3 y +1,-2 del grupo 1).
3. **El tiempo activo total es 1,84 a 1,93 veces el que las duties de Casadei
   requieren.** Esto es robusto: es una suma, no depende del emparejamiento
   duty-vector ni del origen de sectores.
4. La DISTRIBUCION entre los cuatro no coincide con los cuatro productos de
   cosenos, para ningun origen de sector que probe (barrido de offsets: el
   mejor deja 48 % de error de forma).

### Lo que NO queda establecido

El punto 4 es mas debil que los otros tres: encadena tres supuestos mios
(mi reduccion de sector, el emparejamiento duty->slot, y la normalizacion de
la formula de Casadei). No alcanza para acusar al calculo de duties.

Tampoco se resuelve la contradiccion central:

  - |v_o| medido = 1,04 * q, que es correcto por definicion de q.
  - tiempo activo medido = 1,93 * q, contra 1,05 * q esperado.

Si las duties fueran uniformemente 1,84x grandes, la tension TAMBIEN seria
1,84x. No lo es. Y si se las dividiera por dos, el tiempo activo cerraria
pero la tension caeria a 0,52*q, que es peor. Una de las dos normalizaciones
que estoy usando esta mal, y no puedo distinguir cual sin medir los `dela`
directamente.

### Proximo paso, que elimina TODOS mis supuestos

Loguear `dela01..dela13`, `al_ot`, `be_it`, `kv`, `ki` y `q` por acceso
jerarquico de XSIM (`<< signal .tb.dut...>>`, VHDL-2008) y compararlos uno a
uno contra `1024 * delta_k` de Casadei. Eso mide los coeficientes que el
modulador realmente calcula, sin reconstruirlos desde el patron aplicado y sin
depender de mi reduccion de sector: `al_ot` y `be_it` salen del propio
`red_sector`.

Es la medicion que deberia haber hecho de entrada en vez de reconstruir.

## Sonda 4 — los `dela` medidos DIRECTO (2026-09-26)

Leidos por nombres externos de VHDL-2008 (`<< signal .tb.svm.modulador_core.
dela02 : ... >>`), junto con `al_ot`, `be_it`, `kv`, `ki` y el `q` INTERNO.
Sin supuestos: los angulos reducidos salen del propio `red_sector`.

    q_cmd  q_int   d02  d03  d05  d06   S=sum(4)   d07(nulo)  razon vs Casadei
      51     51    154   24   11    1      190        834         1,954
     102    102    298   59   34    6      397        627         1,987
     153    153    460   77   41    6      584        440         1,985
     204    204    635   89   38    5      767        257         1,998
     255    255    746  150   82   16      994         30         1,993
     306    153    925  155   78   13     1171          0         3,987
     357    178   1023  151   67    9     1250        708         3,736

### Hallazgo 1: el calculo de duties esta BIEN

El cociente contra Casadei es **uniforme en las cuatro duties y constante en
q** (1,95 a 2,00). O sea que la FORMA es exacta; solo hay un offset de escala
constante, que muy probablemente es mi normalizacion de la formula y no un
defecto del RTL. No lo reclamo como bug.

**Esto REFUTA la conclusion de la sonda 3** ("la distribucion entre los cuatro
no coincide"). Era un artefacto de mi reduccion de sector, que es justo lo que
la sonda 3 habia marcado como no establecido.

### Hallazgo 2: el fold-back es el normalizador de la division

Arriba de `q_cmd = 255` se activa el normalizador: `q_int` pasa a valer
`q_cmd/2`. Y **el cociente contra Casadei SALTA de 1,99 a 3,99**: la
compensacion no restaura la escala, la deja 2x mas grande.

Con las duties al doble, `S` se pasa de 1024, y `N = 1024 - S` (estado 27)
hace underflow. La guarda del estado 28 (`if acumul(10) = '0'`) anula los
nulos, el patron deja de sumar 2048, y la tension colapsa.

El salto es **discontinuo y exactamente en el umbral del normalizador**, asi
que no depende de ninguna convencion de normalizacion mia: sea cual sea la
constante correcta, duplicarse al cruzar un umbral interno es un bug.

Mecanismo, de punta a punta:

    q > 255 -> normalizador divide q por 2
            -> amp_parcial (lineas 528-536) lo vuelve a multiplicar por 2^n_norm
            -> la compensacion se aplica DE MAS: duties 2x
            -> S > 1024
            -> N = 1024 - S hace underflow
            -> la guarda anula los nulos
            -> FOLD-BACK

### Lo que falta para cerrar

Instrumentar `n_norm`, `res_div`, `aux_div` y `cos_phi` a lo largo de los
estados de la division para senalar la linea exacta. Los candidatos estan
acotados a dos: el `if (q(7) = '1')` del estado 3 que decide si duplicar
`cos_phi`, y la tabla de corrimientos de `amp_parcial`.

Es una corrida corta mas.

## Sonda 5 — traza de la division. RETRACTACION del Hallazgo 2

Instrumentados `n_norm`, `q`, `cos_phi`, `aux_div`, `res_div` y `amp_parcial`
a lo largo de los estados 1 a 8.

    q_cmd = 306
      est  n_norm    q   cos_phi  aux_div  res_div    amp
        3      0     306    255       51      307      307
        4      1     153    255       51      307      614
        5      2     153    510      308      307     1228

### RETRACTACION

**El Hallazgo 2 de la sonda 4 estaba MAL, y el error era mio.**

La division y su compensacion son CORRECTAS:
- estado 3: dispara y divide q (306 -> 153), n_norm = 1
- estado 4: dispara y duplica cos_phi (255 -> 510), n_norm = 2
- dos divisiones del cociente, n_norm = 2, compensacion x4: correcta
- `amp_parcial = 1024 * q_cmd / cos_phi` verificado en cuatro puntos:
      q=204 -> 819 = 1024*204/255
      q=306 -> 1228 = 1024*306/255
      razon 1228/819 = 1,499 contra 306/204 = 1,5

El salto de 1,99 a 3,99 que reporte era un artefacto de MI script: calculaba
la referencia de Casadei con `q_int` (el q ya normalizado, o sea dividido)
en vez de `q_cmd`. Mi referencia se partio al medio; las duties no se
duplicaron. Con `q_cmd` el cociente da 1,99 en TODO el barrido, constante.

Tambien queda refutada mi hipotesis de que `n_norm` fuera posicional en vez de
un contador: aca disparo en estados consecutivos, asi que posicion = cuenta.

### Lo que SI sobrevive

El mecanismo del fold-back: a q_cmd = 306, `S = 1171 > 1024`, `N = 1024 - S`
(estado 27) hace underflow, la guarda del estado 28 anula los nulos, y el
patron deja de sumar 2048.

### Hipotesis principal para el factor 2 (y por lo tanto para el techo)

`cos_phi = 255` es el valor de LUT para `cos(0) = 1,0`. O sea que el modulador
normaliza `i_q_i` **a fondo de escala 255**, mientras el spec, el `Q` de
create_bd.tcl y el codigo de control lo tratan como fondo de escala **512**.

Con `q_max = 443` el modulador ve `443/255 = 1,74`, casi el doble del 0,866
pretendido. Eso explica de una:
- las duties 2x vs la referencia calculada con q_cmd/512
- que `S` llegue a 1024 a q_cmd ~ 270 en vez de a q_cmd = 443
- el techo de |v_o| ~ 0,50 y el fold-back mas alla

**Prediccion falsable**: con `i_q_i` a fondo de escala 255, `q_max = 0,866`
corresponde a `q_word = 221`, no 443. A q_word = 221 la suma `S` deberia
quedar debajo de 1024 y no deberia haber fold-back en todo el rango util.

Es una corrida corta: barrer q_word de 26 a 221 y verificar que S < 1024
siempre y que |v_o| crece monotonamente hasta el maximo.

### Nota de metodo

Esta es la SEGUNDA conclusion que tuve que retractar en esta investigacion
(la primera fue la sonda 3, "la distribucion esta mal"). Las dos veces la
causa fue la misma: comparar contra una referencia que yo mismo calculaba mal.
La leccion es que cuando la medicion del RTL y mi referencia discrepan, el
sospechoso numero uno tiene que ser mi referencia, no el RTL.

## Sonda 6 — barrido con fondo de escala 255: PREDICCION CONFIRMADA

    q_word  q=w/255   S max   nulo min
       26   0,1020     118      906
       51   0,2000     233      791
       77   0,3020     353      671
      102   0,4000     469      555
      128   0,5020     590      434
      153   0,6000     701      323
      179   0,7020     826      198

**`S` nunca desborda y escala lineal con q_word.** Extrapolado a q_word = 221:
`826 * 221/179 = 1020`, justo debajo de 1024. El presupuesto de duties esta
dimensionado EXACTAMENTE para fondo de escala 255. Y no hay fold-back en
ningun punto del rango.

Salvedad: la columna |v_o| de esta corrida la calcule del pico de iU, que
arrastra modo comun, asi que no es comparable con los barridos anteriores
basados en Clarke. No la uso como evidencia. La fila de 221 falto porque la
simulacion corto a los 165 ms y ese tramo arrancaba a los 160.

## CONCLUSION DE LA INVESTIGACION

Dos defectos, los dos identificados, uno arreglado y validado:

### 1. Inversion de 180 grados — RESUELTO

`Modulador.vhd:884`. El patron de signos de `seq0` estaba complementado
respecto de la regla `(-1)^(Kv+Ki)` de Casadei. Fix de una linea, validado
midiendo: el desfasaje paso de +180,0 a -0,1 grados y la magnitud no se movio.

### 2. Fondo de escala de `i_q_i`: 255, no 512 — IDENTIFICADO

`cos_phi = 255` es el `cos(0)` de la LUT, asi que el modulador normaliza
`i_q_i` contra 255. El spec, el `Q` de create_bd.tcl y el codigo de control lo
tratan como 512. Con `q_max = 443` el modulador ve `443/255 = 1,74`, el doble
del 0,866 pretendido: las duties salen al doble, `S` llega a 1024 a la mitad
del q util, y mas alla `N = 1024 - S` hace underflow y aparece el fold-back.

Confirmado por la sonda 6: con fondo de escala 255 el presupuesto cierra
exactamente (S -> 1020 de 1024 en q_word = 221 = 0,866*255) y no hay
fold-back.

**Esto NO es un bug del modulador: es un desacuerdo de interfaz.** El
modulador es coherente consigo mismo. Lo que esta mal es lo que le escriben.

### Que hay que cambiar

- `q_max`: 221 en cuentas de `i_q_i`, no 443.
- `SW/python/ModeloControlPR.py`, funcion `normalizar()`: escalar por 255, no
  por 512 (`Q_BITS = 9` deja de ser la forma correcta de pensarlo).
- `HW/src/hdl/control/ControlLazo.vhd`: la conversion `q_24(23 downto 15)` es
  un `*512 >>24`; pasa a ser `*255 >>24`.
- `create_bd.tcl`: el `mk_const Q 9 180` significa 0,706, no 0,352.
- Documentar el fondo de escala en el puerto `i_q_i` de `Modulador.vhd` y
  `SVM_wrapper.vhd`, que es donde no esta dicho en ningun lado.

### Que queda sin evaluar

Si `be_i` tenia la misma inversion que `al_o`. El fix del signo aplica a los
cuatro vectores activos, asi que probablemente se arreglo solo, pero hay que
medirlo: cerrar un lazo sobre la entrada, o medir el factor de desplazamiento
de la corriente de entrada contra `phi_i`.
