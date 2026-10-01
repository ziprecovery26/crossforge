#!/usr/bin/env bash
# CrossForge shared helpers — sourced by every builder script.
# shellcheck shell=bash

set -euo pipefail

CF_LOG_PREFIX="${CF_LOG_PREFIX:-crossforge}"

cf::log()  { printf '\033[1;36m[%s]\033[0m %s\n' "$CF_LOG_PREFIX" "$*"; }
cf::warn() { printf '\033[1;33m[%s][warn]\033[0m %s\n' "$CF_LOG_PREFIX" "$*" >&2; }
cf::err()  { printf '\033[1;31m[%s][error]\033[0m %s\n' "$CF_LOG_PREFIX" "$*" >&2; }
cf::die()  { cf::err "$*"; exit 1; }

cf::group() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$*"; else cf::log "$*"; fi
}
cf::endgroup() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi
}

cf::need() {
  command -v "$1" >/dev/null 2>&1 || cf::die "required tool not found: $1"
}

# ---- CrossForge target id -> GOOS/GOARCH -------------------------------------
cf::go_triple() {
  case "$1" in
    linux-x64|linux-x64-baseline|linux-x64-musl|linux-x64-musl-baseline) echo "linux amd64" ;;
    linux-arm64|linux-arm64-musl)  echo "linux arm64" ;;
    windows-x64|windows-x64-baseline) echo "windows amd64" ;;
    windows-arm64)                 echo "windows arm64" ;;
    darwin-x64|darwin-x64-baseline) echo "darwin amd64" ;;
    darwin-arm64)                  echo "darwin arm64" ;;
    android-arm64)                 echo "android arm64" ;;
    *) cf::die "unmapped go target: $1" ;;
  esac
}

# ---- CrossForge target id -> rust triple -------------------------------------
cf::rust_triple() {
  case "$1" in
    linux-x64|linux-x64-baseline)  echo "x86_64-unknown-linux-gnu" ;;
    linux-x64-musl|linux-x64-musl-baseline) echo "x86_64-unknown-linux-musl" ;;
    linux-arm64)                   echo "aarch64-unknown-linux-gnu" ;;
    linux-arm64-musl)              echo "aarch64-unknown-linux-musl" ;;
    windows-x64|windows-x64-baseline) echo "x86_64-pc-windows-gnu" ;;
    windows-arm64)                 echo "aarch64-pc-windows-gnullvm" ;;
    darwin-x64|darwin-x64-baseline) echo "x86_64-apple-darwin" ;;
    darwin-arm64)                  echo "aarch64-apple-darwin" ;;
    android-arm64)                 echo "aarch64-linux-android" ;;
    *) cf::die "unmapped rust target: $1" ;;
  esac
}

# ---- CrossForge target id -> Bun --compile target ----------------------------
cf::bun_target() {
  case "$1" in
    linux-x64)                echo "bun-linux-x64" ;;
    linux-x64-baseline)       echo "bun-linux-x64-baseline" ;;
    linux-arm64)              echo "bun-linux-arm64" ;;
    linux-x64-musl)           echo "bun-linux-x64-musl" ;;
    linux-x64-musl-baseline)  echo "bun-linux-x64-musl-baseline" ;;
    linux-arm64-musl)         echo "bun-linux-arm64-musl" ;;
    darwin-x64)               echo "bun-darwin-x64" ;;
    darwin-x64-baseline)      echo "bun-darwin-x64-baseline" ;;
    darwin-arm64)             echo "bun-darwin-arm64" ;;
    windows-x64)              echo "bun-windows-x64" ;;
    windows-x64-baseline)     echo "bun-windows-x64-baseline" ;;
    windows-arm64)            echo "bun-windows-arm64" ;;
    # Android/Termux — official Bun >= 1.4.x runtime target (bionic libc)
    android-arm64)            echo "bun-linux-arm64-android" ;;
    *) cf::die "unmapped bun target: $1" ;;
  esac
}

cf::is_windows_target() { case "$1" in windows-*) return 0 ;; *) return 1 ;; esac; }
cf::is_android_target() { case "$1" in android-*) return 0 ;; *) return 1 ;; esac; }

# ---- archive a directory ------------------------------------------------------
# cf::archive <target-id> <dir> <out-dir>
cf::archive() {
  local target="$1" dir="$2" out="$3"
  mkdir -p "$out"
  if cf::is_windows_target "$target"; then
    ( cd "$dir" && zip -qr "$out/${CF_PROJECT}-${target}.zip" . )
    cf::log "archived $out/${CF_PROJECT}-${target}.zip"
  else
    ( cd "$dir" && tar -czf "$out/${CF_PROJECT}-${target}.tar.gz" . )
    cf::log "archived $out/${CF_PROJECT}-${target}.tar.gz"
  fi
}

# ---- checksums ----------------------------------------------------------------
cf::checksums() {
  local out="$1"
  ( cd "$out" && find . -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.deb' -o -name '*.pkg.tar.xz' -o -name '*.sh' -o -name '*.ps1' \) -printf '%f\n' \
    | sort | xargs -r sha256sum > SHA256SUMS )
  cf::log "wrote $out/SHA256SUMS"
  cat "$out/SHA256SUMS" 2>/dev/null || true
}

# ---- provenance NOTICE + LICENSE copy -----------------------------------------
# cf::add_notice <target-dir> <recipe.json>
cf::add_notice() {
  local dir="$1" recipe="$2"
  local id repo ref license commit
  id="$(jq -r '.id' "$recipe")"
  repo="$(jq -r '.upstream.repo' "$recipe")"
  ref="$(jq -r '.upstream.ref' "$recipe")"
  license="$(jq -r '.license.spdx' "$recipe")"
  commit="${CF_UPSTREAM_COMMIT:-unknown}"

  # upstream LICENSE file, if the checkout has one
  for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
    if [ -f "$CF_UPSTREAM_DIR/$f" ]; then
      cp "$CF_UPSTREAM_DIR/$f" "$dir/LICENSE"
      break
    fi
  done

  cat > "$dir/NOTICE.md" <<EOF
# NOTICE — $id binary

This binary was **built from public source code by CrossForge**, an
automated cross-compilation pipeline. It is not an official upstream release
unless the upstream project says so.

| field | value |
|---|---|
| project | \`$repo\` |
| source ref | \`$ref\` |
| source commit | \`$commit\` |
| upstream license | \`$license\` |
| built at (UTC) | \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\` |
| built by | CrossForge GitHub Actions (\`${GITHUB_REPOSITORY:-unknown}\`, run \`${GITHUB_RUN_ID:-local}\`) |
| toolchain | bun \`$(bun --version 2>/dev/null || echo n/a)\`, node \`$(node --version 2>/dev/null || echo n/a)\`, go \`$(go version 2>/dev/null | awk '{print $3}' || echo n/a)\` |

Source: https://github.com/$repo
Build logs: https://github.com/${GITHUB_REPOSITORY:-ziprecovery26/crossforge}/actions/runs/${GITHUB_RUN_ID:-0}

This artifact is redistributed under the terms of the upstream license shown
above. CrossForge claims no copyright over the compiled program.
EOF
  cf::log "wrote NOTICE.md + LICENSE into $(basename "$dir")"
}

# ---- JSON helper (jq is guaranteed by setup-toolchain) ------------------------
cf::json() {
  cf::need jq
  jq -r "$1" "$2"
}
