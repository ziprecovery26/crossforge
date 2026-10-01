# 📱 Termux / Android (aarch64)

## TL;DR — install

```bash
pkg update && pkg install curl ripgrep
curl -fsSL https://github.com/OWNER/crossforge/releases/latest/download/termux-install.sh | bash
opencode
```

## Yeh kaam kaise karta hai (aur kyun yeh "free" nahi tha)

Android **bionic libc** use karta hai, glibc/musl nahi. Isliye normal Linux binaries Termux
mein **nahi chalte**. OpenCode Bun ka compiled binary hai (`bun build --compile`), to pehle
Bun ka Android support chahiye tha — jo lambe time tak "not planned" tha.

**Ab achhi khabar:** Bun 1.4.x ne official android runtime ship karna shuru kiya hai
(`bun-linux-aarch64-android.zip` release asset), aur `bun build --compile --target=bun-linux-arm64-android`
kaam karta hai. CrossForge yahi use karta hai.

Do cheezein phir bhi solve karni padti hain:

| problem | solution |
|---|---|
| `@opentui/core` ke paas android-arm64 native lib **nahi** hai (npm par sirf linux/mac/win + musl) | hum `libopentui.so` khud Zig + Android NDK se build karte hain — `android/opentui/build-opentui-android.sh` |
| bionic mein dynamic libs ka `dlopen` path alag hota hai | binary ke saath ek bash **launcher** ship karte hain jo `LD_LIBRARY_PATH` + `OPENTUI_LIB_PATH` set karta hai |

## Artifact layout

```
opencode-android-arm64.tar.gz
├── bin/opencode        # launcher (bash) — PATH me install hota hai
├── bin/opencode.bin    # asli compiled binary (bun-linux-arm64-android)
├── lib/libopentui.so   # TUI renderer (bionic aarch64)
├── NOTICE.md           # provenance: commit, license, toolchain, run URL
└── LICENSE
```

Installer ise Termux prefix mein aise rakhta hai:

```
$PREFIX/bin/opencode                     → launcher
$PREFIX/libexec/opencode/opencode.bin    → binary
$PREFIX/lib/libopentui.so                → native lib
```

## `libopentui.so` build (NDK + Zig)

```bash
# GitHub Actions par automatically chalta hai (job: _pipeline → android-libs)
bash android/opentui/build-opentui-android.sh \
     --work /tmp/opentui \
     --out  ./out-android \
     --ref  v0.4.5 \
     --zig  0.15.2
```

Script kya karti hai:

1. `anomalyco/opentui` clone karti hai us ref par jo opencode ke `@opentui/core` pin se match kare
   (recipe: `registry/opencode.json → android.opentui.ref`).
2. Zig (`0.15.2`, upstream ke `.zig-version` se match) download karti hai.
3. `packages/core/src/zig` mein `zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-android.<API>`
   chalati hai (kai target spellings try karti hai, Zig ke syntax changes se bachne ke liye).
4. Output ko verify karti hai: `file` ke hisaab se **ARM aarch64** hona chahiye, warna reject.

**Agar yeh build fail ho jaye** (upstream layout change, Zig version mismatch, etc.):

* workflow **fail nahi hota** — Termux binary bina `libopentui.so` publish hota hai
  (CLI/`opencode run` chalega, par full-screen TUI render nahi hoga).
* fallback options (documented, community-maintained):
  * `@androidtui/core-android-arm64` npm package (Bionic-native OpenTUI build),
  * community Termux packages jo patched Bun + libopentui ship karte hain.
  Hum inhe **pin/verify** karke use karte hain, blindly nahi.

## TUI troubleshooting

| symptom | fix |
|---|---|
| TUI khaali/kalak dikhta hai | `termux-setup-storage`; `echo $TERM` → hona chahiye `xterm-256color` |
| `libopentui.so: cannot open shared object` | file check karo: `ls -la $PREFIX/lib/libopentui.so`; launcher se chalao (`$PREFIX/bin/opencode`) |
| `Permission denied` | `chmod +x $PREFIX/libexec/opencode/opencode.bin` |
| Memory low | bade repos par `--max-old-space-size` style flags kaam nahi karte (Bun hai), par `OPENCODE_DISABLE_*` env vars se features off kar sakte ho |
| 32-bit phone (armv7) | supported nahi — sirf **aarch64** (arm64-v8a) build hota hai |

## Tested config reference

| item | value |
|---|---|
| min Android | 7.0 (API 24) |
| arch | aarch64 (arm64-v8a) |
| runtime | Bun `1.4.2` android target |
| zig | 0.15.2 (opentui `.zig-version`) |
| NDK | r27c |
| deps | `ripgrep`, `bash` (installer `pkg install` kar deta hai) |
