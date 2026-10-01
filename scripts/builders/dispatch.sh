#!/usr/bin/env bash
# CrossForge build dispatcher.
#
#   dispatch.sh --recipe registry/opencode.json --upstream ../work/opencode \
#               --out ../artifacts --targets linux-x64,windows-x64 --version 1.18.34
#
# Reads the recipe, picks the right ecosystem builder, and drops archives +
# raw target directories into --out.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

RECIPE=""
UPSTREAM=""
OUT=""
TARGETS=""
VERSION=""
REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --recipe)   RECIPE="$2"; shift 2 ;;
    --upstream) UPSTREAM="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --targets)  TARGETS="$2"; shift 2 ;;
    --version)  VERSION="$2"; shift 2 ;;
    --ref)      REF="$2"; shift 2 ;;
    *) cf::die "unknown argument: $1" ;;
  esac
done

[ -n "$RECIPE" ]   || cf::die "--recipe is required"
[ -n "$UPSTREAM" ] || cf::die "--upstream is required"
[ -n "$OUT" ]      || cf::die "--out is required"
[ -f "$RECIPE" ]   || cf::die "recipe not found: $RECIPE"
[ -d "$UPSTREAM" ] || cf::die "upstream checkout not found: $UPSTREAM"

mkdir -p "$OUT"

CF_PROJECT="$(jq -r '.id' "$RECIPE")"
export CF_PROJECT
BUILD_SYSTEM="$(jq -r '.buildSystem' "$RECIPE")"
VERSION="${VERSION:-$(jq -r '.upstream.ref // "0.0.0"' "$RECIPE")}"

if [ -z "$TARGETS" ]; then
  TARGETS="$(jq -r '(.defaultTargets // .targets) | join(",")' "$RECIPE")"
fi

cf::group "CrossForge · $CF_PROJECT @ $VERSION"
cf::log "build system : $BUILD_SYSTEM"
cf::log "upstream dir : $UPSTREAM"
cf::log "targets      : $TARGETS"
cf::log "output dir   : $OUT"
cf::endgroup

# ------------------------------------------------------------------------------
# The upstream project is also checked out *inside* the crossforge repo for
# drivers — keep the layout explicit so relative paths in drivers work.
# ------------------------------------------------------------------------------
export CF_UPSTREAM_DIR="$UPSTREAM"
export CF_OUT_DIR="$OUT"
export CF_VERSION="$VERSION"
export CF_REF="$REF"
export CF_ROOT_DIR="$ROOT_DIR"
export CF_TARGETS="$TARGETS"

MONOREPO_PKG_DIR="$(jq -r '.upstream.monorepo.packageDir // empty' "$RECIPE")"
DRIVER_REL="$(jq -r '.upstream.monorepo.buildDriver // empty' "$RECIPE")"

