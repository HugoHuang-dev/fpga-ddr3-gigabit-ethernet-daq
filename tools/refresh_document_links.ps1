param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$versionsRoot = Join-Path $projectRoot 'versions'
$allFiles = @(Get-ChildItem -LiteralPath $versionsRoot -Recurse -File)
$markdownFiles = @($allFiles | Where-Object Extension -eq '.md')
$byName = @{}
foreach ($file in $allFiles) {
    $key = $file.Name.ToLowerInvariant()
    if (-not $byName.ContainsKey($key)) { $byName[$key] = [System.Collections.Generic.List[string]]::new() }
    $byName[$key].Add($file.FullName)
}

function Resolve-DocumentAsset([string]$document, [string]$token) {
    $parent = Split-Path -Parent $document
    $tokenPath = $token.Replace('/', [IO.Path]::DirectorySeparatorChar).Replace('\', [IO.Path]::DirectorySeparatorChar)
    if ($tokenPath -match '^[A-Za-z]:') { return $null }
    for ($depth = 0; $depth -le 3; $depth++) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $parent $tokenPath))
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and $candidate -ne $document) { return $candidate }
        $parent = Split-Path -Parent $parent
    }
    $key = [IO.Path]::GetFileName($tokenPath).ToLowerInvariant()
    if (-not $byName.ContainsKey($key)) { return $null }
    $choices = @($byName[$key] | Where-Object { $_ -notmatch '\\build\\' })
    if ($tokenPath.Contains([IO.Path]::DirectorySeparatorChar)) {
        $suffixMatches = @($choices | Where-Object { $_.EndsWith($tokenPath, [StringComparison]::OrdinalIgnoreCase) })
        if ($suffixMatches.Count -eq 1 -and $suffixMatches[0] -ne $document) { return $suffixMatches[0] }
    }
    if ($choices.Count -eq 1 -and $choices[0] -ne $document) { return $choices[0] }
    $versionMatch = [regex]::Match($document, 'project2_v[1-9][^\\]*')
    if ($versionMatch.Success) {
        $sameVersion = @($choices | Where-Object { $_ -like "*$($versionMatch.Value)*" })
        if ($sameVersion.Count -eq 1 -and $sameVersion[0] -ne $document) { return $sameVersion[0] }
    }
    return $null
}

