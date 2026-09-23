[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$simRoot = Join-Path $projectRoot 'sim'
$rtlRoot = Join-Path $projectRoot 'rtl'
$resultRoot = Join-Path $simRoot 'results'
$workRoot = Join-Path $simRoot '.modelsim_work'
New-Item -ItemType Directory -Force -Path $resultRoot, $workRoot | Out-Null

$vlog = Get-Command vlog -ErrorAction Stop
$vsim = Get-Command vsim -ErrorAction Stop
$tests = @(
    [pscustomobject]@{
        Name = 'ingress_fifo'
        Top = 'tb_v9_ingress_fifo'
        Rtl = @(Join-Path $rtlRoot 'v6_ingress_fifo.v')
        Testbench = Join-Path $simRoot 'tb_v9_ingress_fifo.v'
        PassText = 'PASS tb_v9_ingress_fifo:'
        Coverage = 'FIFO full/empty and watermarks; hysteretic source gate; input/output backpressure; ordering; simultaneous push/pop; flush; overflow/underflow injection; counter clear'
    },
    [pscustomobject]@{
        Name = 'packetizer'
        Top = 'tb_v9_packetizer'
        Rtl = @(Join-Path $rtlRoot 'udp_v9_tx_fifo_packetizer.v')
        Testbench = Join-Path $simRoot 'tb_v9_packetizer.v'
        PassText = 'PASS tb_v9_packetizer:'
        Coverage = 'Exact 32-byte P2V9 header; 1024-byte payload byte comparison; packet sequence; 64-bit first-word index; packet-boundary app_tx_ready backpressure; early/late last; overflow/underflow; clear'
    },
    [pscustomobject]@{
        Name = 'pipeline_controller'
        Top = 'tb_v9_pipeline_controller'
        Rtl = @(Join-Path $rtlRoot 'v6_pipeline_controller.v')
        Testbench = Join-Path $simRoot 'tb_v9_pipeline_controller.v'
        PassText = 'PASS tb_v9_pipeline_controller:'
        Coverage = 'Ring write/read pointers and wrap; committed/released accounting; high/low-water drain hysteresis; write/read backpressure; overflow/underflow fault injection; FIFO/packetizer fatal inputs; AXI BRESP error'
    }
)

$rows = [System.Collections.Generic.List[string]]::new()
$failed = $false
foreach ($test in $tests) {
    foreach ($source in @($test.Rtl) + @($test.Testbench)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required V9 simulation source is missing: $source"
        }
    }

    $testWork = Join-Path $workRoot $test.Name
    if (Test-Path -LiteralPath $testWork) {
        $resolvedWork = [IO.Path]::GetFullPath($testWork)
        $resolvedRoot = [IO.Path]::GetFullPath($workRoot) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedWork.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean ModelSim work directory outside sim root: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testWork | Out-Null
    $transcript = Join-Path $resultRoot ("{0}_transcript.log" -f $test.Name)

    Push-Location $testWork
    try {
        $vlibOutput = (& vlib work 2>&1 | Out-String)
        $vlibExit = $LASTEXITCODE
        $compileArgs = @('-work', 'work') + @($test.Rtl) + @($test.Testbench)
        $compileOutput = (& $vlog.Source @compileArgs 2>&1 | Out-String)
        $compileExit = $LASTEXITCODE
        $simOutput = ''
        $simExit = -1
        if ($vlibExit -eq 0 -and $compileExit -eq 0) {
            $simOutput = (& $vsim.Source '-c' '-lib' 'work' $test.Top '-do' 'run -all; quit -f' 2>&1 | Out-String)
            $simExit = $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $allOutput = @(
        "V9 ModelSim regression: $($test.Name)"
        "UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "RTL: $($test.Rtl -join ', ')"
        "Testbench: $($test.Testbench)"
        ''
        '=== vlib ==='
        $vlibOutput.TrimEnd()
        '=== vlog ==='
        $compileOutput.TrimEnd()
        '=== vsim ==='
        $simOutput.TrimEnd()
        ''
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($transcript, $allOutput, [Text.UTF8Encoding]::new($false))

    $hasPass = $simOutput.Contains($test.PassText)
    $hasBenchFailure = [regex]::IsMatch($simOutput, '(?m)^#\s+FAIL\b')
    $passed = $vlibExit -eq 0 -and $compileExit -eq 0 -and $simExit -eq 0 -and $hasPass -and -not $hasBenchFailure
    if (-not $passed) { $failed = $true }
    $status = if ($passed) { 'PASS' } else { 'FAIL' }
    $rows.Add("| $($test.Name) | $status | $($test.Coverage) | [transcript](./$($test.Name)_transcript.log) |")
    Write-Host ("[{0}] {1}" -f $status, $test.Name)
}

$summary = @(
    '# V9 ModelSim 10.6c regression summary'
    ''
    "Generated: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    ''
    'This regression compiles and simulates the V9 project RTL directly; no V8 test is counted as V9 evidence.'
    ''
    '| Test | Result | Self-checked coverage | Raw transcript |'
    '|---|---:|---|---|'
) + $rows + @(
    ''
    $(if ($failed) { '**Overall: FAIL**' } else { '**Overall: PASS — 3/3 self-checking RTL simulations passed.**' })
    ''
    'The packetizer backpressure test covers the real packet-boundary contract: a packet is not launched while `app_tx_ready` is low, queued bytes and sequence/index remain unchanged, and ready-low/high is exercised between packets.'
    ''
)
$summaryPath = Join-Path $resultRoot 'MODELSIM_V9_SUMMARY.md'
[IO.File]::WriteAllLines($summaryPath, $summary, [Text.UTF8Encoding]::new($false))

if ($failed) {
    throw "One or more V9 ModelSim regressions failed. See $summaryPath"
}
Write-Host "V9 ModelSim regression PASS. Summary: $summaryPath"
