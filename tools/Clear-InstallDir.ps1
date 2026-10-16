# Dot-sourced by chocolateyinstall.ps1, and by Test-ClearInstallDir.ps1, so the
# one piece of logic that can destroy a working installation is directly
# testable rather than buried inline in the install script.

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

        A single Remove-Item races the uninstaller's remaining file handles.
        When it loses, -ErrorAction SilentlyContinue discards the failure and
        the install that follows fails with nothing left on disk. That is what
        happened on 2026-10-06. Retry instead.

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
        [int] $RetrySeconds = 5
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) { break }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $RetrySeconds
    }
    return $true
}
