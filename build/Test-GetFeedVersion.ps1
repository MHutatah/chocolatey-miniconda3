# Run: powershell -NoProfile -File build\Test-GetFeedVersion.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-FeedVersion.ps1')

$fails = 0
function Assert([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "  ok    $Message" }
    else { Write-Host "  FAIL  $Message"; $script:fails++ }
}
function AssertEq([string] $In, [string] $Expected) {
    $got = Get-FeedVersion -NuspecVersion $In
    Assert ($got -eq $Expected) "$In -> $Expected$(if ($got -ne $Expected) { " (got $got)" })"
}

Write-Host 'Get-FeedVersion'

# The case that broke the 2026-10-15 pack and the 2026-10-17 feed probe.
AssertEq '26.9.3.0'  '26.9.3'
# Upstream build 1 and above survive untouched, which is why this went unnoticed
# for a month: 26.7.1.1 needed no normalizing.
AssertEq '26.7.1.1'  '26.7.1.1'
AssertEq '26.9.3.10' '26.9.3.10'
# A zero in the third component is NOT dropped. NuGet keeps it.
AssertEq '4.12.0'    '4.12.0'
AssertEq '26.10.0.0' '26.10.0'
AssertEq '1.0.0.0'   '1.0.0'
# Not four parts: left alone.
AssertEq '26.9.3'    '26.9.3'
AssertEq '4.12'      '4.12'
# Tolerates padding, since this reads out of XML.
AssertEq ' 26.9.3.0 ' '26.9.3'

$threw = $false
try { Get-FeedVersion -NuspecVersion '  ' } catch { $threw = $true }
Assert $threw 'throws on an empty version rather than returning something unusable'

if ($fails) {
    Write-Host ''
    Write-Host "$fails check(s) failed."
    exit 1
}
Write-Host ''
Write-Host 'All checks passed.'