$converted = 0
$unresolved = [System.Collections.Generic.HashSet[string]]::new()
$tokenPattern = '(?<!\[)`(?<token>[^`\r\n]+?\.(?:png|jpg|jpeg|json|txt|md|xdc|bit|ltx|ila|csv|rpt|log|xpr|tcl|py|v|sv|exe))`(?!\]\()'
foreach ($document in $markdownFiles) {
    $lines = [IO.File]::ReadAllLines($document.FullName, [Text.Encoding]::UTF8)
    $insideFence = $false
    $changed = $false
    for ($lineNumber = 0; $lineNumber -lt $lines.Length; $lineNumber++) {
        $line = $lines[$lineNumber]
        if ($line.TrimStart() -match '^(```|~~~)') { $insideFence = -not $insideFence; continue }
        if ($insideFence) { continue }
        $newLine = [regex]::Replace($line, $tokenPattern, {
            param($match)
            $token = $match.Groups['token'].Value
            $asset = Resolve-DocumentAsset $document.FullName $token
            if (-not $asset) {
                [void]$unresolved.Add($token)
                return $match.Value
            }
            $relative = [IO.Path]::GetRelativePath((Split-Path -Parent $document.FullName), $asset).Replace('\', '/')
            $script:converted++
            return '[`' + $token + '`](' + $relative + ')'
        })
        if ($newLine -ne $line) { $lines[$lineNumber] = $newLine; $changed = $true }
    }
    if ($changed -and $Apply) { [IO.File]::WriteAllLines($document.FullName, $lines, [Text.UTF8Encoding]::new($false)) }
}

Write-Output "Inline file references convertible: $converted"
Write-Output "Unique unresolved tokens: $($unresolved.Count)"
if ($unresolved.Count -gt 0) { $unresolved | Sort-Object | ForEach-Object { Write-Output "UNRESOLVED: $_" } }
if (-not $Apply) { exit 0 }

$versionPaths = @{
    1 = @('v1_v5/project2_v1_udp')
    2 = @('v1_v5/project2_v2_stream')
    3 = @('v1_v5/project2_v3_ddr3')
    4 = @('v1_v5/project2_v4_ddr3_udp')
    5 = @('v1_v5/project2_v5_ring_buffer', 'v5_v6/project2_v5_315m', 'v5_v6/project2_v5_400m', 'v5_v6/project2_v5_max_unpaced')
    6 = @('v5_v6/project2_v6_pipeline')
    7 = @('v7_v9/project2_v7_uart_control')
    8 = @('v7_v9/project2_v8_xadc_acquisition')
    9 = @('v7_v9/project2_v9_full_validation')
}

foreach ($kind in @('evidence', 'constraints')) {
    $indexRoot = Join-Path $projectRoot $kind
    [void](New-Item -ItemType Directory -Path $indexRoot -Force)
    $overview = @("# Project2 $(if ($kind -eq 'evidence') { '图像与波形证据' } else { '引脚与时序约束' })", '', '按版本浏览；文件来自相应工程，版本目录保留完整原始资料。', '')
    foreach ($number in 1..9) {
        $destDir = Join-Path $indexRoot "V$number"
        [void](New-Item -ItemType Directory -Path $destDir -Force)
        $sources = [System.Collections.Generic.List[IO.FileInfo]]::new()
        foreach ($relativeVersion in $versionPaths[$number]) {
            $sourceDir = Join-Path $versionsRoot ($relativeVersion.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $sourceDir)) { continue }
            foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -Recurse -File)) {
                if ($file.FullName -match '\\build\\|\\board_test_package\\|\\ip\\') { continue }
                if ($kind -eq 'evidence') {
                    if ($file.Extension.ToLowerInvariant() -notin @('.png', '.jpg', '.jpeg', '.ila')) { continue }
                    if ($file.FullName -notmatch '\\evidence\\' -and $file.Extension.ToLowerInvariant() -ne '.ila') { continue }
                } else {
                    if ($file.Extension.ToLowerInvariant() -ne '.xdc' -or $file.FullName -notmatch '\\constraints\\') { continue }
                }
                $sources.Add($file)
            }
        }
        if ($number -in @(5, 6) -and $kind -eq 'evidence') {
            $extra = Join-Path $versionsRoot 'v5_v6/evidence'
            foreach ($file in (Get-ChildItem -LiteralPath $extra -File)) {
                if ($file.Extension.ToLowerInvariant() -notin @('.png', '.jpg', '.jpeg')) { continue }
                if ($number -eq 5 -and $file.Name -match '^(ila_400m|max_|host_|315m_|400m_|development_pc_)') { $sources.Add($file) }
                if ($number -eq 6 -and $file.Name -match '^(ila_v6_|v6_)') { $sources.Add($file) }
            }
        }
        $items = @("# V$number $(if ($kind -eq 'evidence') { '图像与波形证据' } else { '引脚与时序约束' })", '', "[返回总览](README.md)", '')
        $used = @{}
        foreach ($source in ($sources | Sort-Object FullName -Unique)) {
            $name = $source.Name
            if ($used.ContainsKey($name.ToLowerInvariant())) {
                $prefix = Split-Path -Leaf (Split-Path -Parent $source.DirectoryName)
                $name = $prefix + '_' + $name
            }
            $used[$name.ToLowerInvariant()] = $true
            $destination = Join-Path $destDir $name
            Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
            $origin = [IO.Path]::GetRelativePath($versionsRoot, $source.FullName).Replace('\', '/')
            $items += ('- [{0}](V{1}/{0}) — `versions/{2}`' -f $name, $number, $origin)
        }
        if ($sources.Count -eq 0) { $items += '本版没有独立归档的此类文件。' }
        [IO.File]::WriteAllLines((Join-Path $indexRoot "V$number.md"), $items, [Text.UTF8Encoding]::new($false))
        $overview += "- [V$number](V$number.md)（$($sources.Count) 项）"
    }
    [IO.File]::WriteAllLines((Join-Path $indexRoot 'README.md'), $overview, [Text.UTF8Encoding]::new($false))
}
