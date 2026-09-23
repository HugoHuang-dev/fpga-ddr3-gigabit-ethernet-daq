$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Administrator PowerShell before running this capture replay.'
}
$expected = @{
    'project2_v5_top.bit' = 'E0BFAA90E77DDE94257B0FADD033CE97A525727A88EF42C5B377DD6D1947FBD3'
    'project2_v5_top.ltx' = '9C76CD050FE5EC07BB8F57763B124F2F55F324171469F33C22CD040041A01931'
    'udp_v5_monitor_rio.exe' = '2C9FD4FB01C2A26C84413E293736C20CBF86F81A17F4D4626CDC5AB58576F253'
}
foreach ($name in $expected.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash -ne $expected[$name]) { throw "Hash mismatch: $name" }
}
$runDir = Join-Path $PSScriptRoot ('replays\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Start-Transcript -Path (Join-Path $runDir 'console.txt') | Out-Null
$captureStarted = $false
try {
    Write-Host "Evidence: $runDir"
    Write-Host 'Program the original BIT and matching LTX from this folder. Press RESET and wait for DDR calibration.'
    Read-Host 'Press Enter only after programming and RESET are complete' | Out-Null
    Get-NetAdapter | Format-List * | Out-File (Join-Path $runDir 'adapters.txt')
    Get-NetIPAddress -AddressFamily IPv4 | Format-List * | Out-File (Join-Path $runDir 'addresses.txt')
    Get-NetRoute -AddressFamily IPv4 | Format-List * | Out-File (Join-Path $runDir 'routes.txt')
    $address = Get-NetIPAddress -AddressFamily IPv4 -IPAddress '192.168.1.100'
    $adapter = Get-NetAdapter -InterfaceIndex $address.InterfaceIndex
    Get-NetAdapterAdvancedProperty -Name $adapter.Name | Format-List * | Out-File (Join-Path $runDir 'adapter_settings.txt')
    Get-NetAdapterStatistics -Name $adapter.Name | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_before.json')
    pktmon status
    # Finalize a leftover capture instead of silently reusing its old output path.
    pktmon stop
    pktmon filter list
    pktmon filter add ('P2Replay_' + (Get-Date -Format 'HHmmss')) -i 192.168.1.11 -t UDP -p 6666
    if ($LASTEXITCODE -ne 0) { throw 'PktMon filter creation failed.' }
    pktmon start --capture --comp nics --pkt-size 128 --file-size 1024 --log-mode circular --file-name (Join-Path $runDir 'ingress.etl')
    if ($LASTEXITCODE -ne 0) { throw 'PktMon start failed. Receiver was not started.' }
    $captureStarted = $true
    & (Join-Path $PSScriptRoot 'udp_v5_monitor_rio.exe') --duration 60 --output (Join-Path $runDir 'rio_result.json')
    $monitorExitCode = $LASTEXITCODE
    "Receiver exit code: $monitorExitCode" | Out-Host
    pktmon counters
    pktmon stop
    if ($LASTEXITCODE -ne 0) { throw 'PktMon stop failed; preserve the ETL and console output.' }
    $captureStarted = $false
    Get-NetAdapterStatistics -Name $adapter.Name | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_after.json')
    Write-Host 'Press FPGA RESET now to stop transmission.'
    Read-Host 'After pressing FPGA RESET, press Enter to convert the saved capture' | Out-Null
    pktmon etl2pcap (Join-Path $runDir 'ingress.etl') --out (Join-Path $runDir 'ingress.pcapng')
    if ($LASTEXITCODE -ne 0) { throw 'Conversion failed; the original ETL is retained.' }
    if (Test-Path -LiteralPath (Join-Path $runDir 'rio_result.json')) {
        Get-Content -LiteralPath (Join-Path $runDir 'rio_result.json')
    }
    Write-Host "Replay finished. Evidence: $runDir"
} finally {
    if ($captureStarted) { pktmon stop }
    Write-Host 'If the FPGA is still transmitting, press its RESET button.'
    Stop-Transcript | Out-Null
}
