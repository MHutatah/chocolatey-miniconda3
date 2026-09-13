$ErrorActionPreference = 'Stop'

$packageVersion = $env:chocolateyPackageVersion
# Anaconda has published a 64-bit Windows installer only since 4.12.0, and there
# is no native arm64 build, so arm64 runs this under x64 emulation.
$url64 = 'https://repo.anaconda.com/miniconda/Miniconda3-py313_26.7.1-1-Windows-x86_64.exe'
$checksum64 = 'ff485c617e0e15addc111aa1caa206679e214d223624297bf8aa0bc726ed67bd'
$ToolsDir = Get-ToolsLocation
$pp = Get-PackageParameters

# Parameters and defaults are unchanged from the package as published since
# 4.10.3, so an upgrade never relocates an existing installation.
if (!$pp['InstallationType']) {
    $InstallationType = 'AllUsers'
}
else {
    if ($pp['InstallationType'] -notin 'AllUsers', 'JustMe') {
        Write-Error "Value for InstallationType not recognised: only `'AllUsers`' or `'JustMe`' are valid"
    }
    else {
        $InstallationType = $pp['InstallationType']
    }
}

if (!$pp['RegisterPython']) {
    $RegisterPython = '1'
}
else {
    if ($pp['RegisterPython'] -notin '0', '1') {
        Write-Error "Value for RegisterPython not recognised: only `'0`' or `'1`' are valid"
    }
    else {
        $RegisterPython = $pp['RegisterPython']
    }
}

if (!$pp['AddToPath']) {
    $AddToPath = '0'
}
else {
    if ($pp['AddToPath'] -notin '0', '1') {
        Write-Error "Value for AddToPath not recognised: only `'0`' or `'1`' are valid"
    }
    else {
        $AddToPath = $pp['AddToPath']
    }
}

if (!$pp['D']) {
    $D = Join-Path $ToolsDir 'miniconda3'
}
else {
    if (!(Test-Path -IsValid $pp['D'])) {
        Write-Error "Value for D ($($pp['D'])) is not a valid directory path"
    }
    else {
        $D = $pp['D']
    }
}

# Miniconda's NSIS installer refuses to write into a directory that already
# holds a Miniconda: it exits 2, which Chocolatey reports as "Setup was
# cancelled". Upgrading therefore has to remove the old tree first. Any
# environments living inside it would go with it, so stop rather than destroy
# them; /Force overrides once they have been exported or moved.
#
# This looks only at $D. An installation originally placed elsewhere with /D
# needs the same /D passed on upgrade, which has always been true here.
$existing = Join-Path $D 'Uninstall-Miniconda3.exe'
if (Test-Path -LiteralPath $existing) {
    $envsDir = Join-Path $D 'envs'
    $envs = if (Test-Path -LiteralPath $envsDir) { @(Get-ChildItem -LiteralPath $envsDir -Directory) } else { @() }
    if ($envs.Count -gt 0 -and !$pp['Force']) {
        throw ("$D holds $($envs.Count) conda environment(s): " + ($envs.Name -join ', ') +
               ". Upgrading Miniconda removes them. Export or move them first, then re-run, " +
               "or pass --params `"'/Force'`" to upgrade anyway.")
    }

    Write-Host "Removing the existing Miniconda3 at $D before upgrading..."
    Uninstall-ChocolateyPackage -PackageName 'miniconda3' -FileType 'exe' `
                                -SilentArgs '/S' -File $existing -ValidExitCodes @(0)

    # The NSIS uninstaller returns before the tree is actually gone, and on a
    # large installation it keeps working for minutes afterwards.
    #
    # Never throw past this point. The installation has already been removed, so
    # aborting here leaves the machine with no Miniconda at all, which is worse
    # than any install error that follows. Wait generously, clear whatever the
    # uninstaller could not delete (it cannot remove its own exe while running),
    # then let the installer report any real problem itself.
    $deadline = (Get-Date).AddMinutes(15)
    while ((Test-Path -LiteralPath $existing) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }

    if (Test-Path -LiteralPath $D) {
        Write-Host "Clearing what the uninstaller left behind in $D ..."
        Remove-Item -LiteralPath $D -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Install-ChocolateyPackage `
    -PackageName 'miniconda3' `
    -InstallerType 'EXE'  `
    -Url64 $url64 `
    -Checksum64 $checksum64 `
    -ChecksumType64 'sha256' `
    -SilentArgs "/S /InstallationType=$InstallationType /RegisterPython=$RegisterPython /AddToPath=$AddToPath /D=$D" `
    -ValidExitCodes @(0)
