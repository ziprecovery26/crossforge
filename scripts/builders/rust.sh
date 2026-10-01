#!/usr/bin/env bash
# Generic Rust builder — cross compilation through cargo-zigbuild + zig.
#
# Recipe fields:
#   rust.bins     : array of [[bin]] names. Khaali chhodo to auto-detect
#                   (saare executables jo build ke baad target/<triple>/release me aaye).
#   rust.features : comma separated features
#   rust.no-default-features : "true" to pass --no-default-features
#
# Behaviour: ek target fail hone par baaki targets rukte nahi. Job sirf tab fail hoti hai
# jab *koi bhi* target build na ho. Failed targets ka summary print hota hai.
set -uo pipefail

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
declare -a BINS=()
while IFS= read -r line; do [ -n "$line" ] && BINS+=("$line"); done < <(jq -r '(.rust.bins // [])[]' "$RECIPE")
FEATURES="$(jq -r '.rust.features // empty' "$RECIPE")"
NO_DEFAULT="$(jq -r '.["rust"]["no-default-features"] // false' "$RECIPE")"

PKG_DIR="$UPSTREAM/$(jq -r '.upstream.subdir // "."' "$RECIPE")"
cd "$PKG_DIR" || cf::die "upstream subdir not found: $PKG_DIR"

# Prefer cargo-zigbuild (no macOS machine needed for darwin targets). Fall back
# to plain cargo when zig isn't available.
# `cargo zigbuild` is a cargo *subcommand*; plain cargo needs the `build` word.
CMDLINE=(cargo build)
if command -v cargo-zigbuild >/dev/null 2>&1 && command -v zig >/dev/null 2>&1 && zig version >/dev/null 2>&1; then
  CMDLINE=(cargo zigbuild)
  cf::log "using cargo-zigbuild ($(cargo-zigbuild --version 2>/dev/null | head -1)) + zig $(zig version)"
elif command -v cargo-zigbuild >/dev/null 2>&1; then
  cf::warn "cargo-zigbuild mila par zig nahi — plain cargo use kar raha hoon (arm64/windows targets fail ho sakte hain)"
else
  cf::warn "cargo-zigbuild nahi mila — plain cargo use kar raha hoon (host-only linking)"
fi

if [ "${#BINS[@]}" -gt 0 ]; then
  cf::log "binary names from recipe: ${BINS[*]}"
else
  cf::log "no rust.bins in recipe — saare binaries auto-detect honge"
fi

FAILED=()
BUILT=()

for target in ${TARGETS//,/ }; do
  triple="$(cf::rust_triple "$target")"
  out_dir="$OUT/${CF_PROJECT}-${target}"
  rm -rf "$out_dir"; mkdir -p "$out_dir/bin"

  cf::group "building $CF_PROJECT-$target ($triple)"

  rustup target add "$triple" >/dev/null 2>&1 || cf::warn "rustup target add $triple failed (may already be installed)"

  # Android needs the NDK-provided compiler wrappers for C dependencies.
  if [ "$triple" = "aarch64-linux-android" ] && [ -n "${ANDROID_NDK_HOME:-}" ]; then
    NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    export CC_aarch64_linux_android="$NDK_BIN/aarch64-linux-android24-clang"
    export CXX_aarch64_linux_android="$NDK_BIN/aarch64-linux-android24-clang++"
    export AR_aarch64_linux_android="$NDK_BIN/llvm-ar"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_BIN/aarch64-linux-android24-clang"
    cf::log "android NDK env set (API 24)"
  fi

  extra=()
  [ -n "$FEATURES" ] && extra+=(--features "$FEATURES")
  [ "$NO_DEFAULT" = "true" ] && extra+=(--no-default-features)
  if [ "${#BINS[@]}" -eq 0 ]; then extra+=(--bins); fi

  # shellcheck disable=SC2086
  if ! "${CMDLINE[@]}" --release --target "$triple" "${extra[@]}"; then
    cf::err "rust build failed for $triple"
    cf::endgroup
    FAILED+=("$target")
    rmdir "$out_dir/bin" "$out_dir" 2>/dev/null || true
    continue
  fi

  release_dir="target/$triple/release"
  copied=0

  if [ "${#BINS[@]}" -gt 0 ]; then
    for bin in "${BINS[@]}"; do
      src="$release_dir/$bin"
      [ -f "${src}.exe" ] && src="${src}.exe"
      if [ -f "$src" ]; then
        cp "$src" "$out_dir/bin/"
        copied=$((copied + 1))
      else
        cf::warn "expected binary not found: $src"
      fi
    done
  fi

  # Auto-detect: executables in the release dir (skip build metadata/artifacts)
  if [ "$copied" -eq 0 ]; then
    while IFS= read -r f; do
      b="$(basename "$f")"
      case "$b" in
        *.d|*.rlib|*.rmeta|*.so|*.dylib|*.dll|*.a|*.dSYM|*.pdb|*.exp|*.lib|*.o) continue ;;
      esac
      cp "$f" "$out_dir/bin/" && {
        cf::log "auto-detected binary: $b"
        copied=$((copied + 1))
      }
    done < <(find "$release_dir" -maxdepth 1 -type f -perm -u+x 2>/dev/null | sort)
  fi

  if [ "$copied" -eq 0 ]; then
    cf::err "no binaries produced for $triple"
    cf::endgroup
    FAILED+=("$target")
    rm -rf "$out_dir"
    continue
  fi

  cf::add_notice "$out_dir/bin" "$RECIPE"
  cf::archive "$target" "$out_dir/bin" "$OUT"
  BUILT+=("$target")
  cf::endgroup
done

# ---- summary ------------------------------------------------------------------
cf::log "built (${#BUILT[@]}): ${BUILT[*]:-none}"
if [ "${#FAILED[@]}" -gt 0 ]; then
  cf::warn "failed (${#FAILED[@]}): ${FAILED[*]}"
fi

if [ "${#BUILT[@]}" -eq 0 ]; then
  cf::die "har target fail hua ($CF_PROJECT $VERSION) — recipe/toolchain check karo"
fi

cf::log "rust build complete for $CF_PROJECT $VERSION"
