param(
    [ValidateRange(1, 86400)]
    [int]$DurationSeconds = 60
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Right-click 01_Run_V6_400M_60s_NoCapture.cmd and choose Run as administrator.'
}

$exe = Join-Path $PSScriptRoot 'receiver\udp_v5_monitor_rio.exe'
$expectedReceiverHash = '2C9FD4FB01C2A26C84413E293736C20CBF86F81A17F4D4626CDC5AB58576F253'
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedReceiverHash) {
    throw 'Receiver hash mismatch.'
}

$ip = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress '192.168.1.100' -ErrorAction SilentlyContinue)
if ($ip.Count -ne 1 -or $ip[0].PrefixLength -ne 24) {
    throw 'Set exactly one Ethernet interface to 192.168.1.100 / 255.255.255.0 first.'
}
$adapter = Get-NetAdapter -InterfaceIndex $ip[0].InterfaceIndex
if ($adapter.Status -ne 'Up') {
    throw 'Ethernet link is not Up. Check board power and cable.'
}

$runDir = Join-Path $PSScriptRoot ('results\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$rule = 'Project2_V6_400M_' + [guid]::NewGuid().ToString('N')
$ruleAdded = $false
$receiverExitCode = -1

Start-Transcript -Path (Join-Path $runDir 'console.txt') | Out-Null
try {
    Write-Host "RESULTS: $runDir"
    Write-Host "This is the controlled V6 400 Mb/s NO-CAPTURE test for $DurationSeconds seconds."
    Write-Host 'Use Windows performance power mode. Close WeChat, NetEase Music, browsers, downloads, cloud sync and unnecessary background programs.'
    Write-Host 'Confirm PktMon is stopped. Program fpga\project2_v6_400m.bit with the matching LTX.'
    Write-Host 'Press board RESET once, wait at least 5 seconds, then press Enter here. Do not press KEY0 yet.'
    Read-Host | Out-Null

    powercfg /getactivescheme | Out-File (Join-Path $runDir 'power_scheme.txt') -Encoding UTF8
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 25 Name,Id,CPU,WorkingSet64 | ConvertTo-Json | Set-Content (Join-Path $runDir 'top_processes_before.json')
    $adapter | Select-Object Name,InterfaceDescription,InterfaceGuid,Status,LinkSpeed,DriverVersion | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter.txt')
    Get-NetAdapterStatistics -Name $adapter.Name | Select-Object ReceivedPacketErrors,ReceivedDiscardedPackets,ReceivedUnicastPackets,ReceivedBytes | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_before.json')

    pktmon stop | Out-File (Join-Path $runDir 'pktmon_stop.txt') -Encoding UTF8
    New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow -Program $exe -Protocol UDP -LocalPort 6666 -LocalAddress 192.168.1.100 -RemoteAddress 192.168.1.11 -Profile Any | Out-Null
    $ruleAdded = $true

    Write-Host 'The receiver will prepare its buffers. Press KEY0 exactly once only after it prints ARMED.'
    & $exe --duration $DurationSeconds --output (Join-Path $runDir 'rio_result.json')
    $receiverExitCode = $LASTEXITCODE
    Write-Host "Receiver exit code: $receiverExitCode"

    Get-NetAdapterStatistics -Name $adapter.Name | Select-Object ReceivedPacketErrors,ReceivedDiscardedPackets,ReceivedUnicastPackets,ReceivedBytes | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_after.json')
    Write-Host 'Press FPGA RESET once to stop/rearm transmission, then press Enter here.'
    Read-Host | Out-Null
} finally {
    if ($ruleAdded) {
        Remove-NetFirewallRule -Name $rule -ErrorAction Continue
    }
    Stop-Transcript | Out-Null
}

Write-Host "DONE. Copy or return the complete folder: $runDir"
if ($receiverExitCode -ne 0) {
    Write-Host 'This run is a strict FAIL. Keep rio_result.json and console.txt; do not rerun before recording it.'
    exit $receiverExitCode
}
Write-Host "This $DurationSeconds-second run passed. Keep the complete result folder."


