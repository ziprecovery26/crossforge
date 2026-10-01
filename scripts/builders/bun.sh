#!/usr/bin/env bash
# Generic Bun builder — `bun build --compile` for every CrossForge target.
# Recipe fields used:
#   custom.build      : entrypoint file (relative to upstream root), e.g. "src/index.ts"
#   custom.binaryName : output binary name (default: project id)
#   custom.installCmd : override install command (default: bun install)
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

cf::need bun
cf::need jq

CF_PROJECT="$(jq -r '.id' "$RECIPE")"
export CF_PROJECT
ENTRY="$(jq -r '.custom.build // empty' "$RECIPE")"
BIN_NAME="$(jq -r '.custom.binaryName // .id' "$RECIPE")"
INSTALL_CMD="$(jq -r '.custom.installCmd // "bun install"' "$RECIPE")"
EXTRA_DEFINES="$(jq -r '.custom.defines // {} | to_entries | map("--define \(.key)=\(.value|tojson)") | join(" ")' "$RECIPE")"

[ -n "$ENTRY" ] || cf::die "bun builder needs .custom.build (entrypoint) in the recipe"

PKG_DIR="$UPSTREAM/$(jq -r '.upstream.subdir // "."' "$RECIPE")"
cd "$PKG_DIR"

cf::group "bun install"
if [ ! -d node_modules ]; then
  eval "$INSTALL_CMD"
fi
cf::endgroup

for target in ${TARGETS//,/ }; do
  bun_target="$(cf::bun_target "$target")"
  out_dir="$OUT/${CF_PROJECT}-${target}"
  cf::group "building $CF_PROJECT-$target ($bun_target)"
  mkdir -p "$out_dir/bin"

  outfile="$out_dir/bin/$BIN_NAME"
  cf::is_windows_target "$target" && outfile="${outfile}.exe"

  bun build \
    --compile \
    --minify \
    --sourcemap=none \
    --target="$bun_target" \
    --outfile "$outfile" \
    --define "CF_VERSION=\"$VERSION\"" \
    $EXTRA_DEFINES \
    "$ENTRY" 2>&1 | tail -20 || cf::die "bun build failed for $target"

  if cf::is_windows_target "$target"; then
    cf::log "produced $(ls -la "$out_dir/bin" | tail -1)"
  else
    chmod +x "$outfile"
  fi

  cf::add_notice "$out_dir/bin" "$RECIPE"
  cf::archive "$target" "$out_dir/bin" "$OUT"
  cf::endgroup
done

cf::log "bun build complete for $CF_PROJECT $VERSION"
