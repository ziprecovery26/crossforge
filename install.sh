#!/usr/bin/env bash
# CrossForge · Linux/macOS installer for opencode
#
#   curl -fsSL https://github.com/ziprecovery26/crossforge/releases/latest/download/install.sh | bash
#
# Env overrides: CROSSFORGE_REPO, CROSSFORGE_PROJECT, CROSSFORGE_VERSION, CROSSFORGE_PREFIX
set -euo pipefail

REPO="${CROSSFORGE_REPO:-ziprecovery26/crossforge}"
PROJECT="${CROSSFORGE_PROJECT:-opencode}"
VERSION="${CROSSFORGE_VERSION:-latest}"
PREFIX_DIR="${CROSSFORGE_PREFIX:-$HOME/.local}"

say() { printf '\033[1;36m[crossforge]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[crossforge][error]\033[0m %s\n' "$*" >&2; exit 1; }

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  os="linux" ;;
  Darwin) os="darwin" ;;
  *) die "Unsupported OS: $OS (Windows ke liye install.ps1 use karo)" ;;
esac
case "$ARCH" in
  x86_64|amd64) arch="x64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) die "Unsupported arch: $ARCH" ;;
esac

# musl detection (Alpine etc.)
if [ "$os" = "linux" ] && { [ -f /etc/alpine-release ] || ldd /bin/sh 2>/dev/null | grep -qi musl; }; then
  TARGET="linux-${arch}-musl"
else
  TARGET="${os}-${arch}"
fi

if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

if [ "$os" = "darwin" ]; then ASSET="${PROJECT}-${TARGET}.tar.gz"; else ASSET="${PROJECT}-${TARGET}.tar.gz"; fi

say "platform: $TARGET"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say "downloading $ASSET"
curl -fL --retry 3 --progress-bar -o "$TMP/$ASSET" "$BASE/$ASSET" \
  || die "download failed. Available builds: https://github.com/$REPO/releases"

if curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" 2>/dev/null; then
  ( cd "$TMP" && grep -E "  $ASSET\$" SHA256SUMS | sha256sum -c - ) \
    || die "checksum mismatch — refusing to install"
  say "checksum ok"
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"
mkdir -p "$PREFIX_DIR/bin"
install -m 0755 "$TMP/$PROJECT" "$PREFIX_DIR/bin/$PROJECT"
say "installed → $PREFIX_DIR/bin/$PROJECT"

case ":$PATH:" in
  *":$PREFIX_DIR/bin:"*) ;;
  *) say "PATH mein add karne ke liye apne shell rc mein yeh daalo:"
     say "  export PATH=\"$PREFIX_DIR/bin:\$PATH\"" ;;
esac

"$PREFIX_DIR/bin/$PROJECT" --version || true
say "done ✅"
