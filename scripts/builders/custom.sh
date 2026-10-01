#!/usr/bin/env bash
# Escape hatch for projects that don't fit go/rust/bun.
# The recipe provides shell commands that are executed once per target with
# these environment variables available:
#
#   CF_TARGET       e.g. windows-x64
#   CF_TARGET_DIR   where the artifacts must end up
#   CF_VERSION      resolved version string
#   CF_UPSTREAM     path to the upstream checkout
#
# Recipe:
#   "custom": {
#     "build": "make cross TARGET=$CF_TARGET OUT=$CF_TARGET_DIR"
#   }
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

cf::need jq
CF_PROJECT="$(jq -r '.id' "$RECIPE")"
export CF_PROJECT
BUILD_CMD="$(jq -r '.custom.build // empty' "$RECIPE")"
[ -n "$BUILD_CMD" ] || cf::die "custom builder needs .custom.build in the recipe"

PKG_DIR="$UPSTREAM/$(jq -r '.upstream.subdir // "."' "$RECIPE")"

for target in ${TARGETS//,/ }; do
  out_dir="$OUT/${CF_PROJECT}-${target}"
  mkdir -p "$out_dir/bin"
  cf::group "custom build $CF_PROJECT-$target"

  export CF_TARGET="$target"
  export CF_TARGET_DIR="$out_dir/bin"
  export CF_VERSION="$VERSION"
  export CF_UPSTREAM="$PKG_DIR"
  CF_GOOS="$(cf::go_triple "$target" | awk '{print $1}')"
  CF_GOARCH="$(cf::go_triple "$target" | awk '{print $2}')"
  CF_RUST_TRIPLE="$(cf::rust_triple "$target")"
  export CF_GOOS CF_GOARCH CF_RUST_TRIPLE

  ( cd "$PKG_DIR" && eval "$BUILD_CMD" ) || cf::die "custom build failed for $target"

  if [ -z "$(ls -A "$out_dir/bin" 2>/dev/null)" ]; then
    cf::warn "custom build produced nothing in $CF_TARGET_DIR for $target"
    continue
  fi

  cf::add_notice "$out_dir/bin" "$RECIPE"
  cf::archive "$target" "$out_dir/bin" "$OUT"
  cf::endgroup
done

cf::log "custom build complete for $CF_PROJECT $VERSION"
