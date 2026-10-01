# 🎯 Build matrix — target IDs

Har target ka ek **id** hota hai. Wahi id `--targets` mein, recipe mein aur matrix mein use hoti hai,
aur artifact ka naam bhi usi se banta hai: `<project>-<target>.tar.gz|zip`.

| id | OS / libc | arch | note |
|---|---|---|---|
| `linux-x64` | Linux / glibc | x86_64 | AVX2 (modern CPUs) |
| `linux-x64-baseline` | Linux / glibc | x86_64 | purane CPUs (no AVX2) |
| `linux-arm64` | Linux / glibc | aarch64 | Raspberry Pi 4/5, ARM servers |
| `linux-x64-musl` | Linux / musl | x86_64 | Alpine, Docker scratch |
| `linux-x64-musl-baseline` | Linux / musl | x86_64 | old CPUs + Alpine |
| `linux-arm64-musl` | Linux / musl | aarch64 | Alpine on ARM |
| `darwin-x64` | macOS | x86_64 | Intel Macs |
| `darwin-x64-baseline` | macOS | x86_64 | older Intel |
| `darwin-arm64` | macOS | aarch64 | Apple Silicon |
| `windows-x64` | Windows | x86_64 | ASI |
| `windows-x64-baseline` | Windows | x86_64 | no AVX2 |
| `windows-arm64` | Windows | aarch64 | Snapdragon X, Surface Pro X |
| `android-arm64` | Android / bionic | aarch64 | Termux, min Android 7 |

## Ecosystem support

| target | Bun (`--compile`) | Go | Rust (`cargo zigbuild`) |
|---|---|---|---|
| linux-x64 | ✅ | ✅ | ✅ |
| linux-x64-baseline | ✅ | ✅ (same as x64) | ✅ |
| linux-arm64 | ✅ | ✅ | ✅ |
| linux-x64-musl | ✅ | ✅ (static, covered by `linux-x64`) | ✅ |
| linux-arm64-musl | ✅ | ✅ (static) | ✅ |
| darwin-x64 / arm64 | ✅ | ✅ | ✅ (zig linker) |
| windows-x64 / arm64 | ✅ | ✅ | ⚠️ gnu target (`*-pc-windows-gnu`) |
| android-arm64 | ✅ (Bun ≥1.4) | ✅ (`CGO_ENABLED=0`) / ⚠️ cgo needs NDK | ⚠️ needs NDK + `aarch64-linux-android` target |

Legend: ✅ works out of the box · ⚠️ works with extra toolchain (NDK/sysroot)

## Bun target mapping (internal)

```
linux-x64              → bun-linux-x64
linux-x64-baseline     → bun-linux-x64-baseline
linux-arm64            → bun-linux-arm64
linux-x64-musl         → bun-linux-x64-musl
linux-x64-musl-baseline→ bun-linux-x64-musl-baseline
linux-arm64-musl       → bun-linux-arm64-musl
darwin-x64 / arm64     → bun-darwin-x64 / bun-darwin-arm64
windows-x64 / arm64    → bun-windows-x64 / bun-windows-arm64
android-arm64          → bun-linux-arm64-android      ← Bun 1.4+
```

## Go mapping

`GOOS`/`GOARCH` pairs: `linux/amd64`, `linux/arm64`, `windows/amd64`, `windows/arm64`,
`darwin/amd64`, `darwin/arm64`, `android/arm64` (cgo → NDK).

`CGO_ENABLED=0` wale Go binaries **static** hote hain → ek hi artifact glibc aur musl dono par chalta hai.

## Rust mapping

`cargo zigbuild` se: `x86_64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`,
`aarch64-unknown-linux-musl`, `aarch64-unknown-linux-gnu`, `x86_64-pc-windows-gnu`,
`aarch64-pc-windows-gnullvm`, `x86_64-apple-darwin`, `aarch64-apple-darwin`,
`aarch64-linux-android` (NDK sysroot chahiye).

## Recipe example (Go project)

```json
{
  "id": "ripgrep",
  "upstream": { "repo": "BurntSushi/ripgrep", "ref": "14.1.1", "refStrategy": "pinned" },
  "buildSystem": "rust",
  "license": { "spdx": "MIT", "redistributable": true },
  "rust": { "bins": ["rg"] },
  "targets": ["linux-x64", "linux-arm64", "windows-x64", "darwin-arm64", "android-arm64"],
  "defaultTargets": ["linux-x64", "windows-x64", "android-arm64"],
  "nightly": false,
  "enabled": true
}
```

## Kaun se targets default hote hain?

`defaultTargets` set na ho to `targets` ka poora set chalta hai. Sab targets build karna
CI minutes khaata hai (12 targets ≈ 40–60 min, sharded). Practical default:

```json
"defaultTargets": ["linux-x64", "linux-arm64", "linux-x64-musl", "windows-x64", "darwin-arm64", "android-arm64"]
```
