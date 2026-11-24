# Builds the release zips, commits + pushes, and publishes GitHub release v<VERSION>.
# Usage (from the project folder):  powershell -ExecutionPolicy Bypass -File tools\release.ps1
param([string]$Notes = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$src = Get-Content "game\scripts\updater.gd" -Raw
if ($src -notmatch 'const VERSION := "([0-9.]+)"') { throw "VERSION not found in updater.gd" }
$version = $Matches[1]
$tag = "v$version"
Write-Host "Releasing $tag"

$existing = gh release view $tag --json tagName 2>$null
if ($LASTEXITCODE -eq 0 -and $existing) { throw "Release $tag already exists - bump VERSION in game/scripts/updater.gd first" }

# zip entries need forward slashes (Compress-Archive in PowerShell 5 writes backslashes)
function New-Zip([string]$zipPath, [array]$items) {
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, "Create")
    try {
        foreach ($it in $items) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $it.Full, $it.Entry, "Optimal") | Out-Null
        }
    } finally { $zip.Dispose() }
}

function Get-Files([string]$dir, [string]$prefix) {
    $base = (Resolve-Path $dir).Path.TrimEnd('\') + '\'
    Get-ChildItem $dir -Recurse -File | Where-Object { $_.FullName -notlike "*\.godot\*" } | ForEach-Object {
        [pscustomobject]@{ Full = $_.FullName; Entry = $prefix + $_.FullName.Substring($base.Length).Replace('\', '/') }
    }
}

New-Item -ItemType Directory -Force dist | Out-Null
$game = @(Get-Files "game" "")
New-Zip "dist\game-update.zip" $game

$full = @(Get-Files "game" "ForestDrift/game/")
$full += [pscustomobject]@{ Full = (Resolve-Path "play.bat").Path; Entry = "ForestDrift/play.bat" }
$full += [pscustomobject]@{ Full = (Resolve-Path "README.md").Path; Entry = "ForestDrift/README.md" }
foreach ($exe in Get-ChildItem "tools\godot\*.exe") {
    $full += [pscustomobject]@{ Full = $exe.FullName; Entry = "ForestDrift/tools/godot/" + $exe.Name }
}
New-Zip "dist\ForestDrift-windows.zip" $full
Write-Host ("Built dist\game-update.zip ({0:N1} MB) and dist\ForestDrift-windows.zip ({1:N1} MB)" -f `
    ((Get-Item dist\game-update.zip).Length / 1MB), ((Get-Item dist\ForestDrift-windows.zip).Length / 1MB))

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { git commit -m "Release $tag" }
git push
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

if ($Notes -eq "") { $Notes = "Forest Drift $tag. New players: download ForestDrift-windows.zip, unzip, run play.bat. Existing players: use the Update button on the start screen." }
gh release create $tag "dist\ForestDrift-windows.zip" "dist\game-update.zip" --title "Forest Drift $tag" --notes $Notes
if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
Write-Host "Published $tag"
