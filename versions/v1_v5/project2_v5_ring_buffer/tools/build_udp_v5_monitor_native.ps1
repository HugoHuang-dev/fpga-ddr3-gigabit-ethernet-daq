$ErrorActionPreference = 'Stop'

$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Visual Studio Installer vswhere.exe was not found.'
}

$installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) {
    throw 'Visual Studio C++ build tools were not found.'
}

$devcmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
$source = Join-Path $PSScriptRoot 'udp_v5_monitor_native.cpp'
$output = Join-Path $PSScriptRoot 'udp_v5_monitor_native.exe'
$buildCommand = '"{0}" -arch=amd64 -host_arch=amd64 && cl /nologo /O2 /EHsc /std:c++17 /Fe:"{1}" "{2}" ws2_32.lib iphlpapi.lib' -f $devcmd, $output, $source

& $env:ComSpec /d /s /c $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "Native monitor build failed with exit code $LASTEXITCODE"
}

Write-Host "NATIVE_MONITOR_READY: $output"
