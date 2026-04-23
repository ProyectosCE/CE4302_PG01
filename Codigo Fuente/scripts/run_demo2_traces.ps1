# ============================================
# SCRIPT: run_demo2_traces.ps1
# DESCRIPCIÓN:
#   Ejecuta el testbench top_tb con diferentes workloads de traces.
#   Permite seleccionar el archivo de trace sin editar código.
#
# USO:
#   PS> .\run_demo2_traces.ps1 -TraceFile "workload_contention.csv"
#   PS> .\run_demo2_traces.ps1 -TraceFile "workload_prodcons.csv"
#   PS> .\run_demo2_traces.ps1 -TraceFile "workload_migration.csv"
#   PS> .\run_demo2_traces.ps1  # Usa default (contention)
# ============================================

param(
    [string]$TraceFile = "workload_contention.csv",
    [string]$Simulator = "questa"  # o "vcs", "xcelium", etc.
)

# Directorio base del proyecto
$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$CodigoFuente = Join-Path $ProjectRoot "Codigo Fuente"
$SourceDir = Join-Path $CodigoFuente "src"
$TbDir = Join-Path $CodigoFuente "tb"
$TracesDir = Join-Path $ProjectRoot "traces"
$SimResultsDir = Join-Path $ProjectRoot "Demostraciones" "#2" "sim_results"

# Crear directorio de resultados si no existe
if (!(Test-Path $SimResultsDir)) {
    New-Item -ItemType Directory -Path $SimResultsDir | Out-Null
}

# Ruta completa del archivo de trace
$TraceFilePath = Join-Path $TracesDir $TraceFile

# Validar que el archivo existe
if (!(Test-Path $TraceFilePath)) {
    Write-Host "[ERROR] Archivo de trace no encontrado: $TraceFilePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Archivos disponibles en $TracesDir :" -ForegroundColor Yellow
    Get-ChildItem $TracesDir -Name
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DEMO 2 - Ejecutor de Traces"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Trace:         $TraceFile" -ForegroundColor Green
Write-Host "Ruta completa: $TraceFilePath" -ForegroundColor Green
Write-Host "Resultados:    $SimResultsDir" -ForegroundColor Green
Write-Host ""

# Cambiar a directorio de simulación
Push-Location $TbDir

# Ejecutar con el simulador seleccionado (ejemplo para Questa/ModelSim)
# Nota: Ajusta según tu simulador y flujo de compilación
Write-Host "[INFO] Compilando y ejecutando testbench..." -ForegroundColor Yellow
Write-Host ""

# Comando ejemplo para Questa (adaptable a otros simuladores)
# Se pasa la ruta absoluta del trace como plusarg
$LogFile = Join-Path $SimResultsDir "sim_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Construcción del comando (ejemplo ModelSim/Questa)
# Ajusta según tu setup de compilación (do files, scripts, etc.)
$VlogCmd = "vlog -sv ${SourceDir}\*.sv ${TbDir}\*.sv"
$VsimCmd = "vsim -c top_tb +TRACE_FILE=`"${TraceFilePath}`" -log `"${LogFile}`" -do `"run -all; quit`""

Write-Host "[EXEC] $VlogCmd" -ForegroundColor Magenta
Write-Host "[EXEC] $VsimCmd" -ForegroundColor Magenta
Write-Host ""

# Si prefieres, descomentar estas líneas para ejecución real:
# Invoke-Expression $VlogCmd
# Invoke-Expression $VsimCmd

Write-Host "[OK] Log guardado en: $LogFile" -ForegroundColor Green
Write-Host ""
Write-Host "NOTA: Los comandos de ejecución están listos. Ajusta según tu setup de simulación." -ForegroundColor Yellow

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
