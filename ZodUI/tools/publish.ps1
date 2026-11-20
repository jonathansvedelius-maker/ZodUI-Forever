# Publishes ZodUI and Undead Route to the public repo, with a clean history of its own: the committed state of each
# private repo (git archive HEAD) goes into one folder each, public-README.md becomes README.md, and it is committed
# under GitHub's no-reply address, so no private history or e-mail address goes public. Then it builds the zips
# (release.ps1) and makes a GitHub release with both.
#
#   .\ZodUI\tools\publish.ps1                 commit, push and release what is committed in both private repos
#   .\ZodUI\tools\publish.ps1 -NoRelease      commit and push only
#
# Only committed work is published: commit in ZodUI and UndeadRoute first.

param(
    [string]$Repo = 'ZodUI-Forever',
    [switch]$NoRelease
)

# The folder that holds the addon repos (ZodUI, UndeadRoute): two up from this script, in ZodUI\tools.
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$ErrorActionPreference = 'Stop'
$addons = @('ZodUI', 'UndeadRoute')
$work = Join-Path $Root "public\$Repo"

# Whether a gh command succeeds; its error text is not an error here (PowerShell 5 stops on a native command's stderr).
function Succeeds([scriptblock]$cmd) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $cmd *> $null; return $LASTEXITCODE -eq 0 } catch { return $false } finally { $ErrorActionPreference = $old }
}

$login = (gh api user --jq .login).Trim()
$id = (gh api user --jq .id).Trim()
$author = "$login"
$email = "$id+$login@users.noreply.github.com"

# The public repo, made the first time.
if (-not (Test-Path (Join-Path $work '.git'))) {
    if (-not (Succeeds { gh repo view "$login/$Repo" })) {
        gh repo create "$login/$Repo" --public --description "ZodUI and Undead Route: addons for WoW Forever" | Out-Null
    }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    git -C $work init -q -b main
    git -C $work remote add origin "https://github.com/$login/$Repo.git"
}
git -C $work config user.name $author
git -C $work config user.email $email

foreach ($name in $addons) {
    $src = Join-Path $Root $name
    if (git -C $src status --porcelain) { Write-Host "${name}: uncommitted changes are left out; only HEAD is published." -ForegroundColor Yellow }
    $dest = Join-Path $work $name
    if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $tar = Join-Path ([System.IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid()).tar"
    git -C $src archive --format=tar -o $tar HEAD
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $tar -C $dest # Windows' own tar: Git's reads C: as a host
    if ($LASTEXITCODE -ne 0) { throw "${name}: could not unpack its files." }
    Remove-Item -LiteralPath $tar
    # Never publish quest data built from other addons.
    if (Test-Path (Join-Path $dest 'Generated.lua')) { throw "${name}: Generated.lua is committed; it must not be published." }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public-README.md') -Destination (Join-Path $work 'README.md') -Force

$versions = foreach ($name in $addons) {
    $v = (Select-String -Path (Join-Path $Root "$name\$name.toc") -Pattern '^## Version:\s*(.+)$').Matches.Groups[1].Value.Trim()
    "$name $v"
}
$label = $versions -join ', '
git -C $work add -A
if (git -C $work status --porcelain) {
    git -C $work commit -q -m "$label"
    git -C $work push -q -u origin main
    Write-Host "pushed: $label" -ForegroundColor Green
} else {
    Write-Host "nothing changed since the last publish." -ForegroundColor Green
}

if ($NoRelease) { return }
$tag = ($versions -replace ' ', '-') -join '_'
if (Succeeds { gh release view $tag --repo "$login/$Repo" }) {
    Write-Host "release $tag already exists, no zips built: bump a version to make a new one." -ForegroundColor Yellow
    return
}
$global:LASTEXITCODE = 0 # the failed release check above left its code; release.ps1 sets 1 only when it fails
& (Join-Path $PSScriptRoot 'release.ps1') -Addon $addons
if ($LASTEXITCODE -ne 0) { throw "the zips could not be built; no release made." }
$zips = foreach ($v in $versions) { Join-Path $Root ("releases\" + ($v -replace ' ', '-') + ".zip") }
$notes = "Download both zips and unpack them into ``World of Warcraft\_forever_\Interface\AddOns``. See the README for what else to install.`n`n" + ($versions -join "`n")
gh release create $tag @zips --repo "$login/$Repo" --title $label --notes $notes --target main | Out-Null
Write-Host "released $tag" -ForegroundColor Green
