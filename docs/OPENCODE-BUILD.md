# 🔨 opencode — cross-platform build (flagship)

CrossForge ka pehla aur reference build. `opencode` Bun par chalta hai aur `bun build --compile`
se single-file binaries banata hai, isliye ek hi Linux runner se saare platforms cross-compile ho jate hain.

## Driver

`drivers/opencode/build-matrix.ts` — upstream ke `packages/opencode/script/build.ts` (MIT) par based,
plus teen cheezein:

1. **`--targets=` selector** → CI ek shard mein targets ka subset build kar sakta hai.
2. **`android-arm64` target** → Bun ke official `bun-linux-arm64-android` runtime ke saath.
3. **Termux packaging layout** → `bin/opencode` (wrapper) + `bin/opencode.bin` + `lib/libopentui.so`.

Build ke waqt yeh defines set hote hain (upstream ke same):

| define | value |
|---|---|
| `OPENCODE_VERSION` | resolved version (e.g. `1.18.34`) |
| `OPENCODE_CHANNEL` | `latest` (release) / `nightly` |
| `OPENCODE_MODELS_DEV` | models.dev ka snapshot (network se build-time par) |
| `OPENCODE_LIBC` / `OPENTUI_LIBC` | `glibc` / `musl` / android |
| `FFF_LIBC` | `gnu` / `musl` / `bionic` |
| `OTUI_TREE_SITTER_WORKER_PATH` | bunfs ke andar worker path |
| `OPENCODE_WORKER_PATH` | TUI worker entry |

## Target list

```
linux-x64              linux-x64-baseline     linux-arm64
linux-x64-musl         linux-x64-musl-baseline linux-arm64-musl
darwin-x64             darwin-x64-baseline    darwin-arm64
windows-x64            windows-x64-baseline   windows-arm64
android-arm64          ← Termux (bionic, aarch64)
```

Default release set (recipe ka `defaultTargets`): 8 targets — linux x64/arm64, musl x64/arm64,
windows x64/arm64, darwin-arm64, android-arm64.

## Local build (agar tumhare machine par RAM hai)

```bash
git clone https://github.com/anomalyco/opencode && cd opencode
bun install
cp <crossforge>/drivers/opencode/build-matrix.ts packages/opencode/script/build-matrix.ts
cd packages/opencode

export OPENCODE_CHANNEL=latest OPENCODE_VERSION=1.18.34
bun run script/build-matrix.ts --targets=linux-x64 --skip-embed-web-ui
./dist/opencode-linux-x64/bin/opencode --version
```

> ⚠️ **RAM:** poora 12-target matrix ek 8 GB+ RAM machine maangta hai. 2 GB wale sandbox par
> Bun bundler OOM ho jata hai — isi liye CrossForge GitHub runners (16 GB + 8 GB swap) use karta hai.

## Android specifics

| step | kya hota hai |
|---|---|
| runtime | Bun 1.4.x official `bun-linux-arm64-android` target |
| binary | `bin/opencode.bin` (aarch64 ELF, PIE, bionic) |
| launcher | `bin/opencode` (bash) → `LD_LIBRARY_PATH` + `OPENTUI_LIB_PATH` set karke exec |
| TUI lib | `lib/libopentui.so` — hun `android/opentui/build-opentui-android.sh` se (NDK + Zig) |
| web UI | android build mein embed nahi hota (artifact chhota rakhne ke liye, aur wahan TUI primary hai) |
| min Android | 7.0 (API 24), sirf aarch64 |

Detail: [`TERMUX.md`](TERMUX.md).

## Upstream badla to kya karein?

1. `git diff` dekho upstream ke `packages/opencode/script/build.ts` mein (targets, defines, files)।
2. Driver ko accordingly update karo (`drivers/opencode/build-matrix.ts`).
3. `registry/opencode.json` mein `upstream.ref` update karo (ya `latest-tag-or-branch` chhodo).
4. Nightly automatically naya commit pakad lega (`.state/last-built.json` diff).

## Release output (udaharan)

```
opencode-linux-x64.tar.gz
opencode-linux-x64-musl.tar.gz
opencode-linux-arm64.tar.gz
opencode-windows-x64.zip
opencode-windows-arm64.zip
opencode-darwin-arm64.tar.gz
opencode-android-arm64.tar.gz        ← bin/opencode, bin/opencode.bin, lib/libopentui.so
SHA256SUMS
install.sh · install.ps1 · termux-install.sh
```
