[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Vivado,

    [Parameter(Mandatory = $true)]
    [string]$PlacedDcp,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$PlacedSha256,

    [Parameter(Mandatory = $true)]
    [string]$PartPinMap,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$MapSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$HelperSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$RunnerSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$WrapperSha256,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$RunLabel,

    [string]$ExpectedTop = 'aes_gcm_axi_top',
    [string]$ExpectedPart = 'xc7a100tcsg324-1',
    [string]$ExpectedVivadoVersion = '2021.1',
    [double]$ExpectedClockPeriodNs = 5.714,
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$RouteDirective = 'Explore'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Resolve-ExistingFile {
    param([string]$LiteralPath, [string]$Label)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "$Label does not exist: $LiteralPath"
    }
    return (Resolve-Path -LiteralPath $LiteralPath).ProviderPath
}

function Resolve-VivadoCommand {
    param([string]$Command)

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Command).ProviderPath
    }
    $resolved = Get-Command -Name $Command -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    return $resolved.Source
}

function Get-NormalizedSha256 {
    param([string]$LiteralPath)

    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Sha256 {
    param([string]$LiteralPath, [string]$Expected, [string]$Label)

    $actual = Get-NormalizedSha256 -LiteralPath $LiteralPath
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "$Label SHA-256 mismatch: expected $Expected, got $actual"
    }
    return $actual
}

function Write-Tsv {
    param([string]$LiteralPath, [string[]]$Lines)

    [System.IO.File]::WriteAllLines(
        $LiteralPath,
        $Lines,
        (New-Object System.Text.UTF8Encoding($false)))
}

