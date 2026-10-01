#!/usr/bin/env bash
# CrossForge · one-command repo creation + push
#
#   bash scripts/push-to-github.sh <github-username> [repo-name] [--private]
#
# Zaroori: `gh auth login` pehle kar lo (gh CLI).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

USERNAME="${1:-}"
REPO="${2:-crossforge}"
VISIBILITY="--public"
[ "${3:-}" = "--private" ] && VISIBILITY="--private"

[ -n "$USERNAME" ] || { echo "usage: bash scripts/push-to-github.sh <username> [repo] [--private]"; exit 1; }

command -v gh >/dev/null 2>&1 || { echo "gh CLI chahiye: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "pehle 'gh auth login' karo"; exit 1; }

echo "==> placeholders replace kar raha hoon (OWNER → $USERNAME)"
grep -rl "ziprecovery26/crossforge" . --exclude-dir=.git 2>/dev/null | while read -r f; do
  sed -i "s#ziprecovery26/crossforge#$USERNAME/$REPO#g" "$f"
  echo "    patched $f"
done

echo "==> git init + commit"
if [ ! -d .git ]; then git init -q -b main; fi
git add -A
git diff --cached --quiet || git commit -q -m "feat: CrossForge — universal cross-compile binary farm (opencode first)"

echo "==> GitHub repo create + push"
if gh repo view "$USERNAME/$REPO" >/dev/null 2>&1; then
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$USERNAME/$REPO.git"
  git push -u origin main
else
  gh repo create "$REPO" $VISIBILITY --source=. --remote=origin --push \
    --description "Universal open-source binary farm — cross-compiled releases (Windows/Linux/macOS/Android-Termux) built on GitHub Actions"
fi

cat <<EOF

✅ ho gaya: https://github.com/$USERNAME/$REPO

Aage ke steps:
  1. Settings → Actions → General → Workflow permissions → **Read and write** ✅
  2. Actions → **setup labels** → Run workflow            (labels + variables banayega)
  3. Actions → **opencode · release** → Run workflow      (pehla binary! 🎯)
  4. Issues → New issue → 🔨 Build Request                (naya project maango)
EOF
