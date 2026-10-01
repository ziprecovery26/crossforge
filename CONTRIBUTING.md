# Contributing to CrossForge

Shukriya! 🙌 Yeh repo open-source binaries ko accessible banane ke liye hai.

## Quick map

| kaam | kahan |
|---|---|
| naya project add karna | `registry/<id>.json` (Build Request issue se bhi ho jata hai) |
| naya ecosystem support (jaise Zig, .NET) | `scripts/builders/<lang>.sh` + `dispatch.sh` mein case |
| opencode build targets | `drivers/opencode/build-matrix.ts` |
| Termux/Android | `android/opentui/`, `termux/` |
| CI logic | `.github/workflows/` |

## Naya registry recipe add karna

```bash
cp registry/opencode.json registry/mera-project.json
# id, upstream.repo, upstream.ref, buildSystem, targets, license bharo
jq . registry/mera-project.json > /dev/null   # valid JSON check
```

Phir `registry/index.json → projects[]` mein entry add karo.

**Rules:**
* `license.spdx` **must** allowlist me ho (`registry/index.json → allowlist`).
* `upstream.ref` pinned rakho (tag ya full SHA). Branch head sirf tab jab nightly chahiye.
* `defaultTargets` rakho — 12 targets har baar build karna CI minutes khaata hai.

## Naya builder likhna

Builder contract (`scripts/builders/*.sh`):

```
builder.sh --recipe <path> --upstream <dir> --out <dir> --targets "a,b" --version X
```

* `source scripts/lib/common.sh` karo — `cf::bun_target`, `cf::go_triple`, `cf::rust_triple`, `cf::archive`, `cf::add_notice` free milte hain.
* Har target ke liye: `<out>/<project>-<target>/bin/<binary>` banao, phir `cf::add_notice` + `cf::archive`.
* Fail par non-zero exit — CI isko properly report karta hai.

## Pull request checklist

- [ ] `bash -n <script>` pass (syntax)
- [ ] `shellcheck <script>` clean (ya justified `# shellcheck disable=`)
- [ ] `jq . registry/*.json` valid
- [ ] recipe mein license + `redistributable: true`
- [ ] docs update (agar behaviour badla ho)
- [ ] commit message conventional (`feat(registry): ...`)

## Security

* Kabhi bhi secrets commit na karo (`.env`, tokens, private keys).
* Workflows mein `pull_request_target` + untrusted checkout ka combo avoid karo.
* Naya third-party action add karte waqt version pin karo.

## Code of conduct (short version)

Respectful raho. Hinglish/English koi bhi theek hai. Beginner questions welcome hain —
hum sab kabhi naye the. 🚀
