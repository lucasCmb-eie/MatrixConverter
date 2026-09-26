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
