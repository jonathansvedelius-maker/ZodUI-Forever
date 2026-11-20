# Builds one zip per addon for a release, with the same files deploy.ps1 ships: the .toc, every file it lists,
# Bindings.xml and Media\. Each zip holds one folder named after the addon, so it is unpacked straight into
# Interface\AddOns. The zips go in .\releases\<Addon>-<version>.zip; upload them to the repo's GitHub release.
#
#   .\ZodUI\tools\release.ps1                 every addon
#   .\ZodUI\tools\release.ps1 UndeadRoute     one

param(
    [string[]]$Addon = @('ZodUI', 'UndeadRoute')
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

$outDir = Join-Path $Root 'releases'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

foreach ($name in $Addon) {
    $src = Join-Path $Root $name
    if (-not (Test-Path (Join-Path $src "$name.toc"))) {
        Write-Host "${name}: no $name.toc in $src, skipped." -ForegroundColor Yellow
        $failed = $true
        continue
    }
    $files = Shipped $src $name
    $missing = @($files | Where-Object { -not (Test-Path (Join-Path $src $_)) })
    if ($missing.Count -gt 0) {
        Write-Host "${name}: the .toc lists files that do not exist: $($missing -join ', '). No zip made." -ForegroundColor Red
        $failed = $true
        continue
    }
    # Never ship a file built from other addons' data.
    if ($files -contains 'Generated.lua') {
        Write-Host "${name}: the .toc lists Generated.lua, which must not be shared. No zip made." -ForegroundColor Red
        $failed = $true
        continue
    }
    $version = (Select-String -Path (Join-Path $src "$name.toc") -Pattern '^## Version:\s*(.+)$').Matches.Groups[1].Value.Trim()
    $zip = Join-Path $outDir "$name-$version.zip"
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
    # Entries named with forward slashes (Compress-Archive on Windows PowerShell writes backslashes, which some
    # unzip tools turn into flat file names).
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        foreach ($f in $files) {
            $entry = "$name/" + ($f -replace '\\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $src $f), $entry) | Out-Null
        }
    } finally { $archive.Dispose() }
    Write-Host ("{0} {1}: {2} files -> {3}" -f $name, $version, $files.Count, $zip) -ForegroundColor Green
}

if ($failed) { exit 1 }
