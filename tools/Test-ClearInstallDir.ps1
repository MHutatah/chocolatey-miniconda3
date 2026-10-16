# Regression test for the upgrade path that destroyed a working installation
# three times: 2026-09-13 (deadline expired mid-uninstall, then threw),
# 2026-10-06 (single Remove-Item lost the race, failure discarded, installer
# then refused a non-empty directory) and 2026-10-16 (hung _conda.exe helpers
# held the directory for the full 15 minutes). Excluded from the nupkg.
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
    # Test-PathInside decides which processes get terminated, so a loose match
    # here means killing processes from an unrelated directory.
    Write-Host 'Test-PathInside'
    Assert (Test-PathInside -Candidate 'C:\tools\miniconda3\_conda.exe' -Directory 'C:\tools\miniconda3') 'matches a file inside the directory'
    Assert (Test-PathInside -Candidate 'C:\tools\miniconda3\Scripts\conda.exe' -Directory 'C:\tools\miniconda3') 'matches a file nested deeper'
    Assert (Test-PathInside -Candidate 'C:\TOOLS\MiniConda3\_conda.exe' -Directory 'C:\tools\miniconda3') 'is case insensitive, as Windows paths are'
    Assert (Test-PathInside -Candidate 'C:\tools\miniconda3\_conda.exe' -Directory 'C:\tools\miniconda3\') 'tolerates a trailing separator on the directory'
    Assert (-not (Test-PathInside -Candidate 'C:\tools\miniconda3-backup\_conda.exe' -Directory 'C:\tools\miniconda3')) 'does NOT match a sibling with the same prefix'
    Assert (-not (Test-PathInside -Candidate 'C:\tools\miniconda3' -Directory 'C:\tools\miniconda3')) 'does NOT match the directory itself'
    Assert (-not (Test-PathInside -Candidate 'C:\Windows\System32\cmd.exe' -Directory 'C:\tools\miniconda3')) 'does not match an unrelated path'
    Assert (-not (Test-PathInside -Candidate $null -Directory 'C:\tools\miniconda3')) 'treats a null path as outside (a protected process reads as null)'
    Assert (-not (Test-PathInside -Candidate '' -Directory 'C:\tools\miniconda3')) 'treats an empty path as outside'

    Write-Host 'Get-ProcessInside'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Assert (@(Get-ProcessInside -Directory $root).Count -eq 0) 'finds nothing in an empty directory'
    # This test host runs from System32, so it must never be selected.
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    Assert (@(Get-ProcessInside -Directory $root | Where-Object { $_.Id -eq $self.Id }).Count -eq 0) 'does not select the current process'
    Assert (@(Get-ProcessInside -Directory (Split-Path -Parent $self.Path) | Where-Object { $_.Id -eq $self.Id }).Count -eq 1) 'does select a process whose exe is inside the directory'

    Write-Host 'Clear-InstallDir'
    # The ordinary case: residue the uninstaller never tracked, nothing locked.
    New-Item -ItemType Directory -Path (Join-Path $root 'tcl') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'tcl\leftover.txt') -Value 'untracked residue'
    Assert (Clear-InstallDir -Path $root -RetrySeconds 0) 'clears a populated directory'
    Assert (-not (Test-Path -LiteralPath $root)) 'the directory is gone afterwards'

    # 2026-10-06: a file still held open. The old code called Remove-Item once
    # with -ErrorAction SilentlyContinue and carried on as if it had worked, so
    # this has to report failure, not success.
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $locked = Join-Path $root 'python.exe'
    Set-Content -LiteralPath $locked -Value 'x'
    $handle = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
    try {
        Assert (-not (Clear-InstallDir -Path $root -TimeoutMinutes 0 -RetrySeconds 0 -GraceSeconds 3600)) 'reports failure while a file is locked'
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
