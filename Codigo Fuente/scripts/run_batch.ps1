param(
    [int[]]$Sizes = @(20, 100, 1000, 10000, 100000),
    [string[]]$Protocols = @("MSI", "FIREFLY"),
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'

# ============================================
# Paths
# ============================================

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$tbDir      = Join-Path $root '..\tb'
$srcDir     = Join-Path $root '..\src'
$tracesDir  = Join-Path $root '..\traces\traces_gen'
$simDir     = Join-Path $root '..\scripts'
$resultsDir = Join-Path $root '..\sim_results'

$compileDoPath = Join-Path $root 'compile_batch.do'

$tbName = "workload_csv_tb"
$numCores = 4

# ============================================
# Metadata del batch
# ============================================

$batchId = Get-Date -Format 'yyyyMMdd_HHmmss'
$batchTimestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " EJECUCION BATCH DE SIMULACIONES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Batch ID       : $batchId"
Write-Host "Timestamp      : $batchTimestamp"
Write-Host "Testbench      : $tbName"
Write-Host "Num cores      : $numCores"
Write-Host "Resultados     : $resultsDir"
Write-Host ""

# ============================================
# Crear carpetas de resultados
# ============================================

$resultsSubdirs = @(
    $resultsDir,
    (Join-Path $resultsDir 'logs'),
    (Join-Path $resultsDir 'csv_summary'),
    (Join-Path $resultsDir 'csv_per_cache'),
    (Join-Path $resultsDir 'csv_bus_events'),
    (Join-Path $resultsDir 'csv_state_transitions'),
    (Join-Path $resultsDir 'csv_timeline'),
    (Join-Path $resultsDir 'csv_memory'),
    (Join-Path $resultsDir 'batch_reports')
)

foreach ($dir in $resultsSubdirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ============================================
# Workloads esperados
# ============================================

$Workloads = @(
    [pscustomobject]@{
        Model  = "CONTENTION"
        Prefix = "workload_contention"
    },
    [pscustomobject]@{
        Model  = "MIGRATION"
        Prefix = "workload_migration"
    },
    [pscustomobject]@{
        Model  = "PROD-CONS"
        Prefix = "workload_prod-cons"
    }
)

$totalExpectedRuns = $Protocols.Count * $Workloads.Count * $Sizes.Count

Write-Host "Protocolos:" -ForegroundColor Cyan
$Protocols | ForEach-Object { Write-Host "  - $_" }

Write-Host "Workloads:" -ForegroundColor Cyan
$Workloads | ForEach-Object { Write-Host "  - $($_.Model) => $($_.Prefix)_N" }

Write-Host "Tamanos:" -ForegroundColor Cyan
$Sizes | ForEach-Object { Write-Host "  - $_" }

Write-Host ""
Write-Host "Total de ejecuciones esperadas: $totalExpectedRuns" -ForegroundColor Yellow
Write-Host ""

# ============================================
# CSV de resumen del batch
# ============================================

$batchSummaryPath = Join-Path $resultsDir "batch_reports\${batchId}_batch_summary.csv"

"batch_id,run_index,run_id,timestamp,protocol,workload_model,workload_base,size,status,exit_code,log_file,trace_base" |
    Set-Content -Encoding ASCII $batchSummaryPath

function Add-BatchSummaryLine {
    param(
        [string]$BatchId,
        [int]$RunIndex,
        [string]$RunId,
        [string]$Timestamp,
        [string]$Protocol,
        [string]$WorkloadModel,
        [string]$WorkloadBase,
        [int]$Size,
        [string]$Status,
        [int]$ExitCode,
        [string]$LogFile,
        [string]$TraceBase
    )

    $line = "$BatchId,$RunIndex,$RunId,$Timestamp,$Protocol,$WorkloadModel,$WorkloadBase,$Size,$Status,$ExitCode,$LogFile,$TraceBase"
    Add-Content -Encoding ASCII -Path $batchSummaryPath -Value $line
}

# ============================================
# Validar existencia de traces
# ============================================

function Test-TraceGroup {
    param(
        [string]$WorkloadBase,
        [int]$NumCores,
        [string]$TracesDir
    )

    $missing = @()

    for ($pe = 0; $pe -lt $NumCores; $pe++) {
        $tracePath = Join-Path $TracesDir "${WorkloadBase}_PE${pe}.csv"

        if (-not (Test-Path $tracePath)) {
            $missing += $tracePath
        }
    }

    return $missing
}

Write-Host "Validando traces requeridos..." -ForegroundColor Cyan

$missingAll = @()

foreach ($workload in $Workloads) {
    foreach ($size in $Sizes) {
        $workloadBase = "$($workload.Prefix)_$size"
        $missing = Test-TraceGroup -WorkloadBase $workloadBase -NumCores $numCores -TracesDir $tracesDir

        if ($missing.Count -gt 0) {
            $missingAll += $missing
        }
    }
}

if ($missingAll.Count -gt 0) {
    Write-Host ""
    Write-Host "Faltan archivos de trace. No se puede garantizar las 36 ejecuciones." -ForegroundColor Red
    Write-Host "Archivos faltantes:" -ForegroundColor Red

    foreach ($m in $missingAll) {
        Write-Host "  $m" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Abortando batch." -ForegroundColor Red
    exit 1
}

Write-Host "Todos los traces requeridos existen." -ForegroundColor Green
Write-Host ""

# ============================================
# Compilar una sola vez
# ============================================

Write-Host "Compilando testbench y paquetes..." -ForegroundColor Cyan

$compileDoLines = @(
    'vlib work',
    'vlog "../src/types_pkg.sv"',
    'vlog "../src/model_pkg.sv"',
    'vlog "../tb/*.sv"',
    'quit'
)

$compileDoLines | Set-Content -Encoding ASCII $compileDoPath

Push-Location $simDir

try {
    & vsim -c -do "..\scripts\compile_batch.do"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error durante compilacion. Codigo: $LASTEXITCODE" -ForegroundColor Red
        Pop-Location
        exit $LASTEXITCODE
    }
}
catch {
    Write-Host "Error ejecutando compilacion: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

Remove-Item $compileDoPath -ErrorAction SilentlyContinue

Write-Host "Compilacion finalizada correctamente." -ForegroundColor Green
Write-Host ""

# ============================================
# Ejecutar las 36 simulaciones
# ============================================

$runIndex = 0
$successCount = 0
$failCount = 0

foreach ($protocol in $Protocols) {
    foreach ($workload in $Workloads) {
        foreach ($size in $Sizes) {

            $runIndex++

            $runId = "${batchId}_r$('{0:D2}' -f $runIndex)"
            $runTimestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff'

            $workloadModel = $workload.Model
            $workloadBase  = "$($workload.Prefix)_$size"

            # Rutas relativas desde scripts/
            $traceRel = "../traces/traces_gen/$workloadBase"
            $logRel   = "../sim_results/logs/${runId}_${protocol}_${workloadBase}.log"

            Write-Host "----------------------------------------" -ForegroundColor DarkGray
            Write-Host "Run $runIndex / $totalExpectedRuns" -ForegroundColor Yellow
            Write-Host "Protocol : $protocol"
            Write-Host "Workload : $workloadModel"
            Write-Host "Size     : $size"
            Write-Host "Run ID   : $runId"
            Write-Host "Log      : $logRel"
            Write-Host "----------------------------------------" -ForegroundColor DarkGray

            $vsimArgs = @(
                "-c",
                "-l", $logRel,
                $tbName,
                "+TRACE_FILE=$traceRel",
                "+PROTOCOL=$protocol",
                "+WORKLOAD=$workloadBase",
                "+RUN_ID=$runId",
                "+RUN_TIMESTAMP=$runTimestamp",
                "+RESULTS_DIR=../sim_results",
                "-do", "run -all; quit"
            )

            Push-Location $simDir

            $status = "PASS"
            $exitCode = 0

            try {
                & vsim @vsimArgs
                $exitCode = $LASTEXITCODE

                if ($exitCode -ne 0) {
                    $status = "FAIL"
                }
            }
            catch {
                $status = "FAIL"
                $exitCode = 1
                Write-Host "Error ejecutando simulacion: $_" -ForegroundColor Red
            }

            Pop-Location

            if ($status -eq "PASS") {
                $successCount++
                Write-Host "Resultado: PASS" -ForegroundColor Green
            }
            else {
                $failCount++
                Write-Host "Resultado: FAIL" -ForegroundColor Red
            }

            Add-BatchSummaryLine `
                -BatchId $batchId `
                -RunIndex $runIndex `
                -RunId $runId `
                -Timestamp $runTimestamp `
                -Protocol $protocol `
                -WorkloadModel $workloadModel `
                -WorkloadBase $workloadBase `
                -Size $size `
                -Status $status `
                -ExitCode $exitCode `
                -LogFile $logRel `
                -TraceBase $traceRel

            if (($status -eq "FAIL") -and (-not $ContinueOnError)) {
                Write-Host ""
                Write-Host "La ejecucion fallo y ContinueOnError no esta activo. Abortando batch." -ForegroundColor Red
                Write-Host "Resumen parcial: $batchSummaryPath" -ForegroundColor Yellow
                exit $exitCode
            }

            Write-Host ""
        }
    }
}

# ============================================
# Resumen final
# ============================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " BATCH FINALIZADO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total ejecuciones : $totalExpectedRuns"
Write-Host "Exitosas          : $successCount" -ForegroundColor Green
Write-Host "Fallidas          : $failCount" -ForegroundColor Red
Write-Host "Resumen batch     : $batchSummaryPath"
Write-Host "Resultados        : $resultsDir"
Write-Host ""