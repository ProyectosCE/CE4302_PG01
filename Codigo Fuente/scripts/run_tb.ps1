$ErrorActionPreference = 'Stop'

# Paths
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tbDir = Join-Path $root '..\tb'
$srcDir = Join-Path $root '..\src'
$simDir = Join-Path $root '..\sim'
$runDoPath = Join-Path $root 'run_tb.do'

# List all .sv files in tb/ and extract module names
$tbFiles = Get-ChildItem -Path $tbDir -Filter '*.sv' | Select-Object -ExpandProperty Name
if (-not $tbFiles) {
    Write-Host 'No testbench files (.sv) found in tb/ folder.' -ForegroundColor Red
    exit 1
}

# Try to extract module names from each .sv file (simple regex for 'module <name>')
$tbModules = @()
foreach ($file in $tbFiles) {
    $lines = Get-Content (Join-Path $tbDir $file)
    foreach ($line in $lines) {
        if ($line -match '^\s*module\s+([a-zA-Z_][a-zA-Z0-9_]*)') {
            $tbModules += $Matches[1]
            break
        }
    }
}

if (-not $tbModules) {
    Write-Host 'No modules found in tb/ folder.' -ForegroundColor Red
    exit 1
}

# Show list and ask user to select
Write-Host 'Testbenches disponibles:' -ForegroundColor Cyan
for ($i = 0; $i -lt $tbModules.Count; $i++) {
    Write-Host ("[$i] $($tbModules[$i]) ($($tbFiles[$i]))")
}


# Leer y validar la selección del usuario de forma robusta
$selected = Read-Host 'Ingrese el numero del testbench que desea simular'
[int]$selectedInt = -1
if (-not [int]::TryParse($selected, [ref]$selectedInt) -or $selectedInt -lt 0 -or $selectedInt -ge $tbModules.Count) {
    Write-Host 'Seleccion invalida. Abortando.' -ForegroundColor Red
    exit 1
}
$tbName = $tbModules[$selectedInt]




# Usar rutas relativas y comillas dobles en el archivo .do, asegurando que cada línea sea una sola línea

# Compilar primero los packages, luego el resto de los archivos
$doLines = @(
    'vlib work',
    'vlog "../src/types_pkg.sv"',
    'vlog "../src/model_pkg.sv"',
    'vlog "../tb/*.sv"',
    ('vsim ' + $tbName),
    'run -all',
    'quit'
)
$doLines | Set-Content -Encoding ASCII $runDoPath

Write-Host "Archivo temporal run_tb.do generado para $tbName." -ForegroundColor Green


# Ejecutar vsim desde sim/ en modo consola (-c)
$vsimCmd = "vsim -c -do ..\scripts\run_tb.do"
Write-Host "Ejecutando: $vsimCmd" -ForegroundColor Yellow
Push-Location $simDir
try {
    iex $vsimCmd
} catch {
    Write-Host "Error al ejecutar vsim: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Eliminar siempre el archivo temporal run_tb.do al finalizar
Remove-Item $runDoPath -ErrorAction SilentlyContinue
Write-Host 'Archivo run_tb.do eliminado.' -ForegroundColor Green
