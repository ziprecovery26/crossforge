#!/usr/bin/env bash
# Generic Rust builder — cross compilation through cargo-zigbuild + zig.
# Recipe fields:
#   rust.bins     : array of [[bin]] names (defaults to package name)
#   rust.features : comma separated features
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

RECIPE="" UPSTREAM="" OUT="" TARGETS="" VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recipe) RECIPE="$2"; shift 2 ;;
    --upstream) UPSTREAM="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) cf::die "unknown argument: $1" ;;
  esac
done

cf::need cargo
cf::need jq

CF_PROJECT="$(jq -r '.id' "$RECIPE")"
export CF_PROJECT
BINS="$(jq -r '(.rust.bins // [.custom.binaryName // .id]) | join(" ")' "$RECIPE")"
FEATURES="$(jq -r '.rust.features // empty' "$RECIPE")"

PKG_DIR="$UPSTREAM/$(jq -r '.upstream.subdir // "."' "$RECIPE")"
cd "$PKG_DIR"

# Prefer cargo-zigbuild (no macOS machine needed for darwin targets). Fall back
# to plain cargo when zig isn't available.
BUILDER="cargo"
if command -v cargo-zigbuild >/dev/null 2>&1; then
  BUILDER="cargo zigbuild"
  cf::log "using cargo-zigbuild"
else
  cf::warn "cargo-zigbuild not found — falling back to cargo (host-only linking; darwin/msvc targets may fail)"
fi

for target in ${TARGETS//,/ }; do
  triple="$(cf::rust_triple "$target")"
  out_dir="$OUT/${CF_PROJECT}-${target}"
  mkdir -p "$out_dir/bin"

  cf::group "building $CF_PROJECT-$target ($triple)"

  rustup target add "$triple" >/dev/null 2>&1 || cf::warn "rustup target add $triple failed (may already be installed)"

  extra=""
  [ -n "$FEATURES" ] && extra="--features $FEATURES"

  # shellcheck disable=SC2086
  $BUILDER --release --target "$triple" $extra || cf::die "rust build failed for $triple"

  found=0
  for bin in $BINS; do
    src="target/$triple/release/$bin"
    [ -f "${src}.exe" ] && src="${src}.exe"
    if [ -f "$src" ]; then
      cp "$src" "$out_dir/bin/"
      found=1
    else
      cf::warn "expected binary not found: $src"
    fi
  done
  [ "$found" = "1" ] || cf::die "no binaries produced for $triple"

  cf::add_notice "$out_dir/bin" "$RECIPE"
  cf::archive "$target" "$out_dir/bin" "$OUT"
  cf::endgroup
done

cf::log "rust build complete for $CF_PROJECT $VERSION"
