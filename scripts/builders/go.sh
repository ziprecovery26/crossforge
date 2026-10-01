#!/usr/bin/env bash
# Generic Go builder — pure-Go cross compilation via GOOS/GOARCH.
# Recipe fields:
#   go.package  : package to build (default "./...")   e.g. "./cmd/foo"
#   go.ldflags  : ldflags string
#   go.cgo      : "true" to enable cgo (needs the NDK for android-arm64)
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

cf::need go
cf::need jq

CF_PROJECT="$(jq -r '.id' "$RECIPE")"
export CF_PROJECT
PKG="$(jq -r '.go.package // "./..."' "$RECIPE")"
LDFLAGS="$(jq -r '.go.ldflags // ""' "$RECIPE")"
CGO="$(jq -r '.go.cgo // false' "$RECIPE")"
BIN_NAME="$(jq -r '.custom.binaryName // .id' "$RECIPE")"

PKG_DIR="$UPSTREAM/$(jq -r '.upstream.subdir // "."' "$RECIPE")"
cd "$PKG_DIR"

for target in ${TARGETS//,/ }; do
  read -r goos goarch <<< "$(cf::go_triple "$target")"
  out_dir="$OUT/${CF_PROJECT}-${target}"
  mkdir -p "$out_dir/bin"

  outfile="$out_dir/bin/$BIN_NAME"
  [ "$goos" = "windows" ] && outfile="${outfile}.exe"

  cf::group "building $CF_PROJECT-$target ($goos/$goarch)"

  export GOOS="$goos" GOARCH="$goarch"
  export CGO_ENABLED=0
  if [ "$CGO" = "true" ]; then
    export CGO_ENABLED=1
    if [ "$goos" = "android" ]; then
      [ -n "${ANDROID_NDK_HOME:-}" ] || cf::die "cgo android build needs ANDROID_NDK_HOME (run setup-toolchain with ndk: true)"
      CC_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
      [ -x "$CC_BIN" ] || cf::die "NDK clang not found: $CC_BIN"
      export CC="$CC_BIN" CXX="${CC_BIN}++"
    fi
  fi

  # shellcheck disable=SC2086
  go build -trimpath -buildvcs=false \
    ${LDFLAGS:+-ldflags "$LDFLAGS"} \
    -o "$outfile" "$PKG"

  # A static Go binary runs on musl/Alpine too — note it for users.
  if [ "$goos" = "linux" ] && [ "$CGO_ENABLED" = "0" ]; then
    echo "static binary: also runs on Alpine/musl (Target ID: linux-*-musl)" > "$out_dir/README.musl.txt"
  fi

  cf::add_notice "$out_dir/bin" "$RECIPE"
  cf::archive "$target" "$out_dir/bin" "$OUT"
  cf::endgroup
done

cf::log "go build complete for $CF_PROJECT $VERSION"
