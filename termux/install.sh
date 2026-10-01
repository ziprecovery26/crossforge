#!/data/data/com.termux/files/usr/bin/bash
# CrossForge · Termux installer for opencode
#
#   curl -fsSL https://github.com/OWNER/crossforge/releases/latest/download/termux-install.sh | bash
#
# Installs:
#   $PREFIX/bin/opencode                  launcher
#   $PREFIX/libexec/opencode/opencode.bin the real binary
#   $PREFIX/lib/libopentui.so             TUI renderer (bionic aarch64)
set -euo pipefail

REPO="${CROSSFORGE_REPO:-OWNER/crossforge}"
PROJECT="${CROSSFORGE_PROJECT:-opencode}"
VERSION="${CROSSFORGE_VERSION:-latest}"
ARCH="$(uname -m)"

say()  { printf '\033[1;36m[termux]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[termux][error]\033[0m %s\n' "$*" >&2; exit 1; }

[ -n "${PREFIX:-}" ] || die "Yeh installer Termux ke liye hai (PREFIX set nahi hai). Regular Linux ke liye install.sh use karo."

case "$ARCH" in
  aarch64|arm64) ;;
  *) die "Abhi sirf aarch64 (arm64) support hai. Tumhara arch: $ARCH" ;;
esac

command -v curl >/dev/null || { say "curl install kar raha hoon..."; pkg install -y curl; }

if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi
ASSET="${PROJECT}-android-arm64.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading $ASSET ..."
if ! curl -fL --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET"; then
  die "Download fail hua. Releases page check karo: https://github.com/$REPO/releases"
fi

say "SHA256 verify kar raha hoon..."
if curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" 2>/dev/null; then
  ( cd "$TMP" && grep -E "  $ASSET\$" SHA256SUMS | sha256sum -c - ) || die "Checksum match nahi hua — download corrupt ya tampered hai."
else
  say "SHA256SUMS nahi mila, verification skip."
fi

say "Extract + install..."
tar -xzf "$TMP/$ASSET" -C "$TMP"
SRC="$TMP"

mkdir -p "$PREFIX/libexec/$PROJECT" "$PREFIX/lib" "$PREFIX/bin"

if [ -f "$SRC/bin/$PROJECT.bin" ]; then
  install -m 0755 "$SRC/bin/$PROJECT.bin" "$PREFIX/libexec/$PROJECT/$PROJECT.bin"
  install -m 0755 "$SRC/bin/$PROJECT"     "$PREFIX/bin/$PROJECT"
else
  install -m 0755 "$SRC/bin/$PROJECT" "$PREFIX/bin/$PROJECT"
fi

for so in "$SRC"/lib/*.so*; do
  [ -e "$so" ] && install -m 0644 "$so" "$PREFIX/lib/" && say "native lib: $(basename "$so")"
done
for extra in NOTICE.md LICENSE; do
  [ -f "$SRC/$extra" ] && cp "$SRC/$extra" "$PREFIX/libexec/$PROJECT/"
done

# ripgrep is used by opencode's search tools
if ! command -v rg >/dev/null 2>&1; then
  say "ripgrep install kar raha hoon (opencode isko use karta hai)..."
  pkg install -y ripgrep >/dev/null 2>&1 || say "ripgrep install fail — manually: pkg install ripgrep"
fi

say "Installed! Version check:"
"$PREFIX/bin/$PROJECT" --version || say "Binary run nahi hua — issue kholo: https://github.com/$REPO/issues"

cat <<'EOF'

✅ Ho gaya!

Aage kya:
  export ANTHROPIC_API_KEY="sk-ant-..."     # ya koi bhi supported provider
  opencode

Termux tips:
  • Storage access chahiye to: termux-setup-storage
  • Agar TUI render na ho: pkg install ncurses-utils; aur `echo $TERM` check karo (xterm-256color hona chahiye)
EOF
