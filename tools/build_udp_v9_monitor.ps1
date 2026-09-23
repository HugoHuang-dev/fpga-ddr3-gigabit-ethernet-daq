[CmdletBinding()]
param(
    [switch]$RunSelfTest
)

$ErrorActionPreference = 'Stop'
$toolDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $toolDirectory 'udp_v9_monitor_rio.cpp'
$executable = Join-Path $toolDirectory 'udp_v9_monitor_rio.exe'
$object = Join-Path $toolDirectory 'udp_v9_monitor_rio.obj'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "Visual Studio locator not found: $vswhere"
}

$installation = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $installation) {
    throw 'A Visual Studio installation with the C++ x64 toolchain was not found.'
}

$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars)) {
    throw "vcvars64.bat not found: $vcvars"
}

$compile = 'call "{0}" >nul && cl.exe /nologo /std:c++17 /EHsc /O2 /W4 /D_CRT_SECURE_NO_WARNINGS "{1}" /Fo:"{2}" /Fe:"{3}"' -f `
    $vcvars, $source, $object, $executable
& cmd.exe /d /s /c $compile
if ($LASTEXITCODE -ne 0) {
    throw "C++ build failed with exit code $LASTEXITCODE"
}

Write-Host "Built $executable"
if ($RunSelfTest) {
    & $executable --self-test
    if ($LASTEXITCODE -ne 0) {
        throw "Self-test failed with exit code $LASTEXITCODE"
    }
}
