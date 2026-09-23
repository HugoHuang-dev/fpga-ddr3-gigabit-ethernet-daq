$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot ('network_backup\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Get-NetAdapter | Select-Object Name,InterfaceDescription,InterfaceGuid,InterfaceIndex,MacAddress,Status,LinkSpeed | Format-List | Out-File (Join-Path $dir 'adapters.txt') -Encoding UTF8
Get-NetIPInterface -AddressFamily IPv4 | Select-Object InterfaceAlias,InterfaceIndex,Dhcp,InterfaceMetric,ConnectionState | Format-List | Out-File (Join-Path $dir 'dhcp.txt') -Encoding UTF8
Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,InterfaceIndex,IPAddress,PrefixLength,PrefixOrigin | Format-List | Out-File (Join-Path $dir 'ipv4.txt') -Encoding UTF8
Get-NetRoute -AddressFamily IPv4 | Select-Object InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Format-List | Out-File (Join-Path $dir 'routes.txt') -Encoding UTF8
Get-DnsClientServerAddress -AddressFamily IPv4 | Format-List | Out-File (Join-Path $dir 'dns.txt') -Encoding UTF8
netsh interface ipv4 show config | Out-File (Join-Path $dir 'original_config.txt') -Encoding UTF8
Write-Host "BACKUP SAVED: $dir"
Write-Host 'Also photograph the original IPv4 properties, including DNS and Advanced settings, before editing.'
Write-Host 'This script has not changed any network setting.'
