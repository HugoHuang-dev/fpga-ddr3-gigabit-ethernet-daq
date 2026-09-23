param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$versionsRoot = Join-Path $ProjectRoot 'versions'
$versionInfo = @(
    @{ Group='v1_v5'; Name='project2_v1_udp'; Created='2026-07-19'; Revised='2026-09-19' },
    @{ Group='v1_v5'; Name='project2_v2_stream'; Created='2026-07-22'; Revised='2026-09-19' },
    @{ Group='v1_v5'; Name='project2_v3_ddr3'; Created='2026-07-26'; Revised='2026-09-19' },
    @{ Group='v1_v5'; Name='project2_v4_ddr3_udp'; Created='2026-08-02'; Revised='2026-09-20' },
    @{ Group='v1_v5'; Name='project2_v5_ring_buffer'; Created='2026-08-11'; Revised='2026-09-20' },
    @{ Group='v5_v6'; Name='project2_v5_225m_diagnostic'; Created='2026-08-11'; Revised='2026-09-21' },
    @{ Group='v5_v6'; Name='project2_v5_250m_diagnostic'; Created='2026-08-11'; Revised='2026-09-21' },
    @{ Group='v5_v6'; Name='project2_v5_315m'; Created='2026-08-11'; Revised='2026-09-21' },
    @{ Group='v5_v6'; Name='project2_v5_400m'; Created='2026-08-11'; Revised='2026-09-22' },
    @{ Group='v5_v6'; Name='project2_v5_max_unpaced'; Created='2026-08-11'; Revised='2026-09-22' },
    @{ Group='v5_v6'; Name='project2_v6_pipeline'; Created='2026-08-25'; Revised='2026-09-22' },
    @{ Group='v7_v9'; Name='project2_v7_uart_control'; Created='2026-09-02'; Revised='2026-09-22' },
    @{ Group='v7_v9'; Name='project2_v8_xadc_acquisition'; Created='2026-09-08'; Revised='2026-09-22' },
    @{ Group='v7_v9'; Name='project2_v9_full_validation'; Created='2026-09-14'; Revised='2026-09-23' }
)

$firstCreated = @{}
foreach ($v in $versionInfo) {
    $base = Join-Path (Join-Path $versionsRoot $v.Group) $v.Name
    foreach ($subdir in @('rtl', 'sim', 'constraints')) {
        $dir = Join-Path $base $subdir
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -File) {
            if ($f.Extension -notin @('.v', '.sv', '.xdc')) { continue }
            if (-not $firstCreated.ContainsKey($f.Name)) { $firstCreated[$f.Name] = $v.Created }
        }
    }
}

$excludeRtl = @('crc16_d8.v', 'uart_dma.v', 'uart_rx.v', 'uart_tx.v', 'xadc_multichannel.v')
$ascii = [System.Text.Encoding]::ASCII
$latin1 = [System.Text.Encoding]::Latin1
$sha = [System.Security.Cryptography.SHA256]::Create()
$rows = [System.Collections.Generic.List[object]]::new()
$projectTitle = 'FPGA DDR3-Buffered Data Acquisition and Gigabit Ethernet Transmission System'

foreach ($v in $versionInfo) {
    $base = Join-Path (Join-Path $versionsRoot $v.Group) $v.Name
    foreach ($subdir in @('rtl', 'sim', 'scripts', 'constraints')) {
        $dir = Join-Path $base $subdir
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $dir -File) {
            if ($subdir -in @('rtl', 'sim') -and $file.Extension -notin @('.v', '.sv')) { continue }
            if ($subdir -eq 'scripts' -and $file.Extension -ne '.tcl') { continue }
            if ($subdir -eq 'constraints' -and $file.Extension -ne '.xdc') { continue }
            if ($subdir -eq 'rtl' -and $file.Name -in $excludeRtl) { continue }

            $original = [System.IO.File]::ReadAllBytes($file.FullName)
            $bomSize = 0
            if ($original.Length -ge 3 -and $original[0] -eq 0xEF -and $original[1] -eq 0xBB -and $original[2] -eq 0xBF) { $bomSize = 3 }
            $body = $latin1.GetString($original, $bomSize, $original.Length - $bomSize)
            if ($body.StartsWith('// -----------------------------------------------------------------------------') -or $body.StartsWith('# -----------------------------------------------------------------------------')) { continue }

            $marker = if ($file.Extension -in @('.tcl', '.xdc')) { '#' } else { '//' }
            $moduleName = if ($file.Extension -eq '.tcl') { 'Vivado build script' } elseif ($file.Extension -eq '.xdc') { 'Vivado constraints' } else {
                $match = [regex]::Match($body, '(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)')
                if (-not $match.Success) { throw "Cannot identify module: $($file.FullName)" }
                $match.Groups[1].Value
            }
            $created = if ($subdir -eq 'scripts') { $v.Created } else { $firstCreated[$file.Name] }
            $newline = if ($body.Contains("`r`n")) { "`r`n" } else { "`n" }
            $sep = "$marker -----------------------------------------------------------------------------"
            $header = @(
                $sep,
                "$marker Hugo's FPGA Project",
                $sep,
                "$marker Author  : sunmingyin.huang@haw-hamburg.de",
                "$marker Project : $projectTitle",
                "$marker File    : $($file.Name)",
                "$marker Module  : $moduleName",
                "$marker Created : $created",
                "$marker Revised : $($v.Revised)",
                "$marker Editor  : Sublime Text 3 (Build 3211), Tab Size (4)",
                $sep,
                ''
            ) -join $newline
            $prefix = $ascii.GetBytes($header)
            $output = New-Object byte[] ($original.Length + $prefix.Length)
            if ($bomSize -gt 0) { [System.Array]::Copy($original, 0, $output, 0, $bomSize) }
            [System.Array]::Copy($prefix, 0, $output, $bomSize, $prefix.Length)
            [System.Array]::Copy($original, $bomSize, $output, $bomSize + $prefix.Length, $original.Length - $bomSize)
            $originalHash = [System.Convert]::ToHexString($sha.ComputeHash($original)).ToLowerInvariant()
            [System.IO.File]::WriteAllBytes($file.FullName, $output)
            $updatedHash = [System.Convert]::ToHexString($sha.ComputeHash($output)).ToLowerInvariant()
            $relativePath = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\') -replace '\\','/'
            $rows.Add([pscustomobject]@{
                path = $relativePath
                original_sha256 = $originalHash
                headered_sha256 = $updatedHash
                inserted_bytes = $prefix.Length
                original_body_preserved = $true
            })
        }
    }
}

$manifest = Join-Path $ProjectRoot 'tools\source_header_manifest.csv'
$previous = if (Test-Path -LiteralPath $manifest) { @(Import-Csv -LiteralPath $manifest) } else { @() }
$allRows = @($previous) + @($rows)
if ($allRows.Count -gt 0) {
    $allRows | Sort-Object path -Unique | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding utf8
}
$v9 = Join-Path $versionsRoot 'v7_v9\project2_v9_full_validation'
foreach ($subdir in @('rtl', 'sim', 'scripts', 'constraints')) {
    Get-ChildItem -LiteralPath (Join-Path $v9 $subdir) -File |
        Copy-Item -Destination (Join-Path $ProjectRoot $subdir) -Force
}
Write-Output "Headered files: $($rows.Count)"
Write-Output "Manifest: $manifest"
