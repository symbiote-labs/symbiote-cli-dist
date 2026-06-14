# Symbiote CLI — Standalone Distribution

Download-and-run binaries for **`symbiote`**, the terminal client for the Symbiote
Orchestrator platform. No Python required. This repository holds the release
binaries and installers only — not the source.

Supported: **Linux** (x86_64, arm64 — glibc ≥ 2.28: Rocky/RHEL/Alma 8+9, Ubuntu
20.04+, Debian 10+, Mint 20+), **Windows** (x86_64), and **macOS** (Apple silicon
+ Intel).

> **macOS note:** the macOS binaries are not yet code-signed/notarized (Developer ID
> signing is coming). Installs via the script below or Homebrew run with no extra
> steps. If you instead download a `.tar.gz` manually through a browser, macOS
> quarantines it and Gatekeeper will block it — clear the quarantine flag once:
> ```sh
> xattr -dr com.apple.quarantine <path-to-extracted-symbiote-dir>
> ```

## Install

### macOS / Linux (script)
```sh
curl -fsSL https://raw.githubusercontent.com/symbiote-labs/symbiote-cli-dist/main/install.sh | sh
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/symbiote-labs/symbiote-cli-dist/main/install.ps1 | iex
```

### Homebrew (macOS / Linux)
```sh
brew tap symbiote-labs/symbiote
brew install symbiote
```

### Scoop (Windows)
```powershell
scoop bucket add symbiote https://github.com/symbiote-labs/scoop-symbiote
scoop install symbiote
```

### Debian / Ubuntu / Mint (.deb)
Download the `.deb` for your architecture from the
[latest release](https://github.com/symbiote-labs/symbiote-cli-dist/releases/latest), then:
```sh
sudo apt install ./symbiote_*_amd64.deb   # or _arm64
```

### Rocky / RHEL / Alma / Fedora (.rpm)
```sh
sudo dnf install ./symbiote-*.x86_64.rpm   # or .aarch64
```

## Verify

Every release ships `checksums.txt` and a per-asset `.sha256`. The script installers
verify the SHA-256 before installing (hard fail on mismatch). After install:

```sh
symbiote --help
```
