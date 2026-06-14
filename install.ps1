<#
.SYNOPSIS
    Symbiote CLI installer for Windows (PowerShell).

.DESCRIPTION
    Detects the architecture, downloads the matching standalone build, verifies
    its SHA-256 checksum (hard-fails on mismatch -- no fallback), extracts the
    onedir tree, and drops a `symbiote.cmd` launcher shim onto your PATH dir.

    Unix analog: packaging/install.sh.

.EXAMPLE
    irm https://<host>/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Version 1.2.3 -To C:\tools\bin

.NOTES
    Test seams (env): SYMBIOTE_INSTALL_OWNER/REPO/BASE_URL/API_BASE/BINDIR/LIBDIR
    and SYMBIOTE_UNAME_M (override detected arch). These let the offline pytest
    harness drive the script against a file:// fixture with no network.
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$To = "",
    [switch]$DryRun,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- configuration -------------------------------------------------------
$BinName = "symbiote"
$Owner = if ($env:SYMBIOTE_INSTALL_OWNER) { $env:SYMBIOTE_INSTALL_OWNER } else { "symbiote-labs" }
$Repo = if ($env:SYMBIOTE_INSTALL_REPO) { $env:SYMBIOTE_INSTALL_REPO } else { "symbiote-cli-dist" }
$BaseUrl = if ($env:SYMBIOTE_INSTALL_BASE_URL) { $env:SYMBIOTE_INSTALL_BASE_URL } else { "https://github.com/$Owner/$Repo/releases/download" }
$ApiBase = if ($env:SYMBIOTE_INSTALL_API_BASE) { $env:SYMBIOTE_INSTALL_API_BASE } else { "https://api.github.com/repos/$Owner/$Repo" }

$LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME "AppData/Local" }
$DefaultBin = if ($env:SYMBIOTE_INSTALL_BINDIR) { $env:SYMBIOTE_INSTALL_BINDIR } else { Join-Path $LocalAppData "Programs/symbiote/bin" }
$LibDir = if ($env:SYMBIOTE_INSTALL_LIBDIR) { $env:SYMBIOTE_INSTALL_LIBDIR } else { Join-Path $LocalAppData "Programs/symbiote/lib" }

if ([string]::IsNullOrEmpty($To)) { $To = $DefaultBin }

# ---- helpers -------------------------------------------------------------
function Write-Info {
    param([string]$Message)
    Write-Information -MessageData $Message -InformationAction Continue
}

function Show-Usage {
    Write-Info "Symbiote CLI installer (Windows)"
    Write-Info ""
    Write-Info "Usage: install.ps1 [-Version X.Y.Z] [-To DIR] [-DryRun] [-Help]"
    Write-Info ""
    Write-Info "  -Version X.Y.Z  Install a specific version (default: latest release)."
    Write-Info "  -To DIR         Directory for the 'symbiote.cmd' shim (default: $DefaultBin)."
    Write-Info "  -DryRun         Print what would happen; download and install nothing."
    Write-Info "  -Help           Show this help."
}

# Map the host to a release target triple. Honors the SYMBIOTE_UNAME_M seam.
function Resolve-Triple {
    $archRaw = if ($env:SYMBIOTE_UNAME_M) { $env:SYMBIOTE_UNAME_M } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($archRaw) {
        '^(AMD64|x86_64|x64)$' { return "x86_64-pc-windows-msvc" }
        '^(ARM64|aarch64)$' { throw "Windows arm64 is not built yet (only x86_64). See the release notes." }
        default { throw "unsupported architecture: $archRaw" }
    }
}

# Resolve the latest version (X.Y.Z) from the release API (tag: cli-vX.Y.Z).
function Resolve-LatestVersion {
    $resp = Invoke-RestMethod -Uri "$ApiBase/releases/latest" -UseBasicParsing
    $tag = $resp.tag_name
    if ([string]::IsNullOrEmpty($tag)) { throw "could not determine the latest version from $ApiBase" }
    return ($tag -replace '^cli-v', '')
}

function Get-RemoteFile {
    param([string]$Url, [string]$Dest)
    if ($Url -like 'file:*') {
        Copy-Item -LiteralPath ([System.Uri]$Url).LocalPath -Destination $Dest -Force
    }
    else {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    }
}

function Test-Checksum {
    param([string]$Archive, [string]$ShaFile)
    $expected = ((Get-Content -LiteralPath $ShaFile -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLower()
    if ($actual -ne $expected) {
        throw "checksum verification FAILED ($actual != $expected) -- refusing to install"
    }
}

# ---- main ----------------------------------------------------------------
function Invoke-Install {
    param(
        [string]$Version,
        [string]$To,
        [switch]$DryRun,
        [switch]$Help
    )
    if ($Help) { Show-Usage; return }

    $triple = Resolve-Triple
    if ([string]::IsNullOrEmpty($Version)) { $Version = Resolve-LatestVersion }

    $tag = "cli-v$Version"
    $stage = "$BinName-$Version-$triple"
    $asset = "$stage.zip"
    $assetUrl = "$BaseUrl/$tag/$asset"
    $sumUrl = "$assetUrl.sha256"
    $destDir = Join-Path $LibDir $stage
    $launcher = Join-Path $destDir "$BinName.exe"
    $shim = Join-Path $To "$BinName.cmd"

    Write-Info "Symbiote CLI $Version ($triple)"
    Write-Info "  download: $assetUrl"
    Write-Info "  install:  $destDir"
    Write-Info "  shim:     $shim -> $launcher"

    if ($DryRun) {
        Write-Info "dry-run: nothing downloaded or installed."
        return
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zipPath = Join-Path $tmp $asset
        Get-RemoteFile -Url $assetUrl -Dest $zipPath
        Get-RemoteFile -Url $sumUrl -Dest "$zipPath.sha256"
        Test-Checksum -Archive $zipPath -ShaFile "$zipPath.sha256"

        if (Test-Path -LiteralPath $destDir) { Remove-Item -LiteralPath $destDir -Recurse -Force }
        New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
        New-Item -ItemType Directory -Path $To -Force | Out-Null

        Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
        Move-Item -LiteralPath (Join-Path $tmp $stage) -Destination $destDir

        if (-not (Test-Path -LiteralPath $launcher)) {
            throw "expected launcher not found after extraction: $launcher"
        }

        # Windows has no symlinks-by-default; a .cmd shim is the portable launcher.
        $shimBody = "@echo off`r`n`"$launcher`" %*`r`n"
        Set-Content -LiteralPath $shim -Value $shimBody -NoNewline -Encoding ascii

        Write-Info "Installed $BinName $Version -> $shim"
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # PATH guidance / update (the registry edit is Windows-only).
    # $IsWindows only exists in PowerShell Core; on Windows PowerShell 5.1 (where
    # it is absent) we are necessarily on Windows.
    $onWindows = (-not (Test-Path variable:IsWindows)) -or $IsWindows
    $pathParts = ($env:PATH -split [System.IO.Path]::PathSeparator)
    if ($pathParts -notcontains $To) {
        if ($onWindows) {
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            [Environment]::SetEnvironmentVariable("PATH", "$userPath;$To", "User")
            Write-Info ""
            Write-Info "Added $To to your user PATH. Restart your terminal to pick it up."
        }
        else {
            Write-Info ""
            Write-Info "NOTE: $To is not on your PATH. Add it to use 'symbiote' directly."
        }
    }
}

Invoke-Install -Version $Version -To $To -DryRun:$DryRun -Help:$Help
