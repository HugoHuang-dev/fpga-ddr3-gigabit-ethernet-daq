$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Right-click 02_Run_Test.cmd and choose Run as administrator.' }
$exe = Join-Path $PSScriptRoot 'receiver\udp_v5_monitor_rio.exe'
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne '2C9FD4FB01C2A26C84413E293736C20CBF86F81A17F4D4626CDC5AB58576F253') { throw 'Receiver hash mismatch.' }
$ip = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress '192.168.1.100' -ErrorAction SilentlyContinue)
if ($ip.Count -ne 1 -or $ip[0].PrefixLength -ne 24) { throw 'Set exactly one Ethernet interface to 192.168.1.100 / 255.255.255.0 first.' }
$adapter = Get-NetAdapter -InterfaceIndex $ip[0].InterfaceIndex
if ($adapter.Status -ne 'Up') { throw 'Ethernet link is not Up. Check board power and cable.' }
$runDir = Join-Path $PSScriptRoot ('results\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$rule = 'Project2UsbKit_' + [guid]::NewGuid().ToString('N')
$captureStarted = $false
$ruleAdded = $false
Start-Transcript -Path (Join-Path $runDir 'console.txt') | Out-Null
try {
    Write-Host "RESULTS: $runDir"
    $adapter | Select-Object Name,InterfaceDescription,InterfaceGuid,Status,LinkSpeed,DriverVersion | Format-List
    Write-Host 'Use the original 200M BIT on the board. Press board RESET, wait for DDR calibration, then press Enter here.'
    Read-Host | Out-Null
    Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed | Format-List | Out-File (Join-Path $runDir 'adapters.txt') -Encoding UTF8
    Get-NetIPAddress -AddressFamily IPv4 | Format-List | Out-File (Join-Path $runDir 'addresses.txt') -Encoding UTF8
    Get-NetRoute -AddressFamily IPv4 | Format-List | Out-File (Join-Path $runDir 'routes.txt') -Encoding UTF8
    Get-NetAdapterStatistics -Name $adapter.Name | Select-Object ReceivedPacketErrors,ReceivedDiscardedPackets,ReceivedUnicastPackets,ReceivedBytes | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_before.json')
    New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow -Program $exe -Protocol UDP -LocalPort 6666 -LocalAddress 192.168.1.100 -RemoteAddress 192.168.1.11 -Profile Any | Out-Null
    $ruleAdded = $true
    pktmon status
    pktmon stop
    pktmon filter list
    pktmon filter add ('P2Kit_' + (Get-Date -Format 'HHmmss')) -i 192.168.1.11 -t UDP -p 6666
    if ($LASTEXITCODE -ne 0) { throw 'PktMon filter failed; no test started.' }
    pktmon start --capture --comp nics --pkt-size 128 --file-size 1024 --log-mode circular --file-name (Join-Path $runDir 'ingress.etl')
    if ($LASTEXITCODE -ne 0) { throw 'PktMon start failed; no test started. Keep console output.' }
    $captureStarted = $true
    Write-Host 'Press KEY0 only after the receiver prints ARMED.'
    & $exe --duration 60 --output (Join-Path $runDir 'rio_result.json')
    Write-Host "Receiver exit code: $LASTEXITCODE"
    pktmon counters
    pktmon stop
    if ($LASTEXITCODE -ne 0) { throw 'Capture stop failed. Keep all files.' }
    $captureStarted = $false
    Get-NetAdapterStatistics -Name $adapter.Name | Select-Object ReceivedPacketErrors,ReceivedDiscardedPackets,ReceivedUnicastPackets,ReceivedBytes | ConvertTo-Json | Set-Content (Join-Path $runDir 'adapter_after.json')
    Write-Host 'Press FPGA RESET to stop transmission. Then press Enter here.'
    Read-Host | Out-Null
    pktmon etl2pcap (Join-Path $runDir 'ingress.etl') --out (Join-Path $runDir 'ingress.pcapng')
    if ($LASTEXITCODE -ne 0) { throw 'Conversion failed. Preserve ingress.etl.' }
    Write-Host "DONE. Copy the whole results folder back: $runDir"
} finally {
    if ($captureStarted) { pktmon stop }
    if ($ruleAdded) { Remove-NetFirewallRule -Name $rule -ErrorAction Continue }
    Write-Host 'Press board RESET if it is still sending. Restore the Ethernet IPv4 and DNS settings using the guide.'
    Stop-Transcript | Out-Null
}
