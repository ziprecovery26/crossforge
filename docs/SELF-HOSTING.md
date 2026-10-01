# 🖥️ Self-hosting the build farm

GitHub-hosted runners kaafi hain, lekin agar tumhe:

* **unlimited minutes** (private repos par bhi),
* **zyada RAM/CPU** (WebKit-scale native builds),
* **apna toolchain cache** (Bun/Zig/NDK download ek hi baar),

…chahiye, to self-hosted runner lagao.

## 1. Runner register karo

Repo → **Settings → Actions → Runners → New self-hosted runner** →
Linux instructions follow karo:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o runner.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-<ver>.tar.gz
tar xzf runner.tar.gz
./config.sh --url https://github.com/<owner>/crossforge --token <TOKEN> --labels cf-builder
sudo ./svc.sh install && sudo ./svc.sh start
```

## 2. Runner par swap + toolchain pehle se rakho

```bash
# 16 GB swap (persistent)
sudo fallocate -l 16G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Runner user ko `sudo swapon` ke liye passwordless entry do, warna `setup-swap` action skip ho jayega
(already-on swap hone par woh apne aap skip karta hai — `swapon --show` check karta hai).

## 3. Workflows ko runner par bhejo

Har job mein `runs-on` badlo:

```yaml
runs-on: [self-hosted, linux, cf-builder]
```

Ya repo-level default set karo (`.github/workflows/*.yml` mein ek-ek karke):

```bash
sed -i 's/runs-on: ubuntu-latest/runs-on: [self-hosted, linux, cf-builder]/' .github/workflows/_build-project.yml
```

> ⚠️ **Windows smoke test** wala job (`smoke-windows`) Windows runner par hi chalega —
> usko `windows-latest` hi rehne do (ya ek Windows self-hosted runner lagao).

## 4. Cache layering (optional but recommended)

Self-hosted runner par yeh directories persist kar lo (`~/.cache` ke andar):

| tool | cache path |
|---|---|
| Bun | `~/.bun/install/cache` |
| cargo | `~/.cargo/registry`, `~/.cargo/git` |
| NDK | `$HOME/android-ndk-r27c` (setup-toolchain skip kar dega agar mila) |
| Zig | `~/zig` + `PATH` mein daal do (`setup-zig` skip ho jayega) |

## 5. Cost/complexity trade-off

| setup | achha | bura |
|---|---|---|
| GitHub-hosted | zero maintenance, public repo free | 6h job limit, 4 vCPU, disk ~14 GB |
| Self-hosted (1 beefy box) | fast, unlimited, big disk | maintenance, security responsibility |
| Matrix of both | spillover capacity | config complexity |

## 6. Security note (important)

Self-hosted runner par **untrusted PRs** kabhi mat chalao — public repo ho to
Settings → Actions → "Require approval for fork pull request workflows" on rakho.
Is repo ke workflows sirf `workflow_dispatch`, `schedule` aur `issues:labeled` par chalte hain
(PR par nahi) — to default config safe hai.
