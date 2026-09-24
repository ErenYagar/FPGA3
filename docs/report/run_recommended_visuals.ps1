param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2021.1\bin\vivado.bat',
    [string]$Python = 'C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)

$ErrorActionPreference = 'Stop'
$reportDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $reportDir '..\..')).Path
$outputDir = Join-Path $reportDir 'figures\recommended'
$routedDcp = Join-Path $repoRoot 'engrenring\synth_1g\board\output\ece78ce_uart_rsp_175_resetqual4_final_v8\arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp'
$expectedRoutedHash = 'A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B'

foreach ($tool in @($Vivado, $Python)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}
if ((Get-FileHash -LiteralPath $routedDcp -Algorithm SHA256).Hash -ne $expectedRoutedHash) {
    throw "Routed DCP SHA-256 mismatch: $routedDcp"
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$congestionTcl = Join-Path $repoRoot 'tcl\export_vivado_routing_density.tcl'
& $Vivado -mode batch `
    -log (Join-Path $outputDir 'vivado_routing_density.log') `
    -journal (Join-Path $outputDir 'vivado_routing_density.jou') `
    -source $congestionTcl -tclargs $outputDir
if ($LASTEXITCODE -ne 0) {
    throw "Vivado congestion report failed with exit code $LASTEXITCODE"
}

& $Python -X utf8 (Join-Path $reportDir 'generate_recommended_visuals.py')
if ($LASTEXITCODE -ne 0) {
    throw "Recommended visual generation failed with exit code $LASTEXITCODE"
}

Write-Output "RECOMMENDED_VISUALS_PASS output_dir=$outputDir"
