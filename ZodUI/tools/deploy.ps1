# Copies each addon's shipped files into the game's AddOns folder.
# Shipped = the .toc, every file the .toc lists, Bindings.xml if there is one, and everything under Media\ (textures).
# Files in the game folder that are no longer shipped are removed, so it mirrors the repo.
#
#   .\ZodUI\tools\deploy.ps1                 deploy every addon
#   .\ZodUI\tools\deploy.ps1 ZodUI           deploy one
#   .\ZodUI\tools\deploy.ps1 -WhatIf         show what would change
#
# Then /reload in the game. A file newly added to a .toc needs a full game restart.

param(
    [string[]]$Addon = @('ZodUI', 'UndeadRoute'),
    [string]$AddOns = 'C:\Games\World of Warcraft\_forever_\Interface\AddOns',
    [switch]$WhatIf
)

# The folder that holds the addon repos (ZodUI, UndeadRoute): two up from this script, in ZodUI\tools.
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$ErrorActionPreference = 'Stop'
$failed = $false

function Shipped($src, $name) {
    $toc = Join-Path $src "$name.toc"
    $files = @("$name.toc")
    foreach ($line in Get-Content $toc) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $files += ($line -replace '/', '\')
    }
    if (Test-Path (Join-Path $src 'Bindings.xml')) { $files += 'Bindings.xml' }
    $media = Join-Path $src 'Media'
    if (Test-Path $media) {
        foreach ($f in Get-ChildItem -LiteralPath $media -Recurse -File) { $files += $f.FullName.Substring($src.Length + 1) }
    }
    return $files
}

function Same($a, $b) {
    if (-not (Test-Path $b)) { return $false }
    if ((Get-Item $a).Length -ne (Get-Item $b).Length) { return $false }
    return (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash
}

foreach ($name in $Addon) {
    $src = Join-Path $Root $name
    $dest = Join-Path $AddOns $name
    if (-not (Test-Path (Join-Path $src "$name.toc"))) {
        Write-Host "${name}: no $name.toc in $src, skipped." -ForegroundColor Yellow
        $failed = $true
        continue
    }
    if (Test-Path (Join-Path $dest '.git')) {
        Write-Host "${name}: $dest is a git repo, not a deployed copy. Move it away first; nothing was changed." -ForegroundColor Red
        $failed = $true
        continue
    }

    $files = Shipped $src $name
    $missing = @($files | Where-Object { -not (Test-Path (Join-Path $src $_)) })
    if ($missing.Count -gt 0) {
        Write-Host "${name}: the .toc lists files that do not exist: $($missing -join ', '). Nothing was changed." -ForegroundColor Red
        $failed = $true
        continue
    }

    $copied, $removed = 0, 0
    foreach ($f in $files) {
        $from = Join-Path $src $f
        $to = Join-Path $dest $f
        if (Same $from $to) { continue }
        $copied++
        if ($WhatIf) { Write-Host "  would copy $f"; continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }

    if (Test-Path $dest) {
        $keep = @{}
        foreach ($f in $files) { $keep[(Join-Path $dest $f).ToLower()] = $true }
        foreach ($old in Get-ChildItem -LiteralPath $dest -Recurse -File) {
            if ($keep.ContainsKey($old.FullName.ToLower())) { continue }
            $removed++
            if ($WhatIf) { Write-Host "  would remove $($old.FullName.Substring($dest.Length + 1))"; continue }
            Remove-Item -LiteralPath $old.FullName -Force
        }
        if (-not $WhatIf) {
            Get-ChildItem -LiteralPath $dest -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item -Force
        }
    }

    $version = (Select-String -Path (Join-Path $src "$name.toc") -Pattern '^## Version:\s*(.+)$').Matches.Groups[1].Value
    Write-Host ("{0} {1}: {2} files, {3} copied, {4} removed{5}" -f $name, $version, $files.Count, $copied, $removed,
        $(if ($WhatIf) { ' (dry run)' } else { '' })) -ForegroundColor Green
}

if ($failed) { exit 1 }
