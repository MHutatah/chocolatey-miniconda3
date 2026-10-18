# Build-time helper, dot-sourced by .github/workflows. Not shipped: the nuspec
# packs tools\** only, so nothing under build\ reaches the package.

function Get-FeedVersion {
    <#
    .SYNOPSIS
        The version NuGet will actually use, given a nuspec version.

    .DESCRIPTION
        NuGet normalizes a zero revision away, so the nuspec version 26.9.3.0
        becomes 26.9.3 in the artifact name (miniconda3.26.9.3.nupkg) and on the
        feed. This package's fourth version component is upstream's build
        number, which is 0 on a first build, so the difference is routine rather
        than exotic. It has broken three things already: the mumuplayer push,
        the 2026-10-15 auto-update ("Missing package artifact:
        miniconda3.26.9.3.0.nupkg") and the 2026-10-17 feed probe.

        Only a four-part version with a zero revision changes. A trailing zero
        in the third component is kept, because NuGet keeps it: 4.12.0 stays
        4.12.0. Anything that is not four parts is returned unchanged, which
        covers every version this package has ever used.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $NuspecVersion)

    if ([string]::IsNullOrWhiteSpace($NuspecVersion)) {
        throw "Get-FeedVersion: the nuspec version is empty."
    }

    $parts = $NuspecVersion.Trim().Split('.')
    if ($parts.Count -eq 4 -and $parts[3] -match '^0+$') {
        return ($parts[0..2] -join '.')
    }
    return $NuspecVersion.Trim()
}
