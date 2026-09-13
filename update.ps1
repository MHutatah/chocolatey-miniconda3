#requires -Version 5.1
# Automated updater for the miniconda3 Chocolatey package.
#
# Resolves the newest Miniconda3 Windows x86_64 installer from the
# repo.anaconda.com index and reads its SHA256 straight from that index, so
# nothing has to download a 124 MB installer to checksum it. It rewrites the
# package files, packs, and with -Push also publishes.
#
# Anaconda publishes one installer per Python series (py310 through py314 at the
# time of writing) rather than a single "latest", so the package follows one
# series deliberately. -PythonSeries moves it.
#
#   .\update.ps1                       # update + pack only
#   .\update.ps1 -Push                 # update + pack + push (needs CHOCO_API_KEY)
#   .\update.ps1 -ResolveOnly          # just show what upstream is offering
#   .\update.ps1 -PythonSeries py314   # track a different Python series

[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$ResolveOnly,
    [ValidatePattern('^py3\d+$')]
    [string]$PythonSeries = 'py313',
    [string]$ApiKey     = $env:CHOCO_API_KEY,
    [string]$PushSource = 'https://push.chocolatey.org/'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$nuspecPath  = Join-Path $PSScriptRoot 'miniconda3.nuspec'
$installPath = Join-Path $PSScriptRoot 'tools\chocolateyinstall.ps1'
$verifyPath  = Join-Path $PSScriptRoot 'tools\VERIFICATION.txt'

$indexUrl = 'https://repo.anaconda.com/miniconda/'

function Save-XmlNoBom([xml]$Xml, [string]$Path) {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.OmitXmlDeclaration = $false

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Xml.Save($writer) } finally { $writer.Close() }
}

function Resolve-MinicondaRelease {
    param([string]$Series)

    # The index is a plain table, one <tr> per file: name, size, date, sha256.
    # Splitting on the row tag keeps a row with a missing checksum from silently
    # pairing a filename with the next row's hash.
    $html = (Invoke-WebRequest -Uri $indexUrl -UseBasicParsing -TimeoutSec 120).Content
    $namePattern = '<a href="(Miniconda3-' + $Series + '_(\d+(?:\.\d+)+)-(\d+)-Windows-x86_64\.exe)">'

    $builds = foreach ($row in ($html -split '<tr>')) {
        $name = [regex]::Match($row, $namePattern)
        if (-not $name.Success) { continue }
        $sha = [regex]::Match($row, '<td>([0-9a-fA-F]{64})</td>')
        if (-not $sha.Success) { throw "No SHA256 in the index row for $($name.Groups[1].Value)." }

        [pscustomobject]@{
            File    = $name.Groups[1].Value
            # Upstream numbers a release "<conda version>-<build>", e.g. 26.7.1-1.
            # That cannot go into a nuspec unchanged, because "-1" parses as a
            # NuGet prerelease tag and sorts BELOW 26.7.1, which would break
            # upgrade ordering. The build becomes a fourth version part instead.
            Version = [version]"$($name.Groups[2].Value).$($name.Groups[3].Value)"
            Sha256  = $sha.Groups[1].Value.ToLower()
        }
    }

    if (-not $builds) { throw "No Windows x86_64 builds found for series '$Series' at $indexUrl." }

    $latest = $builds | Sort-Object Version | Select-Object -Last 1
    [pscustomobject]@{
        Version = $latest.Version.ToString()
        Url     = "$indexUrl$($latest.File)"
        Sha256  = $latest.Sha256
        File    = $latest.File
        Series  = $Series
    }
}

$rel = Resolve-MinicondaRelease -Series $PythonSeries

if ($ResolveOnly) { return $rel }   # returned, not formatted, so callers can assert on it

$nuspec  = [xml](Get-Content $nuspecPath -Raw)
$current = $nuspec.package.metadata.version
Write-Host "Current package version: $current   upstream latest ($PythonSeries): $($rel.Version)"
if ([version]$rel.Version -le [version]$current) {
    Write-Host "Already up to date; nothing to do."
    return
}

# Parse the current URL + checksum from the install script so replacement is exact.
$installText = Get-Content $installPath -Raw
$oldUrl = [regex]::Match($installText, "url64\s*=\s*'([^']+\.exe)'").Groups[1].Value
$oldSha = [regex]::Match($installText, "checksum64\s*=\s*'([0-9a-fA-F]{64})'").Groups[1].Value
if (-not ($oldUrl -and $oldSha)) { throw "Could not parse the current URL/checksum from chocolateyinstall.ps1." }

foreach ($path in $installPath, $verifyPath) {
    $t = Get-Content $path -Raw
    $t = $t.Replace($oldUrl, $rel.Url).Replace($oldSha, $rel.Sha256)
    Set-Content -Path $path -Value $t -Encoding Ascii -NoNewline
}

$nuspec.package.metadata.version = $rel.Version
Save-XmlNoBom $nuspec $nuspecPath
Write-Host "Updated nuspec, chocolateyinstall.ps1, and VERIFICATION.txt to $($rel.Version)."

Write-Host "Packing..."
& choco pack $nuspecPath --out $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "choco pack failed." }

if ($Push) {
    if (-not $ApiKey) { throw "No API key. Pass -ApiKey or set CHOCO_API_KEY." }
    $nupkg = Join-Path $PSScriptRoot "miniconda3.$($rel.Version).nupkg"
    Write-Host "Pushing $nupkg ..."
    & choco push $nupkg --source $PushSource --api-key $ApiKey
    if ($LASTEXITCODE -ne 0) { throw "choco push failed." }
    Write-Host "Pushed miniconda3 $($rel.Version). It now enters Chocolatey moderation."
} else {
    Write-Host "Done. Built miniconda3.$($rel.Version).nupkg (run with -Push to publish)."
}
