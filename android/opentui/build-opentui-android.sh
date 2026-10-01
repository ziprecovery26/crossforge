#!/usr/bin/env bash
# Builds libopentui.so for Android aarch64 (Termux) from the OpenTUI Zig sources.
#
# Why this exists:
#   @opentui/core ships prebuilt native libs for linux/macOS/Windows only
#   (there is no @opentui/core-android-arm64 on npm). The Termux TUI therefore
#   needs a bionic-linked libopentui.so built by us.
#
# Usage:
#   build-opentui-android.sh --work /tmp/opentui-src --out ./out [--ref v0.4.5] [--zig 0.15.2]
#
# Output: <out>/libopentui.so   (ELF 64-bit aarch64, bionic)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

OPENTUI_REPO="${OPENTUI_REPO:-https://github.com/anomalyco/opentui}"
# kept in sync with registry/opencode.json -> android.opentui
OPENTUI_REF="${OPENTUI_REF:-v0.4.5}"
ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
NDK_API="${NDK_API:-24}"
WORK="${WORK:-/tmp/opentui-android}"
OUT="${OUT:-$ROOT_DIR/out-android}"

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --out)  OUT="$2";  shift 2 ;;
    --ref)  OPENTUI_REF="$2"; shift 2 ;;
    --zig)  ZIG_VERSION="$2"; shift 2 ;;
    --repo) OPENTUI_REPO="$2"; shift 2 ;;
    *) cf::die "unknown argument: $1" ;;
  esac
done

mkdir -p "$OUT"

# ------------------------------------------------------------------------------
# 1. Zig toolchain (version pinned by opentui's .zig-version)
# ------------------------------------------------------------------------------
install_zig() {
  if command -v zig >/dev/null 2>&1 && zig version | grep -q "^${ZIG_VERSION}"; then
    cf::log "zig $ZIG_VERSION already available ($(command -v zig))"
    return 0
  fi

  local arch os
  case "$(uname -m)" in aarch64|arm64) arch="aarch64" ;; *) arch="x86_64" ;; esac
  case "$(uname -s)" in Darwin) os="macos" ;; *) os="linux" ;; esac

  mkdir -p "$WORK/zig" "$WORK/zigdl"

  # Zig ne 0.14+ me tarball naming badal di: zig-<arch>-<os>-<ver>.tar.xz
  # Isliye pehle official index.json se *exact* URL lete hain, phir fallbacks.
  local url=""
  url="$(curl -fsSL https://ziglang.org/download/index.json 2>/dev/null \
    | jq -r --arg v "$ZIG_VERSION" --arg k "${arch}-${os}" '.[$v][$k].tarball // empty' 2>/dev/null || true)"
  if [ -n "$url" ] && curl -fsI -o /dev/null "$url" 2>/dev/null; then
    cf::log "zig URL (index.json): $url"
  else
    url=""
    for cand in \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-${arch}-${os}-${ZIG_VERSION}.tar.xz" \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-${os}-${arch}-${ZIG_VERSION}.tar.xz"
    do
      if curl -fsI -o /dev/null "$cand" 2>/dev/null; then url="$cand"; break; fi
      cf::warn "404: $cand"
    done
  fi
  [ -n "$url" ] || cf::die "zig ${ZIG_VERSION} ka download URL nahi mila. Available versions: https://ziglang.org/download/"

  cf::log "downloading $url"
  curl -fsSL --retry 3 -o "$WORK/zigdl/zig.tar.xz" "$url" || cf::die "zig download failed"
  tar -xJf "$WORK/zigdl/zig.tar.xz" -C "$WORK/zig" --strip-components=1
  [ -x "$WORK/zig/zig" ] || cf::die "zig binary not found after extract"
  export PATH="$WORK/zig:$PATH"
  if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$WORK/zig" >> "$GITHUB_PATH"; fi
  cf::log "zig installed: $(zig version)"
}

install_zig

# ------------------------------------------------------------------------------
# 2. OpenTUI sources at the ref that matches opencode's @opentui/core pin
# ------------------------------------------------------------------------------
SRC="$WORK/opentui"
if [ ! -d "$SRC/.git" ]; then
  cf::log "cloning $OPENTUI_REPO @ $OPENTUI_REF"
  git clone --depth 1 --branch "$OPENTUI_REF" "$OPENTUI_REPO" "$SRC" \
    || cf::die "could not clone opentui @ $OPENTUI_REF"
fi