try {
    if ([math]::Abs($ExpectedClockPeriodNs - 5.714) -ge 0.0005) {
        throw 'ExpectedClockPeriodNs must be the production 5.714 ns contract.'
    }
    if ($ExpectedTop -notmatch '^[A-Za-z0-9_]+$') {
        throw 'ExpectedTop contains unsupported characters.'
    }
    if ($ExpectedPart -notmatch '^[A-Za-z0-9_.-]+$') {
        throw 'ExpectedPart contains unsupported characters.'
    }
    if ($ExpectedVivadoVersion -notmatch '^[A-Za-z0-9_.-]+$') {
        throw 'ExpectedVivadoVersion contains unsupported characters.'
    }

    $vivadoPath = Resolve-VivadoCommand -Command $Vivado
    $placedSource = Resolve-ExistingFile -LiteralPath $PlacedDcp -Label 'Placed DCP'
    $mapSource = Resolve-ExistingFile -LiteralPath $PartPinMap -Label 'PartPin map'
    $scriptRoot = Split-Path -Parent $PSCommandPath
    $helperSource = Resolve-ExistingFile -LiteralPath (
        Join-Path $scriptRoot 'partpin_ooc.tcl') -Label 'PartPin helper'
    $runnerSource = Resolve-ExistingFile -LiteralPath (
        Join-Path $scriptRoot 'run_partpin_replay.tcl') -Label 'Replay Tcl runner'
    $wrapperSource = Resolve-ExistingFile -LiteralPath $PSCommandPath -Label 'Signoff wrapper'

    $placedExpected = $PlacedSha256.ToUpperInvariant()
    $mapExpected = $MapSha256.ToUpperInvariant()
    $helperExpected = $HelperSha256.ToUpperInvariant()
    $runnerExpected = $RunnerSha256.ToUpperInvariant()
    $wrapperExpected = $WrapperSha256.ToUpperInvariant()
    Assert-Sha256 -LiteralPath $placedSource -Expected $placedExpected -Label 'Source placed DCP' | Out-Null
    Assert-Sha256 -LiteralPath $mapSource -Expected $mapExpected -Label 'Source PartPin map' | Out-Null
    Assert-Sha256 -LiteralPath $helperSource -Expected $helperExpected -Label 'Source PartPin helper' | Out-Null
    Assert-Sha256 -LiteralPath $runnerSource -Expected $runnerExpected -Label 'Source replay Tcl runner' | Out-Null
    Assert-Sha256 -LiteralPath $wrapperSource -Expected $wrapperExpected -Label 'Source signoff wrapper' | Out-Null

    if (-not (Test-Path -LiteralPath $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot | Out-Null
    }
    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        throw "OutputRoot is not a directory: $OutputRoot"
    }
    $resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).ProviderPath
    $runDir = Join-Path $resolvedOutputRoot $RunLabel
    if (Test-Path -LiteralPath $runDir) {
        throw "Replay run directory already exists: $runDir"
    }

    New-Item -ItemType Directory -Path $runDir | Out-Null
    $inputDir = New-Item -ItemType Directory -Path (
        Join-Path $runDir 'inputs')
    $scriptDir = New-Item -ItemType Directory -Path (
        Join-Path $runDir 'scripts')
    New-Item -ItemType Directory -Path (Join-Path $runDir 'reports') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $runDir 'checkpoints') | Out-Null

    $stagedPlaced = Join-Path $inputDir.FullName 'placed.dcp'
    $stagedMap = Join-Path $inputDir.FullName 'partpin_map.tsv'
    $stagedHelper = Join-Path $scriptDir.FullName 'partpin_ooc.tcl'
    $stagedRunner = Join-Path $scriptDir.FullName 'run_partpin_replay.tcl'
    $stagedWrapper = Join-Path $scriptDir.FullName 'run_axi_ooc_signoff.ps1'
    Copy-Item -LiteralPath $placedSource -Destination $stagedPlaced
    Copy-Item -LiteralPath $mapSource -Destination $stagedMap
    Copy-Item -LiteralPath $helperSource -Destination $stagedHelper
    Copy-Item -LiteralPath $runnerSource -Destination $stagedRunner
    Copy-Item -LiteralPath $PSCommandPath -Destination $stagedWrapper

    Assert-Sha256 -LiteralPath $stagedPlaced -Expected $placedExpected -Label 'Staged placed DCP' | Out-Null
    Assert-Sha256 -LiteralPath $stagedMap -Expected $mapExpected -Label 'Staged PartPin map' | Out-Null
    Assert-Sha256 -LiteralPath $stagedHelper -Expected $helperExpected -Label 'Staged PartPin helper' | Out-Null
    Assert-Sha256 -LiteralPath $stagedRunner -Expected $runnerExpected -Label 'Staged replay Tcl runner' | Out-Null
    Assert-Sha256 -LiteralPath $stagedWrapper -Expected $wrapperExpected -Label 'Staged signoff wrapper' | Out-Null
    (Get-Item -LiteralPath $stagedPlaced).IsReadOnly = $true
    (Get-Item -LiteralPath $stagedMap).IsReadOnly = $true
    (Get-Item -LiteralPath $stagedHelper).IsReadOnly = $true
    (Get-Item -LiteralPath $stagedRunner).IsReadOnly = $true
    (Get-Item -LiteralPath $stagedWrapper).IsReadOnly = $true

    $periodText = $ExpectedClockPeriodNs.ToString(
        '0.000', [System.Globalization.CultureInfo]::InvariantCulture)
    $identityPath = Join-Path $runDir 'replay_identity.tsv'
    Write-Tsv -LiteralPath $identityPath -Lines @(
        "field`tvalue",
        "placed_source`t$placedSource",
        "placed_sha256`t$placedExpected",
        "map_source`t$mapSource",
        "map_sha256`t$mapExpected",
        "helper_source`t$helperSource",
        "helper_sha256`t$helperExpected",
        "runner_source`t$runnerSource",
        "runner_sha256`t$runnerExpected",
        "wrapper_source`t$wrapperSource",
        "wrapper_sha256`t$wrapperExpected",
        "scope`tOOC_PARTPIN",
        "board_route`t0",
        "top`t$ExpectedTop",
        "part`t$ExpectedPart",
        "vivado_version`t$ExpectedVivadoVersion",
        "clock_period_ns`t$periodText",
        "route_directive`t$RouteDirective"
    )

    $vivadoLog = Join-Path $runDir 'vivado.log'
    $vivadoJournal = Join-Path $runDir 'vivado.jou'
    $consoleLog = Join-Path $runDir 'vivado.console.log'
    $vivadoArgs = @(
        '-mode', 'batch',
        '-log', $vivadoLog,
        '-journal', $vivadoJournal,
        '-source', $stagedRunner,
        '-tclargs',
        $stagedPlaced,
        $placedExpected,
        $stagedMap,
        $mapExpected,
        $runDir,
        $ExpectedTop,
        $ExpectedPart,
        $ExpectedVivadoVersion,
        $periodText,
        $RouteDirective
    )

    Push-Location -LiteralPath $runDir
    try {
        & $vivadoPath @vivadoArgs *> $consoleLog
        $vivadoExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    Assert-Sha256 -LiteralPath $stagedPlaced -Expected $placedExpected -Label 'Post-run staged placed DCP' | Out-Null
    Assert-Sha256 -LiteralPath $stagedMap -Expected $mapExpected -Label 'Post-run staged PartPin map' | Out-Null
    Assert-Sha256 -LiteralPath $stagedHelper -Expected $helperExpected -Label 'Post-run staged PartPin helper' | Out-Null
    Assert-Sha256 -LiteralPath $stagedRunner -Expected $runnerExpected -Label 'Post-run staged replay Tcl runner' | Out-Null
    Assert-Sha256 -LiteralPath $stagedWrapper -Expected $wrapperExpected -Label 'Post-run staged signoff wrapper' | Out-Null
    Assert-Sha256 -LiteralPath $placedSource -Expected $placedExpected -Label 'Post-run source placed DCP' | Out-Null
    Assert-Sha256 -LiteralPath $mapSource -Expected $mapExpected -Label 'Post-run source PartPin map' | Out-Null
    Assert-Sha256 -LiteralPath $helperSource -Expected $helperExpected -Label 'Post-run source PartPin helper' | Out-Null
    Assert-Sha256 -LiteralPath $runnerSource -Expected $runnerExpected -Label 'Post-run source replay Tcl runner' | Out-Null
    Assert-Sha256 -LiteralPath $wrapperSource -Expected $wrapperExpected -Label 'Post-run source signoff wrapper' | Out-Null
    if ($vivadoExitCode -ne 0) {
        throw "Vivado replay exited with code $vivadoExitCode"
    }

    $postIdentityPath = Join-Path $runDir 'replay_post_identity.tsv'
    Write-Tsv -LiteralPath $postIdentityPath -Lines @(
        "field`tvalue",
        "placed_source_sha256`t$placedExpected",
        "placed_staged_sha256`t$placedExpected",
        "map_source_sha256`t$mapExpected",
        "map_staged_sha256`t$mapExpected",
        "helper_source_sha256`t$helperExpected",
        "helper_staged_sha256`t$helperExpected",
        "runner_source_sha256`t$runnerExpected",
        "runner_staged_sha256`t$runnerExpected",
        "wrapper_source_sha256`t$wrapperExpected",
        "wrapper_staged_sha256`t$wrapperExpected"
    )

    $requiredArtifacts = @(
        $vivadoLog,
        $vivadoJournal,
        $consoleLog,
        $identityPath,
        $postIdentityPath,
        (Join-Path $runDir "checkpoints/${ExpectedTop}_placed_partpin.dcp"),
        (Join-Path $runDir "checkpoints/${ExpectedTop}_routed.dcp"),
        (Join-Path $runDir 'reports/live_port_audit.tsv'),
        (Join-Path $runDir 'reports/routed_port_audit.tsv'),
        (Join-Path $runDir 'reports/effective_partpins.xdc'),
        (Join-Path $runDir 'reports/effective_constraints.xdc'),
        (Join-Path $runDir 'reports/ooc_boundary_properties.tsv'),
        (Join-Path $runDir 'reports/ooc_io_constraints.xdc'),
        (Join-Path $runDir 'reports/timing_exceptions.rpt'),
        (Join-Path $runDir 'reports/signoff_summary.tsv'),
        (Join-Path $runDir 'reports/methodology_routed.rpt'),
        (Join-Path $runDir 'reports/utilization_routed.rpt'),
        (Join-Path $runDir 'reports/timing_routed.rpt'),
        (Join-Path $runDir 'reports/route_status.rpt'),
        (Join-Path $runDir 'reports/drc_routed.rpt'),
        (Join-Path $runDir 'reports/boundary_input_setup.rpt'),
        (Join-Path $runDir 'reports/boundary_input_hold.rpt'),
        (Join-Path $runDir 'reports/boundary_output_setup.rpt'),
        (Join-Path $runDir 'reports/boundary_output_hold.rpt'),
        (Join-Path $runDir 'reports/reset_setup.rpt'),
        (Join-Path $runDir 'reports/reset_hold.rpt'),
        (Join-Path $runDir 'reports/internal_setup.rpt'),
        (Join-Path $runDir 'reports/internal_hold.rpt')
    )
    foreach ($artifact in $requiredArtifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "Required replay artifact is missing: $artifact"
        }
        if ((Get-Item -LiteralPath $artifact).Length -eq 0) {
            throw "Required replay artifact is empty: $artifact"
        }
    }

    $vivadoText = [System.IO.File]::ReadAllText($vivadoLog)
    $passPattern = '(?m)^PARTPIN_REPLAY_TCL_SUMMARY status=PASS .+$'
    $errorPattern = '(?m)^PARTPIN_REPLAY_TCL_SUMMARY status=(?:ERROR|FAIL)(?: .*)?$'
    if ([regex]::Matches($vivadoText, $passPattern).Count -ne 1) {
        throw 'Vivado log does not contain exactly one Tcl PASS marker.'
    }
    if ([regex]::Matches($vivadoText, $errorPattern).Count -ne 0) {
        throw 'Vivado log contains a Tcl ERROR/FAIL marker.'
    }
    if ([regex]::Matches(
            $vivadoText,
            '(?m)^WARNING: \[Route 35-198\].*$').Count -ne 0) {
        throw 'Vivado log contains a missing HD.PARTPIN_LOCS warning.'
    }

    $summaryPath = Join-Path $runDir 'reports/signoff_summary.tsv'
    $summaryRows = Import-Csv -LiteralPath $summaryPath -Delimiter "`t"
    $statusRows = @($summaryRows | Where-Object { $_.field -eq 'status' })
    if ($statusRows.Count -ne 1 -or $statusRows[0].value -ne 'PASS') {
        throw 'Machine signoff summary is not exactly PASS.'
    }
    $scopeRows = @($summaryRows | Where-Object { $_.field -eq 'SCOPE' })
    if ($scopeRows.Count -ne 1 -or $scopeRows[0].value -ne 'OOC_PARTPIN') {
        throw 'Machine signoff summary has the wrong scope.'
    }
    $boardRows = @($summaryRows | Where-Object { $_.field -eq 'BOARD_ROUTE' })
    if ($boardRows.Count -ne 1 -or $boardRows[0].value -ne '0') {
        throw 'Machine signoff summary incorrectly claims a board route.'
    }

    $manifestPath = Join-Path $runDir 'artifact_manifest.sha256.tsv'
    $manifestLines = New-Object System.Collections.Generic.List[string]
    $manifestLines.Add("sha256`tbytes`trelative_path")
    $runPrefix = $runDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $artifactFiles = Get-ChildItem -LiteralPath $runDir -Recurse -File |
        Where-Object { $_.FullName -ne $manifestPath } |
        Sort-Object FullName
    foreach ($file in $artifactFiles) {
        $relative = $file.FullName.Substring($runPrefix.Length).Replace('\', '/')
        $hash = Get-NormalizedSha256 -LiteralPath $file.FullName
        $manifestLines.Add("$hash`t$($file.Length)`t$relative")
    }
    Write-Tsv -LiteralPath $manifestPath -Lines $manifestLines.ToArray()

    $finalDcp = Join-Path $runDir "checkpoints/${ExpectedTop}_routed.dcp"
    $finalDcpSha = Get-NormalizedSha256 -LiteralPath $finalDcp
    $manifestSha = Get-NormalizedSha256 -LiteralPath $manifestPath
    Write-Output "PARTPIN_REPLAY_FINAL status=PASS scope=OOC_PARTPIN board_route=0 placed_sha256=$placedExpected map_sha256=$mapExpected helper_sha256=$helperExpected runner_sha256=$runnerExpected wrapper_sha256=$wrapperExpected final_dcp_sha256=$finalDcpSha manifest_sha256=$manifestSha"
    exit 0
}
catch {
    [Console]::Error.WriteLine(
        "PARTPIN_REPLAY_FINAL status=ERROR message=$($_.Exception.Message)")
    exit 1
}
