# Regression test for the upgrade path that destroyed a working installation
# twice: 2026-09-13 (deadline expired mid-uninstall, then threw) and 2026-10-06
# (single Remove-Item lost the race, failure discarded, installer then refused a
# non-empty directory). Excluded from the nupkg by the nuspec.
#
# Run: powershell -NoProfile -File tools\Test-ClearInstallDir.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Clear-InstallDir.ps1')

$fails = 0
function Assert([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Host "  ok    $Message" }
    else { Write-Host "  FAIL  $Message"; $script:fails++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('clear-installdir-' + [guid]::NewGuid().ToString('n'))

try {
    Write-Host 'Clear-InstallDir'

    # The ordinary case: residue the uninstaller never tracked, nothing locked.
    New-Item -ItemType Directory -Path (Join-Path $root 'tcl') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'tcl\leftover.txt') -Value 'untracked residue'
    Assert (Clear-InstallDir -Path $root -RetrySeconds 0) 'clears a populated directory'
    Assert (-not (Test-Path -LiteralPath $root)) 'the directory is gone afterwards'

    # The case that shipped broken: a file still held open. The old code called
    # Remove-Item once with -ErrorAction SilentlyContinue and carried on as if
    # it had worked, so this has to report failure, not success.
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $locked = Join-Path $root 'python.exe'
    Set-Content -LiteralPath $locked -Value 'x'
    $handle = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
    try {
        Assert (-not (Clear-InstallDir -Path $root -TimeoutMinutes 0 -RetrySeconds 0)) 'reports failure while a file is locked'
        Assert (Test-Path -LiteralPath $root) 'leaves the directory in place to report on'
    }
    finally { $handle.Close() }

    # Same call, lock released: this is the retry the fix adds.
    Assert (Clear-InstallDir -Path $root -RetrySeconds 0) 'succeeds once the lock is released'
    Assert (-not (Test-Path -LiteralPath $root)) 'the directory is gone after the lock is released'

    # A fresh install has no directory to clear. That is success, not an error.
    Assert (Clear-InstallDir -Path (Join-Path $root 'never-existed') -RetrySeconds 0) 'treats a missing directory as cleared'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fails) {
    Write-Host ''
    Write-Host "$fails check(s) failed."
    exit 1
}
Write-Host ''
Write-Host 'All checks passed.'
