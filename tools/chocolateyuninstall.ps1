$ErrorActionPreference = 'Stop'

# The install directory is a package parameter, and parameters are not
# guaranteed to be remembered at uninstall time, so find the installation
# through its Add/Remove Programs entry rather than assuming a path.
[array]$key = Get-UninstallRegistryKey -SoftwareName 'Miniconda3*'

if ($key.Count -eq 1) {
    # QuietUninstallString is the NSIS uninstaller already carrying /S.
    $uninstaller = $key[0].UninstallString -replace '^"|"$', ''
    if (-not (Test-Path -LiteralPath $uninstaller)) {
        Write-Warning "Registry points at $uninstaller, which does not exist. Nothing to do."
        return
    }

    Uninstall-ChocolateyPackage -PackageName 'miniconda3' `
                                -FileType 'exe' `
                                -SilentArgs '/S' `
                                -File $uninstaller `
                                -ValidExitCodes @(0)
}
elseif ($key.Count -eq 0) {
    Write-Warning "Miniconda3 has already been uninstalled by other means."
}
else {
    # A separate Anaconda3 or a second Miniconda3 would also match. Removing the
    # wrong one loses somebody's environments, so do nothing and say which.
    Write-Warning "$($key.Count) installations match 'Miniconda3*'. Skipping auto-uninstall to be safe."
    $key | ForEach-Object { Write-Warning "- $($_.DisplayName)" }
}
