#!/usr/bin/env sh
#
# Symbiote CLI installer.
#
#   curl -fsSL https://<host>/install.sh | sh
#   curl -fsSL https://<host>/install.sh | sh -s -- --version 1.2.3 --to /usr/local/bin
#
# Detects OS/arch, downloads the matching standalone build, verifies its SHA-256
# checksum (hard-fails on mismatch — no fallback), then installs the onedir tree
# and symlinks the launcher onto your PATH.
#
# Configuration (env overrides, mainly for testing / mirrors):
#   SYMBIOTE_INSTALL_OWNER     GitHub owner of the public dist repo
#   SYMBIOTE_INSTALL_REPO      GitHub repo name (default: symbiote-cli-dist)
#   SYMBIOTE_INSTALL_BASE_URL  asset base; assets at <BASE_URL>/<tag>/<asset>
#   SYMBIOTE_INSTALL_API_BASE  API base for resolving the latest version
#   SYMBIOTE_INSTALL_BINDIR    bin dir for the symlink (default: ~/.local/bin)
#   SYMBIOTE_INSTALL_LIBDIR    extraction root (default: ~/.local/share/symbiote)
#   SYMBIOTE_UNAME_S           override `uname -s` (test seam)
#   SYMBIOTE_UNAME_M           override `uname -m` (test seam)
#
set -eu

# ---- configuration -------------------------------------------------------
OWNER="${SYMBIOTE_INSTALL_OWNER:-symbiote-labs}"
REPO="${SYMBIOTE_INSTALL_REPO:-symbiote-cli-dist}"
BASE_URL="${SYMBIOTE_INSTALL_BASE_URL:-https://github.com/${OWNER}/${REPO}/releases/download}"
API_BASE="${SYMBIOTE_INSTALL_API_BASE:-https://api.github.com/repos/${OWNER}/${REPO}}"
BINDIR="${SYMBIOTE_INSTALL_BINDIR:-${HOME:-}/.local/bin}"
LIBDIR="${SYMBIOTE_INSTALL_LIBDIR:-${HOME:-}/.local/share/symbiote}"

BIN_NAME="symbiote"
VERSION=""
DRY_RUN=0

# ---- helpers -------------------------------------------------------------
err() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  cat <<EOF
Symbiote CLI installer

Usage: install.sh [--version X.Y.Z] [--to DIR] [--dry-run] [-h|--help]

  --version X.Y.Z   Install a specific version (default: latest release).
  --to DIR          Directory to place the '${BIN_NAME}' launcher symlink
                    (default: ${BINDIR}).
  --dry-run         Print what would happen; download and install nothing.
  -h, --help        Show this help.
EOF
}

# Map the host to a release target triple. Honors test-seam env overrides.
detect_triple() {
  os_raw="${SYMBIOTE_UNAME_S:-$(uname -s)}"
  arch_raw="${SYMBIOTE_UNAME_M:-$(uname -m)}"
  case "${os_raw}" in
    Darwin) os="apple-darwin" ;;
    Linux) os="unknown-linux-gnu" ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT)
      err "Windows is not supported by this script yet. A PowerShell installer is planned." ;;
    *) err "unsupported operating system: ${os_raw}" ;;
  esac
  case "${arch_raw}" in
    x86_64 | amd64) arch="x86_64" ;;
    arm64 | aarch64) arch="aarch64" ;;
    *) err "unsupported architecture: ${arch_raw}" ;;
  esac
  printf '%s-%s' "${arch}" "${os}"
}

# Resolve the latest version (X.Y.Z) from the release API (tag: cli-vX.Y.Z).
resolve_latest_version() {
  tag=$(curl -fsSL "${API_BASE}/releases/latest" \
    | grep '"tag_name"' | head -1 \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  [ -n "${tag}" ] || err "could not determine the latest version from ${API_BASE}"
  printf '%s' "${tag#cli-v}"
}

download() {
  # download <url> <dest>
  curl -fsSL -o "$2" "$1" || err "download failed: $1"
}

verify_checksum() {
  # verify_checksum <dir> <checksum-file-name> — runs inside <dir>
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$1" && sha256sum -c "$2" ) || err "checksum verification FAILED — refusing to install"
  elif command -v shasum >/dev/null 2>&1; then
    ( cd "$1" && shasum -a 256 -c "$2" ) || err "checksum verification FAILED — refusing to install"
  else
    err "no sha256 tool found (need sha256sum or shasum)"
  fi
}

# ---- arg parsing ---------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --version) shift; [ $# -gt 0 ] || err "--version needs a value"; VERSION="$1" ;;
    --version=*) VERSION="${1#--version=}" ;;
    --to) shift; [ $# -gt 0 ] || err "--to needs a value"; BINDIR="$1" ;;
    --to=*) BINDIR="${1#--to=}" ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    *) err "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

command -v curl >/dev/null 2>&1 || err "curl is required but was not found"

# ---- resolve target ------------------------------------------------------
TRIPLE="$(detect_triple)"
if [ -z "${VERSION}" ]; then
  VERSION="$(resolve_latest_version)"
fi

TAG="cli-v${VERSION}"
ASSET="${BIN_NAME}-${VERSION}-${TRIPLE}.tar.gz"
ASSET_URL="${BASE_URL}/${TAG}/${ASSET}"
SUM_URL="${ASSET_URL}.sha256"
DEST_DIR="${LIBDIR}/${BIN_NAME}-${VERSION}-${TRIPLE}"
LAUNCHER="${DEST_DIR}/${BIN_NAME}"
LINK="${BINDIR}/${BIN_NAME}"

info "Symbiote CLI ${VERSION} (${TRIPLE})"
info "  download: ${ASSET_URL}"
info "  install:  ${DEST_DIR}"
info "  symlink:  ${LINK} -> ${LAUNCHER}"

if [ "${DRY_RUN}" -eq 1 ]; then
  info "dry-run: nothing downloaded or installed."
  exit 0
fi

# ---- download + verify ---------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT INT TERM
download "${ASSET_URL}" "${TMP}/${ASSET}"
download "${SUM_URL}" "${TMP}/${ASSET}.sha256"
verify_checksum "${TMP}" "${ASSET}.sha256"

# ---- install -------------------------------------------------------------
rm -rf "${DEST_DIR}"
mkdir -p "${LIBDIR}" "${BINDIR}"
tar -xzf "${TMP}/${ASSET}" -C "${TMP}"
# The archive contains a top-level dir named like the asset (sans .tar.gz).
mv "${TMP}/${BIN_NAME}-${VERSION}-${TRIPLE}" "${DEST_DIR}"
[ -x "${LAUNCHER}" ] || err "expected launcher not found after extraction: ${LAUNCHER}"
ln -sf "${LAUNCHER}" "${LINK}"

info "Installed ${BIN_NAME} ${VERSION} -> ${LINK}"

# ---- PATH guidance -------------------------------------------------------
case ":${PATH}:" in
  *":${BINDIR}:"*) : ;;
  *) info ""
     info "NOTE: ${BINDIR} is not on your PATH. Add this to your shell profile:"
     info "  export PATH=\"${BINDIR}:\$PATH\"" ;;
esac
