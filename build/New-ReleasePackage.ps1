#requires -Version 7.0
<#
.SYNOPSIS
    Builds the release zip: only the files a user needs, inside a "TogKey Display" folder, plus a SHA-256 file.
.PARAMETER ExpectedVersion
    A release tag such as v1.2.0. The build fails unless it matches the version in TogKey Core.psm1.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$ExpectedVersion
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'TogKey Core.psm1') -Force
$version = Get-TogKeyVersion
if ($version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw "Version '$version' in TogKey Core.psm1 is not semantic (X.Y.Z)." }
if ($ExpectedVersion -and (($ExpectedVersion -replace '^v', '') -ne $version)) {
    throw "Tag '$ExpectedVersion' does not match version '$version' in TogKey Core.psm1. Update the version or the tag."
}

# Allow-list, so labels, preferences, .vil exports, tests and CI files can never be shipped by accident.
$files = @('Start TogKey Display.cmd', 'TogKey Display.ps1', 'TogKey Core.psm1', 'TogKey Hid.cs', 'README.md', 'LICENSE')
$staging = Join-Path ([IO.Path]::GetTempPath()) ('togkey-package-' + [guid]::NewGuid().ToString('N'))
$folder = Join-Path $staging 'TogKey Display'
try {
    [void](New-Item -ItemType Directory -Force -Path $folder)
    foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $folder }
    [void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
    $zip = Join-Path (Resolve-Path $OutputDirectory) "TogKey-Display-v$version.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($folder, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$hashFile = "$zip.sha256"
Set-Content -LiteralPath $hashFile -Value "$hash  $([IO.Path]::GetFileName($zip))" -NoNewline

[pscustomobject]@{ Version = $version; Package = $zip; Sha256 = $hash; HashFile = $hashFile }
