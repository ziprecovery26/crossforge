# 🏗️ Architecture

CrossForge ek **GitHub-Actions-native build farm** hai. Koi server nahi, koi Docker registry nahi —
sab kuch public workflows, public logs aur public releases par.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              TRIGGERS                                        │
│  issue:labeled(cf:approved)   schedule(0 3 * * *)   workflow_dispatch         │
└───────────────┬───────────────────────┬──────────────────────┬───────────────┘
                │                       │                      │
        build-request.yml       nightly-rebuild.yml     opencode-release.yml
                │                       │                      │
                └───────────────┬───────┴──────────────────────┘
                                ▼
                        _pipeline.yml  (reusable)
                 ┌──────────────────────────────┐
                 │ 1. android-libs (NDK/Zig)    │  ← best-effort, continue-on-error
                 │ 2. build (→ _build-project)  │
                 └──────────────┬───────────────┘
                                ▼
                        _build-project.yml (reusable)
   ┌─────────────────────────────────────────────────────────────────────────┐
   │ resolve   → recipe padho, ref/version/targets nikalo, shards banao      │
   │ build×N   → swap 8G → toolchain → upstream clone → dispatch.sh → build  │
   │ smoke     → linux + windows runners par binary ko actually RUN karo     │
   │ release   → checksums + notes + installers → GitHub Release             │
   │ notify    → issue par comment (links, status)                           │
   └─────────────────────────────────────────────────────────────────────────┘
                                ▼
                    GitHub Release (assets + SHA256SUMS)
```

## Components

| path | kaam |
|---|---|
| `registry/*.json` | **recipes** — kaun sa repo, kaun sa ref, kaun sa build system, kaun se targets |
| `scripts/builders/dispatch.sh` | **dispatcher** — recipe padh kar सही builder chalata hai |
| `scripts/builders/{bun,go,rust,custom}.sh` | per-ecosystem cross-compile logic |
| `drivers/opencode/build-matrix.ts` | opencode ka specialised multi-target driver |
| `android/opentui/build-opentui-android.sh` | Termux TUI ke liye `libopentui.so` (aarch64/bionic) |
| `termux/package.sh` | zip + `.deb` + pacman `.pkg.tar.xz` |
| `.github/actions/setup-swap` | **swap memory** — OOM-safe heavy builds |
| `.github/actions/setup-toolchain` | Node · Bun · Go · Rust+zigbuild · Zig · NDK |
| `.state/last-built.json` | nightly diffing ke liye last built upstream commits |

## Design decisions

**1. Sab kuch Actions par, koi external builder nahi.**
Ryzen/Xeon runners, unlimited-ish minutes (public repo), aur logs public. Iska matlab:
provenance free milta hai — koi "trust me bro" binary nahi.

**2. Swap memory lazily create hoti hai.**
GitHub runners ke paas 16 GB RAM hai lekin **0 swap**. Bun ka bundler + Zig/NDK builds spike
karte hain → silent OOM kill. `setup-swap` action `/mnt` (ephemeral NVMe) par 8 GB swapfile
banata hai aur `vm.swappiness=60` set karta hai. Isse pehle wale runs jo OOM se marte the,
wo green ho jate hain.

**3. Sharded matrix.**
Targets ko N shards mein todte hain (default 2–3). 12 targets sequentially = 60+ min;
3 shards = ~20 min, aur ek target fail hone par baaki shards chalta rehta hai
(`fail-fast: false`).

**4. Native libs alag job mein.**
`libopentui.so` (JNI-style NN lib — bionic) build karna upstream toolchain par depend karta hai.
Agar wo fail ho jaye to **desktop builds nahi rukte** — sirf Termux artifact bina TUI renderer
ke publish hota hai, aur workflow summary mein saaf warning aata hai.

**5. Drivers registry ke saath version-controlled hain.**
Har project ka build logic `drivers/<project>/` mein hai, aur recipe batati hai ki usse upstream
checkout mein kahan copy karna hai. Upstream badalta hai to sirf driver update karo.

**6. Provenance har artifact ke andar.**
Har archive mein `NOTICE.md` (repo, ref, commit SHA, license, toolchain versions, run URL)
aur upstream `LICENSE` copy hota hai.

## Supported build systems

| system | cross-compile method | notes |
|---|---|---|
| **Bun** | `bun build --compile --target=bun-<os>-<arch>[-musl\|-android]` | single-file binary, no runtime needed |
| **Go** | `GOOS/GOARCH` (+NDK for cgo) | static → Alpine par bhi chalta hai |
| **Rust** | `cargo zigbuild` (zig linker) | macOS/Windows targets bina macOS/Windows machine |
| **custom** | recipe ka build command, per-target env vars | escape hatch (make/cmake/python…) |

## Security model

* Build inputs **sirf public source** — koi prebuilt blob shaamil nahi karte.
* `GITHUB_TOKEN` minimal permissions (workflow-level scopes).
* Third-party actions major version tags se pin hote hain (renovate/dependabot updates ke saath).
* Build-request flow mein license gate **do baar** chalta hai: triage + build ke waqt.
* Secret scanning / CodeQL workflows optional hai — [`SECURITY.md`](../SECURITY.md) dekho.
