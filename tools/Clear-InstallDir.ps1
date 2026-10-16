# Dot-sourced by chocolateyinstall.ps1, and by Test-ClearInstallDir.ps1, so the
# one piece of logic that can destroy a working installation is directly
# testable rather than buried inline in the install script.

function Test-PathInside {
    <#
        True when $Candidate sits inside $Directory. Compares normalized paths
        with a trailing separator, so C:\tools\miniconda3-backup\x.exe does NOT
        count as inside C:\tools\miniconda3. Getting that wrong would mean
        terminating processes belonging to an unrelated directory.
    #>
    param([string] $Candidate, [Parameter(Mandatory)][string] $Directory)

    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    try {
        $prefix = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
        $full   = [System.IO.Path]::GetFullPath($Candidate)
    }
    catch { return $false }
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ProcessInside {
    <#
        Processes whose executable lives inside $Directory. Reading .Path throws
        for processes this account cannot open, so each one is guarded: a
        protected process is simply not ours and must not abort the enumeration.
    #>
    param([Parameter(Mandatory)][string] $Directory)

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $exe = $null
        try { $exe = $_.Path } catch { }
        if (Test-PathInside -Candidate $exe -Directory $Directory) { $_ }
    }
}

function Clear-InstallDir {
    <#
    .SYNOPSIS
        Remove a directory and everything under it, retrying until it is gone.

    .DESCRIPTION
        Miniconda's NSIS uninstaller returns before the tree is gone and keeps
        deleting for minutes afterwards. It also never removes files it did not
        install: uninstalling 4.12.0 was observed to leave 36 files across
        Tools, share and tcl. So the directory still exists after a clean,
        complete uninstall, and clearing it is what lets the installer run at
        all. Otherwise it exits 2 with "Directory '...' is not empty, please
        choose a different location".

        Two things stop the delete, and they need different answers.

        A transient one: the uninstaller still holds file handles. A single
        Remove-Item races those and loses, and -ErrorAction SilentlyContinue
        discards the failure, so the install that follows fails with nothing
        left on disk. That is what happened on 2026-10-06. Retrying fixes it.

        A permanent one: the uninstaller spawns _conda.exe helpers that can hang
        (observed 2026-10-16, two of them still alive 18 minutes later with a
        Python traceback in .step.log). No deadline wins against a live process
        holding the file. So after a grace period, processes running from inside
        the directory are stopped. They belong to the installation that has
        already been uninstalled, so by this point they are dead weight. The
        scope is deliberately narrow: only processes whose own executable is
        inside this directory, never anything else on the machine.

        Reports rather than throws. By the time this is called the old
        installation is already gone, so the caller has to stay free to attempt
        the install regardless of the outcome here.

    .OUTPUTS
        $true when the path no longer exists, $false on timeout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [int] $TimeoutMinutes = 15,
        [int] $RetrySeconds = 5,
        [int] $GraceSeconds = 60
    )

    $deadline  = (Get-Date).AddMinutes($TimeoutMinutes)
    $graceEnds = (Get-Date).AddSeconds($GraceSeconds)
    $warned    = @{}

    while (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) { break }

        # Past the grace period, anything still holding the directory is not
        # going to let go on its own.
        if ((Get-Date) -ge $graceEnds) {
            foreach ($proc in Get-ProcessInside -Directory $Path) {
                if (-not $warned.ContainsKey($proc.Id)) {
                    $warned[$proc.Id] = $true
                    Write-Warning ("Stopping $($proc.Name) (PID $($proc.Id)) from $($proc.Path): " +
                                   "it belongs to the Miniconda just uninstalled and is holding $Path open.")
                }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }

        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $RetrySeconds
    }
    return $true
}
