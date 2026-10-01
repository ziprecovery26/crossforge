#!/usr/bin/env bash
# CrossForge self-test — repo ki sanity locally check karta hai (CI bhi yahi chalata hai).
#   bash scripts/self-test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

head_ "JSON files"
while IFS= read -r f; do
  if jq . "$f" >/dev/null 2>&1; then ok "$f"; else bad "$f (invalid JSON)"; fi
done < <(find . -name "*.json" -not -path "./node_modules/*" -not -path "./.git/*")

head_ "YAML files"
if python3 -c "import yaml" 2>/dev/null; then
  while IFS= read -r f; do
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then
      ok "$f"
    else
      bad "$f (invalid YAML)"
    fi
  done < <(find . -name "*.yml" -not -path "./.git/*")
else
  echo "  (pyyaml nahi hai — skip)"
fi

head_ "Bash syntax"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f (syntax error)"; fi
done < <(find . -name "*.sh" -not -path "./.git/*")

head_ "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t SH_FILES < <(find . -name "*.sh" -not -path "./.git/*")
  if shellcheck -S warning -x "${SH_FILES[@]}" >/tmp/cf-shellcheck.txt 2>&1; then
    ok "shellcheck clean (warning+)"
  else
    bad "shellcheck issues:"; sed 's/^/    /' /tmp/cf-shellcheck.txt | head -20
  fi
else
  echo "  (shellcheck nahi hai — skip)"
fi

head_ "actionlint"
if command -v actionlint >/dev/null 2>&1; then
  if actionlint >/tmp/cf-actionlint.txt 2>&1; then ok "workflows valid"; else bad "actionlint issues:"; sed 's/^/    /' /tmp/cf-actionlint.txt | head -20; fi
else
  echo "  (actionlint nahi hai — skip)"
fi

head_ "registry <-> recipes consistency"
if jq -e '.projects | length > 0' registry/index.json >/dev/null; then
  for id in $(jq -r '.projects[].id' registry/index.json); do
    if [ -f "registry/$id.json" ]; then ok "registry/$id.json exists"; else bad "registry/$id.json MISSING"; fi
  done
else
  bad "registry/index.json empty"
fi

head_ "issue-form parser"
if [ -f tests/fixtures/issue-body.md ]; then
  T="$(bash scripts/lib/parse-issue.sh tests/fixtures/issue-body.md "Repository URL")"
  if [ "$T" = "https://github.com/BurntSushi/ripgrep.git" ]; then ok "parse-issue.sh reads fields"; else bad "parser returned: $T"; fi

  bash scripts/lib/make-recipe.sh --body tests/fixtures/issue-body.md --out /tmp/cf-recipe-test.json --issue 0 >/dev/null 2>&1
  if jq -e '.targets | index("linux-x64")' /tmp/cf-recipe-test.json >/dev/null 2>&1; then
    ok "make-recipe.sh maps checked targets"
  else
    bad "make-recipe.sh did not map targets"
  fi
  # unchecked box target nahi aana chahiye
  if jq -e '.targets | index("windows-x64")' /tmp/cf-recipe-test.json >/dev/null 2>&1; then
    bad "unchecked checkbox leaked into targets"
  else
    ok "unchecked checkbox ignored"
  fi
else
  bad "tests/fixtures/issue-body.md missing"
fi

head_ "target mappings"
# shellcheck source=lib/common.sh
source scripts/lib/common.sh
[ "$(cf::bun_target android-arm64)" = "bun-linux-arm64-android" ] && ok "bun android target" || bad "bun android mapping"
[ "$(cf::bun_target linux-x64-musl)" = "bun-linux-x64-musl" ] && ok "bun musl target" || bad "bun musl mapping"
[ "$(cf::go_triple windows-arm64)" = "windows arm64" ] && ok "go windows/arm64" || bad "go mapping"
[ "$(cf::rust_triple darwin-arm64)" = "aarch64-apple-darwin" ] && ok "rust darwin arm64" || bad "rust mapping"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
