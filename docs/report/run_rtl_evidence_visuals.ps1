param(
    [string]$OutputDir = "C:\project\FPGA3\docs\report\figures\rtl_evidence"
)

$ErrorActionPreference = "Stop"
$RepoRoot = "C:\project\FPGA3"
$Vivado = "C:\Xilinx\Vivado\2021.1\bin\vivado.bat"
$Inkscape = "C:\Program Files\Inkscape\bin\inkscape.com"
$SynthDcp = Join-Path $RepoRoot "engrenring\synth_1g\board\output\ece78ce_uart_rsp_175_resetqual4_final_v8\arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp"
$ExpectedSynthSha256 = "C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6"

foreach ($required in @($Vivado, $Inkscape, $SynthDcp)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required file: $required"
    }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $SynthDcp).Hash -ne $ExpectedSynthSha256) {
    throw "Synthesis DCP SHA-256 mismatch"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$TclScript = Join-Path $RepoRoot "tcl\export_rtl_evidence_schematics.tcl"
$VivadoLog = Join-Path $OutputDir "vivado_rtl_evidence.log"
$VivadoJournal = Join-Path $OutputDir "vivado_rtl_evidence.jou"

& $Vivado -mode batch -log $VivadoLog -journal $VivadoJournal `
    -source $TclScript -tclargs $OutputDir
if ($LASTEXITCODE -ne 0) {
    throw "Vivado RTL evidence export failed with exit code $LASTEXITCODE"
}

$NativeSvgFiles = Get-ChildItem -LiteralPath $OutputDir -Filter "*.svg" -File |
    Where-Object { $_.BaseName -notmatch '_upright$' } |
    Sort-Object Name
if ($NativeSvgFiles.Count -ne 4) {
    throw "Expected four native Vivado SVG schematics, found $($NativeSvgFiles.Count)"
}

foreach ($Svg in $NativeSvgFiles) {
    $SvgText = Get-Content -LiteralPath $Svg.FullName -Raw
    $ClipRect = [regex]::Match(
        $SvgText,
        '<rect x="0" y="0" width="([0-9.]+)" height="([0-9.]+)" />'
    )
    if (-not $ClipRect.Success) {
        throw "Could not determine native schematic dimensions: $($Svg.FullName)"
    }
    $UprightSvgPath = Join-Path $OutputDir "$($Svg.BaseName)_upright.svg"
    $UprightSvgText = [regex]::Replace(
        $SvgText,
        '<svg viewBox="0 0 [^"]+"',
        "<svg viewBox=`"0 0 $($ClipRect.Groups[1].Value) $($ClipRect.Groups[2].Value)`"",
        1
    )
    $UprightSvgText = [regex]::Replace(
        $UprightSvgText,
        '\s+transform="rotate\(-90\) translate\(-[0-9.]+\)"',
        '',
        1
    )
    Set-Content -LiteralPath $UprightSvgPath -Value $UprightSvgText -Encoding utf8 -NoNewline
}

$UprightSvgFiles = Get-ChildItem -LiteralPath $OutputDir -Filter "*_upright.svg" -File |
    Sort-Object Name
if ($UprightSvgFiles.Count -ne 4) {
    throw "Expected four upright SVG schematics, found $($UprightSvgFiles.Count)"
}

foreach ($Svg in $UprightSvgFiles) {
    $PngPath = [System.IO.Path]::ChangeExtension($Svg.FullName, ".png")
    $PdfPath = [System.IO.Path]::ChangeExtension($Svg.FullName, ".pdf")
    $InkscapeArgs = @(
        "--batch-process",
        $Svg.FullName,
        "--export-type=png",
        "--export-filename=$PngPath",
        "--export-width=3200",
        "--export-background=#ffffff",
        "--export-background-opacity=255"
    )
    $ExportStarted = Get-Date
    & $Inkscape @InkscapeArgs
    $FreshPng = $false
    $Deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $Deadline) {
        if (Test-Path -LiteralPath $PngPath) {
            $PngInfo = Get-Item -LiteralPath $PngPath
            if ($PngInfo.Length -gt 0 -and
                $PngInfo.LastWriteTime -ge $ExportStarted.AddSeconds(-1)) {
                $FreshPng = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $FreshPng) {
        throw "PNG conversion failed: $($Svg.FullName)"
    }
    & $Inkscape --batch-process $Svg.FullName --export-type=pdf "--export-filename=$PdfPath"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $PdfPath)) {
        throw "PDF conversion failed: $($Svg.FullName)"
    }
}

Write-Output "RTL_EVIDENCE_VISUALS_PASS output_dir=$OutputDir"