# Optional out-of-tree patches (kept in crossforge so upstream stays untouched)
PATCH_DIR="$SCRIPT_DIR/patches"
if compgen -G "$PATCH_DIR/*.patch" > /dev/null; then
  for p in "$PATCH_DIR"/*.patch; do
    cf::log "applying patch $(basename "$p")"
    if ( cd "$SRC" && git apply --verbose "$p" ); then
      cf::log "  ✓ applied"
    elif ( cd "$SRC" && patch -p1 --forward --silent < "$p" ); then
      cf::log "  ✓ applied (patch -p1 fallback)"
    else
      cf::warn "patch failed (continuing without it): $(basename "$p")"
    fi
  done
fi

# Native Zig sources moved around between versions — find them.
ZIG_DIR=""
for cand in "$SRC/packages/native" "$SRC/packages/core/src/zig"; do
  if [ -f "$cand/build.zig" ]; then ZIG_DIR="$cand"; break; fi
done
[ -n "$ZIG_DIR" ] || cf::die "build.zig not found in opentui checkout ($SRC) — did the layout change?"
cf::log "zig project: $ZIG_DIR"

# ------------------------------------------------------------------------------
# 3. Build for aarch64 + bionic. Try several Zig target spellings so we survive
#    Zig's target-query syntax changes across versions.
# ------------------------------------------------------------------------------
CANDIDATES=(
  "aarch64-linux-android.${NDK_API}"
  "aarch64-linux-android"
  "aarch64-linux-android${NDK_API}"
)

# Zig bionic provide nahi karta — NDK se ek "libc kit" file banani padti hai
# jo zig ko `--libc` ke through dete hain (patch 0002 -> b.libc_file).
SYSROOT=""
LIBC_FILE=""
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  NDK_HOST_DIR="$(ls -d "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/ 2>/dev/null | head -1)"
  SYSROOT="${NDK_HOST_DIR%/}/sysroot"
  if [ -d "$SYSROOT" ]; then
    CRT_DIR="$SYSROOT/usr/lib/${ARCH_TRIPLE:-aarch64-linux-android}/${NDK_API}"
    [ -d "$CRT_DIR" ] || CRT_DIR="$(ls -d "$SYSROOT"/usr/lib/aarch64-linux-android/*/ 2>/dev/null | head -1)"
    LIBC_FILE="$WORK/android-libc.txt"
    ARCH_INC="$SYSROOT/usr/include/aarch64-linux-android"
    [ -d "$ARCH_INC" ] || ARCH_INC="$SYSROOT/usr/include"
    cat > "$LIBC_FILE" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$ARCH_INC
crt_dir=${CRT_DIR%/}
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
dynamic_linker=/system/bin/linker64
EOF
    cf::log "android libc kit: $LIBC_FILE"
    cf::log "  sysroot: $SYSROOT"
    cf::log "  sys_include_dir: $ARCH_INC"
    cf::log "  crt_dir: ${CRT_DIR%/}"
    zig libc "$LIBC_FILE" >/dev/null 2>&1 || cf::warn "zig ne libc file validate nahi ki (phir bhi try karenge)"
  else
    cf::warn "NDK sysroot nahi mila: $SYSROOT"
    SYSROOT=""
  fi
else
  cf::warn "ANDROID_NDK_HOME set nahi hai — bionic linking fail hogi"
fi

build_ok=0
for t in "${CANDIDATES[@]}"; do
  args=(-Doptimize=ReleaseFast -Dtarget="$t")
  [ -n "$LIBC_FILE" ] && args+=(-Dandroid-libc="$LIBC_FILE")
  [ -n "$SYSROOT" ] && args+=(-Dandroid-sysroot="$SYSROOT")
  cf::group "zig build ${args[*]}"
  if ( cd "$ZIG_DIR" && zig build "${args[@]}" ); then
    build_ok=1
    cf::log "built with target $t"
    cf::endgroup
    break
  fi
  cf::endgroup
  cf::warn "target '$t' failed, trying next spelling"
done

if [ "$build_ok" != "1" ]; then
  cf::err "zig build failed for every android target spelling."
  cf::err "Common causes: (1) zig version mismatch — opentui pins .zig-version," 
  cf::err "(2) network access needed for build.zig.zon dependencies,"
  cf::err "(3) upstream changed the target query syntax."
  exit 1
fi

# ------------------------------------------------------------------------------
# 4. Collect the shared library
# ------------------------------------------------------------------------------
SO="$(find "$ZIG_DIR/zig-out" -name "libopentui.so*" -type f 2>/dev/null | head -1 || true)"
[ -n "$SO" ] || SO="$(find "$ZIG_DIR" -maxdepth 4 -name "libopentui*.so" -type f 2>/dev/null | head -1 || true)"
[ -n "$SO" ] || cf::die "libopentui.so not found after build"

cp "$SO" "$OUT/libopentui.so"

# Debug info hata do — Termux users mobile data par download karte hain,
# 13 MB -> ~5 MB se farak padta hai. Strip optional hai (fail ho to chalta hai).
LLVM_STRIP=""
for base in "${ANDROID_NDK_HOME:-}" "${NDK_HOME:-}" /opt/android-ndk "$HOME/android-ndk"; do
  [ -n "$base" ] || continue
  if [ -x "$base/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" ]; then
    LLVM_STRIP="$base/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
    break
  fi
done
if [ -z "$LLVM_STRIP" ] && command -v llvm-strip >/dev/null 2>&1; then
  LLVM_STRIP="$(command -v llvm-strip)"
fi
if [ -n "$LLVM_STRIP" ]; then
  BEFORE="$(stat -c %s "$OUT/libopentui.so")"
  if "$LLVM_STRIP" --strip-unneeded "$OUT/libopentui.so" 2>/dev/null; then
    cf::log "stripped: $BEFORE -> $(stat -c %s "$OUT/libopentui.so") bytes"
  else
    cf::warn "llvm-strip failed — unstripped .so ship kar rahe hain"
  fi
else
  cf::warn "llvm-strip nahi mila — unstripped .so ship kar rahe hain"
fi
cf::log "artifact: $(file "$OUT/libopentui.so")"
file "$OUT/libopentui.so" | grep -q "ARM aarch64" || cf::die "produced .so is not aarch64 — refusing to ship"

ls -la "$OUT/libopentui.so"
