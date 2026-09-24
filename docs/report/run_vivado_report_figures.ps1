param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2021.1\bin\vivado.bat',
    [string]$Python = 'C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [string]$Inkscape = 'C:\Program Files\Inkscape\bin\inkscape.exe'
)

$ErrorActionPreference = 'Stop'
$reportDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $reportDir '..\..')).Path
$outputDir = Join-Path $reportDir 'figures\vivado'
$tclScript = Join-Path $repoRoot 'tcl\export_vivado_report_figures.tcl'

foreach ($tool in @($Vivado, $Python, $Inkscape)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$dcpDir = Join-Path $repoRoot 'engrenring\synth_1g\board\output\ece78ce_uart_rsp_175_resetqual4_final_v8'
$checkpointHashes = @{
    'arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp' = 'C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6'
    'arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp' = 'A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B'
}
foreach ($checkpointName in $checkpointHashes.Keys) {
    $checkpointPath = Join-Path $dcpDir $checkpointName
    if (-not (Test-Path -LiteralPath $checkpointPath)) {
        throw "Checkpoint not found: $checkpointPath"
    }
    $actualHash = (Get-FileHash -LiteralPath $checkpointPath -Algorithm SHA256).Hash
    if ($actualHash -ne $checkpointHashes[$checkpointName]) {
        throw "Checkpoint SHA-256 mismatch: $checkpointPath"
    }
}

$vivadoLog = Join-Path $outputDir 'vivado_report_figures.log'
$vivadoJournal = Join-Path $outputDir 'vivado_report_figures.jou'
$vivadoArgs = @(
    '-mode', 'batch',
    '-log', $vivadoLog,
    '-journal', $vivadoJournal,
    '-source', $tclScript,
    '-tclargs', $outputDir
)
& $Vivado @vivadoArgs
if ($LASTEXITCODE -ne 0) {
    throw "Vivado figure export failed with exit code $LASTEXITCODE"
}

$renderer = Join-Path $reportDir 'render_vivado_physical_svgs.py'
& $Python -X utf8 $renderer $outputDir
if ($LASTEXITCODE -ne 0) {
    throw "Physical SVG rendering failed with exit code $LASTEXITCODE"
}

$svgFiles = @(
    'vivado_synthesis_critical_path_schematic.svg',
    'vivado_implementation_critical_path_schematic.svg',
    'vivado_implementation_device_placement.svg',
    'vivado_critical_path_routing.svg'
)
foreach ($svgName in $svgFiles) {
    $svgPath = Join-Path $outputDir $svgName
    $pngPath = [System.IO.Path]::ChangeExtension($svgPath, '.png')
    $inkscapeArgs = @(
        '--batch-process',
        $svgPath,
        '--export-type=png',
        "--export-filename=$pngPath",
        '--export-width=3200',
        '--export-background=#ffffff',
        '--export-background-opacity=255'
    )
    $exportStarted = Get-Date
    & $Inkscape @inkscapeArgs
    $freshPng = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $pngPath) {
            $pngInfo = Get-Item -LiteralPath $pngPath
            if ($pngInfo.Length -gt 0 -and
                $pngInfo.LastWriteTime -ge $exportStarted.AddSeconds(-1)) {
                $freshPng = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $freshPng) {
        $exportStarted = Get-Date
        & $Inkscape @inkscapeArgs
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $pngPath) {
                $pngInfo = Get-Item -LiteralPath $pngPath
                if ($pngInfo.Length -gt 0 -and
                    $pngInfo.LastWriteTime -ge $exportStarted.AddSeconds(-1)) {
                    $freshPng = $true
                    break
                }
            }
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $freshPng) {
        throw "PNG preview was not generated: $pngPath"
    }
}

Write-Output "VIVADO_REPORT_FIGURES_PASS output_dir=$outputDir"