if [ -n "$DRIVER_REL" ]; then
  # ---- Project with a dedicated CrossForge driver (currently: opencode) -------
  cf::log "using dedicated driver: $DRIVER_REL"
  DRIVER_SRC="$ROOT_DIR/$DRIVER_REL"
  DRIVER_DST_REL="$(jq -r '.upstream.monorepo.driverTargetDir // "script/build-matrix.ts"' "$RECIPE")"
  DRIVER_DST="$UPSTREAM/$MONOREPO_PKG_DIR/$DRIVER_DST_REL"
  [ -f "$DRIVER_SRC" ] || cf::die "driver missing: $DRIVER_SRC"
  mkdir -p "$(dirname "$DRIVER_DST")"
  cp "$DRIVER_SRC" "$DRIVER_DST"

  # Android native libs (libopentui.so) supplied by the android job / prebuilt cache
  ANDROID_LIBS="${CF_ANDROID_LIBS_DIR:-}"
  ANDROID_FLAG=""
  if [ -n "$ANDROID_LIBS" ] && [ -f "$ANDROID_LIBS/libopentui.so" ]; then
    cf::log "android native lib found: $ANDROID_LIBS/libopentui.so"
    if file "$ANDROID_LIBS/libopentui.so" | grep -q "ARM aarch64"; then
      cf::log "libopentui.so is aarch64 ✓"
    else
      cf::warn "libopentui.so does NOT look like an aarch64 ELF — the Termux TUI may not load it"
    fi
    ANDROID_FLAG="--opentui-android=$ANDROID_LIBS/libopentui.so"
  elif echo ",$TARGETS," | grep -q ",android-arm64,"; then
    cf::warn "android-arm64 requested but no libopentui.so available — binary will build, TUI will need the lib at runtime"
  fi

  PKG_DIR="$UPSTREAM/$MONOREPO_PKG_DIR"

  # ---- dependencies -----------------------------------------------------------
  # Bun workspaces hoist node_modules to the repo root, isliye install wahan hota hai.
  INSTALL_DIR="$PKG_DIR"
  if [ -f "$UPSTREAM/bun.lock" ] || [ -f "$UPSTREAM/bun.lockb" ]; then
    INSTALL_DIR="$UPSTREAM"
  fi
  if [ ! -d "$INSTALL_DIR/node_modules" ]; then
    cf::group "bun install ($INSTALL_DIR)"
    ( cd "$INSTALL_DIR" && bun install --frozen-lockfile ) \
      || ( cd "$INSTALL_DIR" && cf::warn "frozen install failed, retry without lockfile" && bun install )
    cf::endgroup
  else
    cf::log "node_modules already present — skipping install"
  fi

  (
    cd "$PKG_DIR"
    # export the env the upstream build script expects
    export OPENCODE_VERSION="${CF_VERSION}"
    export OPENCODE_CHANNEL="${CF_CHANNEL:-latest}"
    # shellcheck disable=SC2086
    bun run script/build-matrix.ts --targets="$CF_TARGETS" $ANDROID_FLAG ${CF_DRIVER_EXTRA_FLAGS:-} 
  )

  DIST_DIR="$PKG_DIR/dist"
  [ -d "$DIST_DIR" ] || cf::die "driver produced no dist/ directory"

  for d in "$DIST_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    target="${name#"$CF_PROJECT"-}"
    cf::log "collecting $name (target=$target)"
    raw_out="$OUT/$name"
    rm -rf "$raw_out"           # replace the (currently empty) placeholder
    mkdir -p "$raw_out"
    cp -a "$d"/. "$raw_out"/
    if cf::is_android_target "$target"; then
      # Termux layout: bin/opencode.bin + bin/opencode (wrapper) + lib/libopentui.so
      cf::add_notice "$raw_out" "$RECIPE"
      cf::archive "$target" "$raw_out" "$OUT"
      cf::log "android layout: $(ls -1 "$raw_out")"
    else
      cf::add_notice "$raw_out/bin" "$RECIPE"
      cf::archive "$target" "$raw_out/bin" "$OUT"
    fi
  done
else
  # ---- Generic builders -------------------------------------------------------
  case "$BUILD_SYSTEM" in
    bun)  bash "$SCRIPT_DIR/bun.sh"   --recipe "$RECIPE" --upstream "$UPSTREAM" --out "$OUT" --targets "$TARGETS" --version "$VERSION" ;;
    go)   bash "$SCRIPT_DIR/go.sh"    --recipe "$RECIPE" --upstream "$UPSTREAM" --out "$OUT" --targets "$TARGETS" --version "$VERSION" ;;
    rust) bash "$SCRIPT_DIR/rust.sh"  --recipe "$RECIPE" --upstream "$UPSTREAM" --out "$OUT" --targets "$TARGETS" --version "$VERSION" ;;
    *)    bash "$SCRIPT_DIR/custom.sh" --recipe "$RECIPE" --upstream "$UPSTREAM" --out "$OUT" --targets "$TARGETS" --version "$VERSION" ;;
  esac
fi

cf::checksums "$OUT"
cf::log "done: $CF_PROJECT $VERSION → $OUT"
