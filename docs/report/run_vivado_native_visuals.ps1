param(
    [string]$OutputDir = "C:\project\FPGA3\docs\report\figures\vivado_native",
    [switch]$OpenGui
)

$ErrorActionPreference = "Stop"
$RepoRoot = "C:\project\FPGA3"
$Vivado = "C:\Xilinx\Vivado\2021.1\bin\vivado.bat"
$CheckpointDir = Join-Path $RepoRoot "engrenring\synth_1g\board\output\ece78ce_uart_rsp_175_resetqual4_final_v8"
$SynthDcp = Join-Path $CheckpointDir "arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp"
$RoutedDcp = Join-Path $CheckpointDir "arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp"
$ExpectedSynthSha256 = "C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6"
$ExpectedRoutedSha256 = "A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B"

if ((Get-FileHash -Algorithm SHA256 -LiteralPath $SynthDcp).Hash -ne $ExpectedSynthSha256) {
    throw "Synthesis DCP SHA-256 mismatch"
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $RoutedDcp).Hash -ne $ExpectedRoutedSha256) {
    throw "Routed DCP SHA-256 mismatch"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
& $Vivado -mode batch -nojournal -nolog `
    -source (Join-Path $RepoRoot "tcl\export_vivado_native_reports.tcl") `
    -tclargs $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "Vivado native report export failed with exit code $LASTEXITCODE"
}

if ($OpenGui) {
    Start-Process -FilePath $Vivado -WindowStyle Normal -ArgumentList @(
        "-mode", "gui",
        "-source", (Join-Path $RepoRoot "tcl\open_vivado_native_visuals.tcl"),
        "-tclargs", $OutputDir
    )
}

