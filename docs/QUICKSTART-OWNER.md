# 🚀 Quickstart — apna CrossForge live karo (5 minute)

> Yeh guide **tumhare liye** hai (repo owner). Sab kuch already likha hua hai —
> bas push karo aur buttons dabao.

## 1. Repo banao

```bash
cd crossforge
git init -b main
git add -A
git commit -m "feat: CrossForge — universal cross-compile binary farm (opencode first)"

# GitHub CLI se repo banao + push (ek command)
gh repo create crossforge --public --source=. --remote=origin --push
```

`gh` nahi hai? Web se karo:

```bash
git remote add origin https://github.com/<TUMHARA-USERNAME>/crossforge.git
git push -u origin main
```

## 2. Placeholder replace karo (`OWNER` → tumhara username)

Poore repo mein `ziprecovery26/crossforge` ko apne `username/crossforge` se badlo:

```bash
grep -rl "ziprecovery26/crossforge" . --exclude-dir=.git | xargs sed -i "s#ziprecovery26/crossforge#<username>/crossforge#g"
git commit -am "chore: point badges/urls at the real repo" && git push
```

(Yeh README, installers, issue templates aur release notes ke links sahi kar deta hai.)

## 3. Actions permissions check karo

Repo → **Settings → Actions → General** :

* ✅ **Workflow permissions** → *Read and write permissions*
* ✅ **Allow GitHub Actions to create and approve pull requests** (optional)
* ✅ **Read and write permissions** for `GITHUB_TOKEN`

Workflows release banate hain aur issue comment karte hain — iske liye `contents: write` + `issues: write` chahiye.
(Workflow files mein already declare kiya hua hai; bas repo setting allow karni hai.)

## 4. Labels banao (ek baar)

**Actions → setup labels → Run workflow** ✅

Isse `cf:approved`, `cf:license-ok`, `build-request` jaise labels ban jayenge aur
`OPENTUI_REF` / `OPENTUI_ZIG_VERSION` variables set ho jayenge.

## 5. Pehla binary banao — opencode 🎯

**Actions → opencode · release → Run workflow**

| input | kya dena hai |
|---|---|
| `ref` | khaali chhodo (= latest upstream tag) ya `dev` / `v1.18.34` |
| `targets` | khaali = recipe ke defaults (12 targets, incl. android-arm64) |
| `publish` | ✅ true (Release publish karo) |
| `shards` | `2` ya `3` (parallel jobs) |

**Time:** ~20–40 min (pehli baar zyada, kyunki Bun + NDK toolchain download hota hai).
**Output:** `Releases` tab mein naya tag + installers + `SHA256SUMS`.

## 6. Roz ka freshness (nightly)

`nightly-rebuild.yml` already configured hai — **roz 03:00 UTC (08:30 IST)** par:

1. har registered project ka upstream commit check karta hai,
2. jo badla hai uska fresh build karta hai,
3. `nightly-YYYY.MM.DD` tag par pre-release publish karta hai,
4. `.state/last-built.json` mein record rakhta hai (agle din diff ke liye).

Tum chaho to manual bhi chala sakte ho: *Actions → nightly rebuild → Run workflow*
(`only_changed = false` kar do to sab projects rebuild honge, chahe upstream na badla ho).

## 7. Requests ka flow test karo

1. **Issues → New issue → 🔨 Build Request** → koi project bharo (jaise `ripgrep`).
2. Bot license verify karega aur comment karega (`cf:license-ok` / `cf:license-blocked`).
3. Tum (maintainer) `cf:approved` label lago → **build-request** workflow:
   * recipe auto-generate karke commit karega,
   * build chalayega,
   * result issue par comment karega (download links ke saath).

---

## Troubleshooting

| problem | fix |
|---|---|
| `Resource not accessible by integration` | Settings → Actions → Workflow permissions → *Read and write* |
| Build OOM kill ho gaya | `shards` badhao (`3`/`4`) — har shard kam targets banata hai; swap action already 8 GB lagata hai |
| `bun install` fail (node-gyp) | setup-toolchain already Node 24 + node-gyp install karta hai; `apt-packages: "python3 build-essential"` add karo |
| Android TUI lib fail | Desktop binaries phir bhi publish honge; dekho [`TERMUX.md`](TERMUX.md) — prebuilt fallback options hain |
| Release publish nahi hua | `publish: true` check karo; tag already exist karta ho to `release_tag` badlo |

## Optional: apna runner (self-hosted)

Zyada speed / unlimited minutes chahiye? [`SELF-HOSTING.md`](SELF-HOSTING.md) dekho —
same workflows self-hosted runner par bhi chalte hain (runner par `swap` step skip ho jata hai
agar already swap hai).
