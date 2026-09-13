# chocolatey-miniconda3

Source for the [`miniconda3`](https://community.chocolatey.org/packages/miniconda3)
Chocolatey package. Community-maintained, not affiliated with Anaconda, Inc.

```powershell
choco install miniconda3
```

## Why this repo exists

The package sat at 4.12.0 from April 2022 until September 2026, shipping a
`py39_4.12.0` installer and flagged "Possibly broken". Its updater had stopped
working for three independent reasons:

1. It scraped `https://docs.conda.io/en/latest/miniconda.html` for installer
   links. That page no longer carries them.
2. Its link pattern hardcoded `py39_`, a series Anaconda no longer builds.
3. Its version pattern could not match the build suffix in current filenames
   such as `Miniconda3-py313_26.7.1-1-Windows-x86_64.exe`.

`update.ps1` here reads the [repo.anaconda.com index](https://repo.anaconda.com/miniconda/)
instead, which publishes a SHA256 beside every file, so a release is resolved
and checksummed without downloading a 124 MB installer.

Thanks to [@chaliy](https://github.com/chaliy) and [@Litee](https://github.com/Litee),
who maintained this package for years and handed it on.

## Versioning

Upstream numbers releases `<conda version>-<build>`, for example `26.7.1-1`.
That cannot go into a nuspec unchanged: `-1` parses as a NuGet prerelease tag
and sorts *below* `26.7.1`, which breaks upgrade ordering. The build becomes a
fourth version part instead, so `26.7.1-1` is published as `26.7.1.1`.

## Python series

Anaconda publishes a separate Windows installer per Python series, py310 through
py314 at the time of writing, rather than a single "latest". This package
follows one deliberately. The series is the `$PythonSeries` default at the top
of `update.ps1`.

Windows builds are 64-bit only. 32-bit was dropped upstream after 4.12.0.

## Upgrading

Miniconda's installer will not write over an existing installation: it exits 2,
reported as "Setup was cancelled". So an upgrade removes the old installation
first. Conda environments inside the installation directory would go with it, so
the upgrade stops and lists them rather than destroying them. Export or move
them, or pass `/Force`:

```powershell
choco upgrade miniconda3 --params="'/Force'"
```

Environments kept outside the installation directory are unaffected.

## Package parameters

Unchanged from the package as published since 4.10.3, so an upgrade never
relocates an existing installation.

| Parameter | Default | Meaning |
|---|---|---|
| `/InstallationType:` | `AllUsers` | `AllUsers` or `JustMe` |
| `/AddToPath:` | `0` | Put Miniconda on `PATH` |
| `/RegisterPython:` | `1` | Register as the default python3 |
| `/D:` | `$ToolsDir\miniconda3` | Installation directory |
| `/Force` | off | Upgrade even if environments would be destroyed |

```powershell
choco install miniconda3 --params="'/AddToPath:1'"
```

## Maintaining

```powershell
.\update.ps1 -ResolveOnly          # show what upstream is offering
.\update.ps1                       # update package files and pack
.\update.ps1 -Push                 # also publish (needs CHOCO_API_KEY)
.\update.ps1 -PythonSeries py314   # track a different series

pwsh -File tools/Test-ResolveRelease.ps1
```

`.github/workflows/update.yml` runs daily, publishes a new upstream version, and
commits the bump back. `.github/workflows/publish.yml` is a manual one-shot for
the initial publish or a re-push during moderation. Both need the
`CHOCO_API_KEY` repository secret, from
<https://community.chocolatey.org/account>.
