# Programa la PL, baja el .elf y CAPTURA la UART a un archivo, en un comando.
#
#   powershell -ExecutionPolicy Bypass -File SW\ps\programar_y_capturar.ps1
#   powershell ... -File ... -Com COM12 -Salida C:\ruta\captura.csv
#
# POR QUE EXISTE
#
# El ciclo manual tiene tres trampas que ya nos mordieron:
#
#   1. El puerto COM es EXCLUSIVO. Si PuTTY o el Serial Terminal de Vitis lo
#      tienen abierto, el otro no ve nada y parece que el programa no habla.
#   2. El programa vuelca y TERMINA en menos de un segundo. Hay que estar
#      capturando ANTES de que corra; engancharse despues pierde todo.
#   3. launch.json de Vitis apuntaba a una COPIA LOCAL del bitstream que se
#      quedo vieja. Mismo tamaño que el nuevo -- los bitstreams del mismo chip
#      pesan todos igual -- asi que solo el hash lo delataba. Habria programado
#      la PL vieja y el sintoma seria identico al bug que estabamos cazando.
#
# Este script abre el puerto PRIMERO, despues programa, y toma el bitstream de
# la plataforma (no de una copia), asi que las tres desaparecen.
#
# OJO: ps7_init va ANTES del bitstream. loadhw -regs NO levanta el controlador
# de DDR, y el .elf se baja a 0x100000 que es DDR: sin esto falla con
# "Cannot access DDR: the controller is held in reset".

param(
    [string]$Com     = "COM12",
    [int]   $Baud    = 115200,
    [string]$Salida  = "",
    [int]   $Timeout = 180,
    # Programa y arranca, pero NO abre el COM. Para programas que no terminan
    # nunca (visor_corriente.c): ahi no hay carrera que ganar y el puerto lo
    # tiene que tomar el visor de Python.
    [switch]$SoloProgramar
)

$ErrorActionPreference = "Stop"
$RAIZ = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$W    = Join-Path $RAIZ "SW\vitis\test_ControlSVM"
$XSCT = "F:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat"

if ($Salida -eq "") {
    $Salida = Join-Path $RAIZ ("captura_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
}

# ---- el script de xsct, generado aca para que las rutas no se dupliquen ----
$tcl = Join-Path $env:TEMP "programar_y_capturar.tcl"
@"
connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 3000
targets -set -nocase -filter {name =~ "*A9*#0"}
source $($W -replace '\\','/')/platform/export/platform/hw/ps7_init.tcl
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "xc7z007s"}
fpga -file $($W -replace '\\','/')/platform/export/platform/hw/sdt/design_testPSPLComm_wrapper.bit
targets -set -nocase -filter {name =~ "*A9*#0"}
rst -processor
dow $($W -replace '\\','/')/Validador/build/Validador.elf
con
"@ | Set-Content $tcl -Encoding ascii

if ($SoloProgramar) {
    Write-Host "programando la PL y bajando el .elf (sin abrir el puerto)..."
    $p = Start-Process -FilePath $XSCT -ArgumentList "`"$tcl`"" -NoNewWindow -PassThru -Wait
    if ($p.ExitCode -ne 0) {
        Write-Host "xsct salio con codigo $($p.ExitCode)"
        exit 1
    }
    Write-Host "OK, programa corriendo. Ahora:"
    Write-Host "  python SW/python/VisorCorriente.py $Com"
    exit 0
}

# ---- 1) el puerto PRIMERO ----
Write-Host "abriendo $Com a $Baud..."
$sp = New-Object System.IO.Ports.SerialPort $Com, $Baud, "None", 8, "One"
$sp.ReadTimeout = 500
# El buffer por defecto son 4096 bytes y el volcado son ~38 KB. Si se llena, el
# driver DESCARTA lo que sigue en silencio: la captura sale truncada sin ningun
# aviso. Un mega de colchon cuesta nada y cubre varias corridas.
$sp.ReadBufferSize = 1048576
try {
    $sp.Open()
} catch {
    Write-Host "NO se pudo abrir ${Com}: $($_.Exception.Message)"
    Write-Host "Hay un PuTTY o el Serial Terminal de Vitis abierto? El puerto es exclusivo."
    exit 1
}
$sp.DiscardInBuffer()

# ---- 2) programar y arrancar, SIN esperar a que xsct cierre ----
#
# Nada de -Wait. El programa arranca con el `con` del tcl y vuelca las 256 fotos
# en ~3,3 s a 115200 baudios, mientras xsct todavia esta cerrandose. Esperarlo
# significa no leer durante ese rato: la primera version hacia eso y la captura
# salia truncada en la linea 51, con el buffer del driver desbordado.
Write-Host "programando la PL y bajando el .elf..."
$p = Start-Process -FilePath $XSCT -ArgumentList "`"$tcl`"" -NoNewWindow -PassThru

# ---- 3) capturar hasta el '# fin' que imprime el programa ----
Write-Host "capturando (corta con '# fin' o a los $Timeout s)..."
$sb    = New-Object System.Text.StringBuilder
$hasta = (Get-Date).AddSeconds($Timeout)
$lineas = 0
$completo = $false
while ((Get-Date) -lt $hasta) {
    try {
        $l = $sp.ReadLine()
        [void]$sb.AppendLine($l.TrimEnd())
        $lineas++
        if ($l -match '^# fin') { $completo = $true; break }
    } catch [System.TimeoutException] { }
}
$sp.Close()
if (-not $p.HasExited) { $p.WaitForExit(30000) | Out-Null }

$sb.ToString() | Set-Content $Salida -Encoding ascii
Write-Host "$lineas lineas -> $Salida"
if (-not $completo) {
    Write-Host "ATENCION: no llego el '# fin'. La captura puede estar incompleta."
    exit 2
}
Write-Host "OK, captura completa. Analizar con:"
Write-Host "  python SW/python/DecodificarSeq0.py `"$Salida`""
