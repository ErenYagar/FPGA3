param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedCoreSha256
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$VivadoBin = 'C:\Xilinx\Vivado\2021.1\bin'
$Xvlog = Join-Path $VivadoBin 'xvlog.bat'
$Xelab = Join-Path $VivadoBin 'xelab.bat'
$Xsim = Join-Path $VivadoBin 'xsim.bat'
$RtlRoot = Join-Path $RepoRoot 'engrenring\rtl\source'
$TestRoot = Join-Path $RepoRoot 'engrenring\rtl\functional test'
$CoreFile = Join-Path $RtlRoot 'stream_core\aes_gcm_stream_core.v'
$OutputRoot = Join-Path $RepoRoot "engrenring\synth_1g\axi_ooc\r54_verify_$Label"

foreach ($Tool in @($Xvlog, $Xelab, $Xsim)) {
    if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) {
        throw "Vivado 2021.1 tool not found: $Tool"
    }
}

$Branch = (git -C $RepoRoot branch --show-current).Trim()
$Commit = (git -C $RepoRoot rev-parse HEAD).Trim()
$Status = (git -C $RepoRoot status --porcelain) -join "`n"
if ($Branch -notlike 'timing/round54-*') {
    throw "Not on a Round54 branch: $Branch"
}
if ($Status) {
    throw "Working tree is not clean:`n$Status"
}

$ActualCoreSha256 = (Get-FileHash -LiteralPath $CoreFile -Algorithm SHA256).Hash
if ($ActualCoreSha256 -ne $ExpectedCoreSha256.ToUpperInvariant()) {
    throw "Core SHA-256 mismatch: expected=$ExpectedCoreSha256 actual=$ActualCoreSha256"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Refusing to overwrite verification directory: $OutputRoot"
}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null

$RtlFiles = @(
    (Join-Path $RtlRoot 'aes_core\sbox.v'),
    (Join-Path $RtlRoot 'stream_aes\aes_block_engine.v'),
    (Join-Path $RtlRoot 'stream_aes\aes_key_context.v'),
    (Join-Path $RtlRoot 'stream_ghash\ghash16.v'),
    (Join-Path $RtlRoot 'stream_axi\axi_lite_regs.v'),
    (Join-Path $RtlRoot 'stream_axi\axis_output_skid_8.v'),
    $CoreFile,
    (Join-Path $RtlRoot 'stream_core\stream_fifo.v'),
    (Join-Path $RtlRoot 'aes_gcm_axi_top.v')
)
$TestFiles = @(
    (Join-Path $TestRoot 'sv\tb_axi_smoke.sv'),
    (Join-Path $TestRoot 'sv\tb_throughput.sv'),
    (Join-Path $TestRoot 'sv\tb_nist.sv'),
    (Join-Path $TestRoot 'sv\tb_round48_boundary_directed.sv'),
    (Join-Path $TestRoot 'sv\tb_round49_residual_directed.sv'),
    (Join-Path $TestRoot 'sv\tb_round53_core_zeroize_directed.sv'),
    (Join-Path $TestRoot 'sv\tb_round53_key_midzeroize_directed.sv'),
    (Join-Path $TestRoot 'sv\tb_round53_non96_ghash_zeroize_directed.sv'),
    (Join-Path $TestRoot 'sv\tb_round53_zeroize_public_directed.sv')
)
$GlblFile = Join-Path (Split-Path $VivadoBin -Parent) 'data\verilog\src\glbl.v'

function Invoke-Logged {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    & $Tool @Arguments 2>&1 | Tee-Object -FilePath $LogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit $LASTEXITCODE; see $LogFile"
    }
}

function Invoke-Round54Test {
    param(
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string]$RunName,
        [Parameter(Mandatory = $true)][string[]]$ExpectedSignatures,
        [string[]]$PlusArgs = @()
    )

    $Snapshot = "r54_${RunName}_sim"
    Invoke-Logged -Tool $Xelab -Arguments @(
        $Top, 'glbl', '-L', 'unisims_ver', '-s', $Snapshot
    ) -LogFile (Join-Path $OutputRoot "${RunName}_xelab.log")

    $Arguments = @($Snapshot, '-runall')
    foreach ($PlusArg in $PlusArgs) {
        $Arguments += @('-testplusarg', $PlusArg)
    }
    $RunLog = Join-Path $OutputRoot "${RunName}_xsim.log"
    Invoke-Logged -Tool $Xsim -Arguments $Arguments -LogFile $RunLog

    $Contents = Get-Content -LiteralPath $RunLog -Raw
    foreach ($Signature in $ExpectedSignatures) {
        if (-not $Contents.Contains($Signature)) {
            throw "Missing signature '$Signature' in $RunLog"
        }
    }
    Write-Host "ROUND54_TEST_PASS name=$RunName"
}

