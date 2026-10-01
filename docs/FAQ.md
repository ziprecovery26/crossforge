# ❓ FAQ

### Yeh repo kya karta hai, ek line mein?
Kisi bhi **open-source project** ke pre-built binaries (Windows/Linux/macOS/**Android-Termux**)
GitHub Actions par automated cross-compile karke GitHub Release par deta hai.

### Binary kisne banaya? Trust kaise karun?
- Build **public GitHub Actions runner** par, **public source** se hota hai.
- Logs public hain — `Actions` tab → run → poora log.
- Har archive mein `NOTICE.md` hai: repo, ref, **commit SHA**, license, toolchain versions, run URL.
- `SHA256SUMS` release ke saath aata hai. Installer checksum verify karta hai.

### Kya yeh upstream project ke official binaries hain?
**Nahi.** Yeh CrossForge ke community/automated builds hain. Upstream maintainers iske liye
responsible nahi hain (aur unka naam use karna avoid karte hain). Issues upstream ke bajaye
**yahan** kholo.

### Kaun-kaun se projects build hote hain?
`registry/index.json` dekho. Pehla flagship: **opencode** (MIT). Aur add karne ke liye ek
Build Request issue kholo.

### Closed-source project build kar sakte ho?
Nahi. License gate (`cf:license-blocked`) hai. Bina license = reject.

### Android ke liye normal Linux binary kyun nahi chalta?
Android **bionic** libc use karta hai; Linux binaries **glibc/musl** ke liye linked hote hain.
Isliye alag `android-arm64` build hoti hai, aur native libs (`libopentui.so`) bhi bionic ke liye
compile karne padte hain — dekho [`TERMUX.md`](TERMUX.md).

### Swap memory ka kya role hai?
GitHub ke runners par 16 GB RAM hai par **swap zero**. Bun/Zig/NDK builds spike karte hain aur
OOM par process **chupchap marr** jata hai (koi error nahi, bas fail). `setup-swap` action
`/mnt` par 8 GB swapfile banata hai — isse heavy builds reliably pass hote hain.

### Build kitna time leta hai?
* Pehli baar: ~25–45 min (toolchain download + NDK).
* Cached/nightly: ~15–25 min (sharded).
* Ek single Linux target: ~5–10 min.

### Nightly ka matlab?
Roz **03:00 UTC (08:30 IST)** par:
* upstream ka latest commit check,
* badla ho to fresh build,
* `nightly-YYYY.MM.DD` tag par **pre-release** publish,
* stable releases alag tags par rehte hain (`v1.18.34-cf.1`).

### Kya main apna fork banake apni binaries bana sakta hoon?
Bilkul — poora setup isi liye hai. [`QUICKSTART-OWNER.md`](QUICKSTART-OWNER.md) follow karo.

### Build minutes free hain?
Public repo ke liye GitHub Actions minutes **free** hain (standard runners). Private repo ho to
minutes count honge. Bahut zyada projects ho to self-hosted runner better hai —
[`SELF-HOSTING.md`](SELF-HOSTING.md).

### `baseline` binary kya hai?
Purane x86_64 CPUs (jo AVX2 support nahi karte) ke liye. Naye CPUs par normal binary use karo.

### macOS binary unsigned hai — chalega?
Haan, par Gatekeeper block kar sakta hai:
```bash
xattr -dr com.apple.quarantine ./opencode
```
Signed/notarized builds ke liye Apple Developer account chahiye (roadmap mein hai).

### Kyun kuch targets "best-effort" hain?
`android-arm64` ka TUI lib upstream me upstream support nahi hai (OpenTUI ke paas android
native lib nahi). Hum best-effort build karte hain aur fail hone par **saaf warning** dete hain —
chupke se jhoota success nahi dikhate.

### Kya tum pura binary ko "publish" karne se pehle test karte ho?
Haan — `smoke-linux` / `smoke-windows` jobs binary ko actually **run karke** `--version` check
karte hain (native runner par). Yeh jobs `continue-on-error: true` hain kyunki woh information
dete hain; agar output nahi aata to summary mein dikh jata hai.
