#requires -Version 5.1
# Checks for Resolve-MinicondaRelease in update.ps1, run against the live
# repo.anaconda.com index.
#
# Anaconda publishes per Python series and numbers releases "<version>-<build>",
# so these assert the properties that must hold whatever Anaconda ships next,
# rather than pinning today's version numbers.
#
#   pwsh -File tools/Test-ResolveRelease.ps1

$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$update = Join-Path $root 'update.ps1'

$fail = 0
function Check($label, $ok, $detail) {
    if (-not $ok) { $script:fail++ }
    "{0,-52} {1}  {2}" -f $label, $(if ($ok) { 'PASS' } else { 'FAIL' }), $detail
}

$r = & $update -ResolveOnly 3>$null

# 1. Shape. The fourth version part is the upstream build number, and it is the
#    whole reason this package does not use upstream's version string verbatim.
Check 'version is four parts'        ($r.Version -match '^\d+\.\d+\.\d+\.\d+$') $r.Version
Check 'checksum looks like a SHA256' ($r.Sha256 -match '^[0-9a-f]{64}$')        ''
Check 'url is on repo.anaconda.com'  ($r.Url -like 'https://repo.anaconda.com/miniconda/*') ''
Check 'url is 64-bit Windows'        ($r.Url -like '*-Windows-x86_64.exe')      ''

# 2. The resolved file must actually be on the index, with that exact checksum.
#    This is the check that catches a resolver drifting onto a stale or wrong row.
$index = (Invoke-WebRequest -Uri 'https://repo.anaconda.com/miniconda/' -UseBasicParsing -TimeoutSec 120).Content
$row = ($index -split '<tr>') | Where-Object { $_ -match [regex]::Escape($r.File) } | Select-Object -First 1
Check 'resolved file is listed upstream' ($null -ne $row) $r.File
$published = if ($row) { [regex]::Match($row, '<td>([0-9a-fA-F]{64})</td>').Groups[1].Value } else { '' }
Check 'checksum matches the published one' ($published.ToLower() -eq $r.Sha256) ''

# 3. Nothing newer of the same series may exist, or the package silently stands
#    still while upstream moves.
$series = $r.Series
$all = [regex]::Matches($index, '<a href="Miniconda3-' + $series + '_(\d+(?:\.\d+)+)-(\d+)-Windows-x86_64\.exe">') |
    ForEach-Object { [version]"$($_.Groups[1].Value).$($_.Groups[2].Value)" } |
    Sort-Object
$newest = $all | Select-Object -Last 1
Check 'resolved version is the newest of its series' ([version]$r.Version -eq $newest) "newest=$newest"

# 4. The series switch has to actually change the answer, or the package would
#    track py313 forever no matter what the parameter says.
$alt = if ($series -eq 'py312') { 'py311' } else { 'py312' }
$other = & $update -ResolveOnly -PythonSeries $alt 3>$null
Check "-PythonSeries $alt resolves that series" ($other.Url -like "*_$alt`_*" -or $other.File -like "*$alt`_*") $other.File

if ($fail) { throw "$fail check(s) failed." }
"`nAll checks passed."