Set-Location $OutputRoot
@(
    "label=$Label",
    "git_branch=$Branch",
    "git_commit=$Commit",
    "core_sha256=$ActualCoreSha256",
    'vivado_version=2021.1'
) | Set-Content -LiteralPath (Join-Path $OutputRoot 'provenance.txt')

Invoke-Logged -Tool $Xvlog -Arguments (@('--sv') + $RtlFiles + $TestFiles + $GlblFile) `
    -LogFile (Join-Path $OutputRoot 'compile_stdout.log')

Invoke-Round54Test tb_axi_smoke smoke @('AXI_SMOKE_PASS cycles=8364')
Invoke-Round54Test tb_throughput throughput @(
    'THROUGHPUT mode=AES-128 direction=encrypt cycles=18920',
    'THROUGHPUT mode=AES-128 direction=decrypt cycles=19139',
    'THROUGHPUT mode=AES-192 direction=encrypt cycles=19520',
    'THROUGHPUT mode=AES-192 direction=decrypt cycles=19739',
    'THROUGHPUT mode=AES-256 direction=encrypt cycles=20120',
    'THROUGHPUT mode=AES-256 direction=decrypt cycles=20339',
    'THROUGHPUT_PASS all key modes >= 1.0 Gbps'
)
Invoke-Round54Test tb_round48_boundary_directed round48 @(
    'ROUND48_BOUNDARY_DIRECTED_PASS'
)
Invoke-Round54Test tb_round49_residual_directed round49 @(
    'ROUND49_RESIDUAL_DIRECTED_PASS'
)
Invoke-Round54Test tb_round53_core_zeroize_directed round53_core @(
    'ROUND54_PREP_TAG_REPEATED_ZEROIZE_PASS same_edge_clear=1 value=000',
    'ROUND53_CORE_ZEROIZE_PASS result=13 visible_fires=1',
    'ROUND53_ZSEQ_ADMISSION_PASS held_until_abort=1 admitted_next_edge=1',
    'ROUND53_DESCRIPTOR_ZEROIZE_COLLISION_PASS'
) @('EXPECT_LOCAL_PREP_CLEAR')
Invoke-Round54Test tb_round53_key_midzeroize_directed round53_key @(
    'KEY_MID_EXPANSION_ZEROIZE_PASS'
)
Invoke-Round54Test tb_round53_non96_ghash_zeroize_directed round53_non96 @(
    'ROUND53_NON96_GHASH_ZEROIZE_PASS',
    'ROUND53_GHASH_SLOT_STALL_PASS',
    'ROUND53_AES_DATA_CAPACITY_STALL_PASS'
)
Invoke-Round54Test tb_round53_zeroize_public_directed round53_public @(
    'ROUND53_PUBLIC_ZEROIZE_PASS idle_results=0 accepted=2 abort_results=2'
)

$RspDirectory = (Join-Path $TestRoot 'rsp').Replace('\', '/')
Invoke-Round54Test tb_nist nist525 @(
    'NIST_TOTAL_SUMMARY pass=525 fail=0 total=525 cycles=145808',
    'NIST_LIMITED_DONE pass=525 fail=0 total=525'
) @('MAX_VECTORS_525', "RSP_DIR_$RspDirectory")
Invoke-Round54Test tb_nist nist5255 @(
    'NIST_TOTAL_SUMMARY pass=5255 fail=0 total=5255 cycles=1615588',
    'NIST_LIMITED_DONE pass=5255 fail=0 total=5255'
) @('MAX_VECTORS_5255', "RSP_DIR_$RspDirectory")

Write-Host "ROUND54_REGRESSION_PASS label=$Label commit=$Commit core_sha256=$ActualCoreSha256"
