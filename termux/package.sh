#!/usr/bin/env bash
# Packages the Android/Termux build into zip + .deb + pacman .pkg.tar.xz
#
# Usage:
#   package.sh --dist <dir with bin/ lib/ NOTICE.md> --name opencode --version 1.18.34 \
#              --binaries out/ --arch aarch64
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

DIST="" NAME="" VERSION="" OUT="" ARCH="aarch64" PKGREL="1"
while [ $# -gt 0 ]; do
  case "$1" in
    --dist)    DIST="$2"; shift 2 ;;
    --name)    NAME="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    --arch)    ARCH="$2"; shift 2 ;;
    --rel)     PKGREL="$2"; shift 2 ;;
    *) cf::die "unknown argument: $1" ;;
  esac
done

[ -n "$DIST" ] && [ -d "$DIST" ] || cf::die "--dist must point at a directory containing bin/"
[ -n "$NAME" ]    || cf::die "--name is required"
[ -n "$VERSION" ] || cf::die "--version is required"
OUT="${OUT:-$ROOT_DIR/out-termux}"
mkdir -p "$OUT"

PREFIX_PATH="data/data/com.termux/files/usr"
STAGE="$OUT/.stage-$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/$PREFIX_PATH/bin" "$STAGE/$PREFIX_PATH/libexec/$NAME" "$STAGE/$PREFIX_PATH/lib"

# --- lay out the Termux prefix --------------------------------------------------
if [ -f "$DIST/bin/opencode.bin" ]; then
  # opencode-style layout: wrapper in bin/, real binary in libexec/, libs in lib/
  install -m 0755 "$DIST/bin/opencode"      "$STAGE/$PREFIX_PATH/bin/$NAME"
  install -m 0755 "$DIST/bin/opencode.bin"  "$STAGE/$PREFIX_PATH/libexec/$NAME/$NAME.bin"
  # rewrite the wrapper to the installed location
  cat > "$STAGE/$PREFIX_PATH/bin/$NAME" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# CrossForge Termux launcher for $NAME $VERSION
SELF="\$PREFIX/libexec/$NAME/$NAME.bin"
LIB="\$PREFIX/lib"
export LD_LIBRARY_PATH="\$LIB:\${LD_LIBRARY_PATH:-}"
export OPENTUI_LIB_PATH="\${OPENTUI_LIB_PATH:-\$LIB}"
exec "\$SELF" "\$@"
EOF
  chmod 0755 "$STAGE/$PREFIX_PATH/bin/$NAME"
  for so in "$DIST"/lib/*.so*; do
    [ -e "$so" ] && install -m 0644 "$so" "$STAGE/$PREFIX_PATH/lib/"
  done
else
  # plain: everything in bin/
  for f in "$DIST"/bin/*; do install -m 0755 "$f" "$STAGE/$PREFIX_PATH/bin/"; done
fi

for extra in NOTICE.md LICENSE README.md; do
  [ -f "$DIST/$extra" ] && cp "$DIST/$extra" "$STAGE/$PREFIX_PATH/libexec/$NAME/" || true
done

# --- dependency list (ripgrep is used by the agent's search tools) --------------
DEPS_DEB="ripgrep, bash"
DEPS_PACMAN="ripgrep bash"

# --- 1. plain zip ----------------------------------------------------------------
( cd "$STAGE" && zip -qr "$OUT/${NAME}-${VERSION}-android-${ARCH}.zip" . )
cf::log "zip  → ${NAME}-${VERSION}-android-${ARCH}.zip"

# --- 2. .deb (Debian/Ubuntu-flavoured Termux installs & proot distros) ----------
DEB_DIR="$OUT/deb-$NAME"
rm -rf "$DEB_DIR"; mkdir -p "$DEB_DIR/DEBIAN"
SIZE_KB=$(du -sk "$STAGE" | awk '{print $1}')
cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION-$PKGREL
Architecture: $ARCH
Maintainer: CrossForge <crossforge@users.noreply.github.com>
Installed-Size: $SIZE_KB
Depends: $DEPS_DEB
Homepage: https://github.com/OWNER/crossforge
Description: $NAME for Android/Termux ($ARCH) — built by CrossForge
 Cross-compiled from public source by the CrossForge pipeline.
 See /data/data/com.termux/files/usr/libexec/$NAME/NOTICE.md for provenance.
EOF
cp -a "$STAGE/." "$DEB_DIR/"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$DEB_DIR" "$OUT/${NAME}-${VERSION}-${ARCH}.deb" >/dev/null
  cf::log "deb  → ${NAME}-${VERSION}-${ARCH}.deb"
else
  cf::warn "dpkg-deb not installed — skipping .deb (zip still produced)"
fi

# --- 3. pacman package (Termux uses pacman) -------------------------------------
if command -v bsdtar >/dev/null 2>&1 || command -v tar >/dev/null 2>&1; then
  PKG_DIR="$OUT/pkg-$NAME"
  rm -rf "$PKG_DIR"; mkdir -p "$PKG_DIR"
  cp -a "$STAGE/$PREFIX_PATH/." "$PKG_DIR/"
  cat > "$PKG_DIR/.PKGINFO" <<EOF
pkgname = $NAME
pkgbase = $NAME
pkgver = $VERSION-$PKGREL
pkgdesc = $NAME for Android/Termux ($ARCH) — built by CrossForge
url = https://github.com/OWNER/crossforge
builddate = $(date +%s)
packager = CrossForge <crossforge@users.noreply.github.com>
size = $(du -sb "$PKG_DIR" | awk '{print $1}')
arch = $ARCH
license = MIT
depend = $DEPS_PACMAN
EOF
  ( cd "$PKG_DIR" && tar -cJf "$OUT/${NAME}-${VERSION}-${PKGREL}-${ARCH}.pkg.tar.xz" .PKGINFO * )
  cf::log "pacman → ${NAME}-${VERSION}-${PKGREL}-${ARCH}.pkg.tar.xz"
fi

# --- 4. standalone installer -----------------------------------------------------
cp "$SCRIPT_DIR/install.sh" "$OUT/termux-install.sh" 2>/dev/null || true
chmod +x "$OUT/termux-install.sh" 2>/dev/null || true

rm -rf "$STAGE" "$DEB_DIR" "$PKG_DIR"
cf::log "termux packaging done → $OUT"
ls -la "$OUT"
