# 🙋 Request flow — "bhai isko build kar do"

## Step by step

```
1. USER      → Issues → New issue → 🔨 Build Request (form)
                     ↓
2. BOT       → request-triage.yml chalta hai
                 • license check (GitHub API SPDX)
                 • build system detect (go.mod / Cargo.toml / package.json / pyproject)
                 • comment + label: cf:license-ok | cf:license-blocked | cf:needs-review
                     ↓
3. MAINTAINER→ `cf:approved` label lagata hai (imp: isse hi build chalu hota hai)
                     ↓
4. BOT       → build-request.yml
                 • license dobara verify (defense in depth)
                 • registry/<id>.json auto-generate + commit (naya project ho to)
                 • _pipeline.yml → _build-project.yml (swap + toolchain + compile)
                     ↓
5. BOT       → GitHub Release publish + issue par comment
                 (per-platform download links, logs, checksums)
```

## Labels

| label | matlab |
|---|---|
| `build-request` | user ne form submit kiya |
| `cf:triage` | bot triage pending |
| `cf:license-ok` | license allowlist pass |
| `cf:license-blocked` | license allow nahi karta |
| `cf:needs-review` | SPDX detect nahi hua / unusual license |
| `cf:needs-info` | form adhoora hai |
| `cf:approved` | **maintainer ne green light diya → build chalu** |
| `cf:built` | binary publish ho gaya |
| `cf:failed` | build fail — logs issue par |

## License policy

**Allowed (OSI-approved):** MIT · Apache-2.0 · BSD-2/3-Clause · ISC · MPL-2.0 · GPL-2.0/3.0 ·
LGPL-2.1/3.0 · EPL-2.0 · Zlib · Unlicense · 0BSD · BSL-1.0 …

**Denied:** `NOASSERTION` (koi license nahi) · `UNLICENSED` · `LicenseRef-Proprietary` ·
BUSL-1.1 · Elastic-2.0 · SSPL-1.0

Naya license jodna hai? `registry/index.json → allowlist.licenses` mein PR karo.

## Agar project ka koi recipe na ho

`make-recipe.sh` issue form se ek minimal recipe banata hai:

```json
{
  "id": "ripgrep",
  "upstream": { "repo": "BurntSushi/ripgrep", "ref": "14.1.1", "refStrategy": "latest-tag-or-branch" },
  "buildSystem": "custom",
  "custom": { "build": "<entrypoint / build command from the form>", "binaryName": "ripgrep" },
  "targets": ["windows-x64", "linux-x64", "android-arm64"],
  "license": { "spdx": "MIT", "redistributable": true }
}
```

Yeh ek **starting point** hai — maintainer `buildSystem` (go/rust/bun) set karke, `custom.build`
ko sahi command se replace karke recipe sudhaar sakta hai, ya `scripts/builders/` mein naya
builder likh sakta hai.

## Build fail hua to?

1. Issue par `❌ build failed` comment aata hai + Actions run ka link.
2. Maintainer log dekhta hai — usually 3 me se ek cheez hoti hai:
   * upstream ne build system badal diya → driver/recipe update,
   * toolchain version mismatch (Bun/Zig/Rust) → recipe mein pin karo,
   * memory/OOM → `shards` badhao (swap already enabled hai).
3. Recipe fix karke `cf:approved` label hata kar dobara lagao → rebuild.

## Rules & limits

* Sirf **public repos**.
* Sirf **open-source licenses** (upar wali list).
* Hum **cyber-weapons, malware, credential stealers** build nahi karte — request reject + report.
* Ek request = ek project. Multiple projects ke liye multiple issues kholo.
* Native/OS-specific projects (jaise Linux-kernel modules ya Windows-only DLLs) out of scope ho sakte hain.

## Kaun approve karta hai?

Repo collaborators (write access) — yahi `cf:approved` label laga sakte hain.
Naya maintainer add karna ho to `CONTRIBUTING.md` dekho.
