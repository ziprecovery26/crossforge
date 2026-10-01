<div align="center">

# 🔨 CrossForge

### Universal Open-Source Binary Farm
**Ek repo, jahan se tumhare pasandida open-source project ke pre-built binaries milte hain — Windows, Linux, macOS aur Android/Termux ke liye.**

[![Build](https://img.shields.io/github/actions/workflow/status/ziprecovery26/crossforge/opencode-release.yml?style=flat-square&label=builds)](../../actions)
[![Nightly](https://img.shields.io/github/actions/workflow/status/ziprecovery26/crossforge/nightly-rebuild.yml?style=flat-square&label=nightly)](../../actions)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Requests](https://img.shields.io/github/issues/ziprecovery26/crossforge/build-request?style=flat-square&label=requests)](../../issues)

</div>

---

## Yeh kya hai? (Hinglish tl;dr)

CrossForge ek **automated cross-compile platform** hai. Tum ek **Issue** kholte ho aur likhte ho:

> "Bhai, `<project>` ko mere phone/PC ke liye build kar do."

Humara bot:
1. Project ka **license verify** karta hai (sirf open-source / OSI-approved projects),
2. **GitHub Actions** ke powerful runners (Microsoft ke servers, 4-core + **swap memory** enabled) par fresh clone karke
   **cross-compile** karta hai,
3. Binaries ko **GitHub Release** + **Actions artifacts** mein publish karta hai,
4. Aur tumhare issue par **comment** karke download link de deta hai.

Sab kuch **100% GitHub ke servers par** hota hai — koi manual binary upload nahi, koi third-party build server nahi,
pura **build provenance** Actions logs mein public hota hai.

> **Pehla official target: [`opencode`](https://github.com/anomalyco/opencode)** — the open source AI coding agent.
> Agar tum is repo ko fork karke chalate ho, to pehla binary automatically opencode ka ban jayega.

---

## 📦 Supported build targets

| Platform | Target IDs | Runtime support |
|---|---|---|
| 🪟 Windows | `windows-x64`, `windows-x64-baseline`, `windows-arm64` | Bun · Go · Rust |
| 🐧 Linux (glibc) | `linux-x64`, `linux-x64-baseline`, `linux-arm64` | Bun · Go · Rust |
| 🐧 Linux (musl/Alpine) | `linux-x64-musl`, `linux-x64-musl-baseline`, `linux-arm64-musl` | Bun · Go · Rust |
| 🍎 macOS | `darwin-x64`, `darwin-x64-baseline`, `darwin-arm64` | Bun · Go · Rust |
| 📱 Android / Termux (aarch64) | `android-arm64` | Bun (official `bun-linux-arm64-android` runtime) · Go |

> **Note:** `baseline` = purane CPUs (no AVX2) ke liye. Android target bionic libc use karta hai — glibc binaries Android par **nahi** chalte.

---

## 🚀 Quick start

### opencode (flagship binary)

**Linux / macOS**
```bash
curl -fsSL https://github.com/ziprecovery26/crossforge/releases/latest/download/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://github.com/ziprecovery26/crossforge/releases/latest/download/install.ps1 | iex
```

**Android / Termux**
```bash
pkg install curl
curl -fsSL https://github.com/ziprecovery26/crossforge/releases/latest/download/termux-install.sh | bash
```

**Manual download:** [`Releases`](../../releases) → apne platform ka archive uthao → `opencode-<target>` folder mein binary hai.

---

## 🙋 Apna project request karo (step by step)

1. **Issues → New Issue → 🔨 Build Request** kholo.
2. Form bharo: project ka repo URL, exact tag/commit, konsa build system, kaunse targets chahiye.
3. Ek maintainer request ko `cf:approved` label deta hai (license + safety check ke baad).
4. `build-request.yml` workflow chalu ho jata hai → build → release → **issue par result comment**.

**Rules:**

| ✅ Build hoga | ❌ Build nahi hoga |
|---|---|
| OSI-approved open-source license (MIT, Apache-2.0, BSD, GPL, MPL, ISC, Unlicense…) | Closed-source / koi license nahi |
| Build system repo mein public hai | Prebuilt proprietary blobs jodkar distribute karna |
| Upstream project ke redistribution terms respect hote hain | License dene wala project `no-redistribution` bolta ho |
| Reproducible: hum foran source se build karte hain | Malware / credential stealer / abuse |

Details: [`docs/REQUEST-FLOW.md`](docs/REQUEST-FLOW.md) · Supported ecosystems: [`docs/BUILD-MATRIX.md`](docs/BUILD-MATRIX.md)

---

## ⚙️ Yeh repo kaise kaam karta hai

```
                        ┌───────────────────────────────┐
   Issue (Build Request)│  license-verify  → allow/deny │
        │               └───────────────────────────────┘
        ▼                            │ pass
  cf:approved label                  ▼
        │                ┌────────────────────────────────────────────┐
        └───────────────►│  GitHub Actions (ubuntu / windows runners) │
                         │  • setup-swap  → 4–8 GB swap (memory safe) │
                         │  • setup-bun / rust / go / zig / NDK       │
                         │  • clone upstream @ pinned ref             │
                         │  • cross-compile → 12+ targets             │
                         │  • smoke test (native runner only)         │
                         └────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼────────────────────┐
                    ▼                   ▼                    ▼
            Actions artifacts     GitHub Release        Issue comment
            (90-day retention)    (binaries + SHA256)   (links + logs)
```

**Daily fresh builds:** [`nightly-rebuild.yml`](.github/workflows/nightly-rebuild.yml) har raat **03:00 UTC** par chalta hai,
upstream ke naye commits/tags dekhta hai, aur sabhi registered projects ke **fresh binaries** banata hai.
Purane build artifacts ke bajaye nightly release tag (`nightly-YYYY.MM.DD`) par publish hota hai.

---

## 🗂️ Repo layout

```
crossforge/
├── registry/                 # approved projects ka catalog (JSON recipes)
│   ├── index.json            #   index — kaun-kaun supported hai
│   └── opencode.json         #   recipe: repo, ref, build system, targets
├── drivers/opencode/         # opencode ke liye cross-compile driver (build-matrix.ts)
├── scripts/
│   ├── handle-request.ts     # issue → verify → dispatch
│   ├── lib/license-verify.ts # SPDX allowlist checker
│   └── builders/             # go.sh · rust.sh · bun.sh · generic.sh
├── android/opentui/          # NDK se libopentui.so build (Termux TUI ke liye)
├── termux/                   # Termux installer + .deb / pacman packaging
└── .github/workflows/        # sab kuch yahin chalta hai
```

---

## 🔐 Trust & safety

* Har binary **public GitHub Actions runner** par, **public source** se build hota hai — logs sabke liye khule hain.
* Releases ke saath **`SHA256SUMS`** file aati hai, aur (jab available ho) **artifact attestations** bhi.
* Hum **kabhi** prebuilt binary ko source ke bina publish nahi karte.
* Build fail hone par hum "jhoothi success" nahi dikhate — issue par saaf `❌ build failed` comment + log link jata hai.

---

## ✅ Verification status (honest disclosure)

Yeh repo *kaam karta hai* aur uske components locally verify kiye gaye hain, lekin poora
binary pipeline **GitHub Actions par** chalta hai (yahi design hai). Kaun-kya verified hai:

| cheez | status |
|---|---|
| Workflows YAML + expression + action inputs | ✅ **actionlint clean** (43 self-test checks pass) |
| Shell scripts (builders, packaging, installers) | ✅ **shellcheck clean** (warning level) |
| Issue-form parser + recipe generator | ✅ tested with a real issue-form fixture |
| Termux packaging (zip / `.deb` / pacman) | ✅ actually built & inspected locally |
| Target → toolchain mapping (Bun/Go/Rust) | ✅ unit-tested in `scripts/self-test.sh` |
| Bun cross-compile targets (windows/linux/musl/**android**) | ✅ verified that `bun build --compile --target=...` produces valid ELF/Mach-O/PE for each |
| Full opencode binary | ⏳ **CI par** — 12 targets, ~20–40 min (dev sandbox me sirf 2 GB RAM tha, bundler OOM ho gaya — isliye swap-enabled runners) |
| `libopentui.so` (android TUI lib) | ⚠️ best-effort — NDK+Zig job CI me chalta hai; upstream layout badla to fail hote hi saaf warning deta hai |

Apne aap check karo:

```bash
bash scripts/self-test.sh      # 43 checks, sab local
```

## 📄 License

Repo ka apna code: **MIT** — [`LICENSE`](LICENSE).
Har published binary apne upstream project ke license ke under aata hai (`registry/<project>.json` mein `license` field dekho).
Hum upstream projects ke code ka ownership claim nahi karte; hum sirf unhe build karke distribute karte hain jahan license allow karta hai.

<div align="center">

**Made for the open-source community · Fork karo, apna binary farm banao 🚀**

</div>
