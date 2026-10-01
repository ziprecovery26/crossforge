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

head_ "workflow output references"

# Teen tarah ki galtiyan pakadni hain (teenon ek baar ho chuki hain / ho sakti hain):
#   1. needs.<job>.outputs.<name> jo declare hi nahi hai
#   2. steps.<id>.outputs.<name> jahan <id> us job me nahi hai
#   3. steps.<id>.outputs.<name> jahan step hai par woh <name> output deta hi nahi
#      (asli bug: `steps.recipe.outputs.version` — recipe step version nahi likhta)
if command -v python3 >/dev/null 2>&1 && [ -d ".github/workflows" ]; then
  BADREFS="$(python3 - <<'PYEOF'
import glob, os, re, yaml

def load(path):
    try:
        return yaml.safe_load(open(path)) or {}
    except Exception:
        return {}

def events(doc):
    on = doc.get("on", doc.get(True)) or {}
    return on if isinstance(on, dict) else {}

wf_dir = ".github/workflows"
root = os.path.dirname(os.path.dirname(wf_dir)) or "."

def call_outputs(uses):
    if not uses or not uses.startswith("./"):
        return None
    path = os.path.join(root, uses[2:])
    if not os.path.isfile(path):
        return None
    return set((events(load(path)).get("workflow_call") or {}).get("outputs") or {})

def job_blocks(text):
    lines, out, cur, buf = text.splitlines(True), {}, None, []
    for ln in lines:
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
        if m:
            if cur:
                out[cur] = "".join(buf)
            cur, buf = m.group(1), [ln]
        elif cur is not None:
            if re.match(r"^[A-Za-z#]", ln):
                out[cur] = "".join(buf)
                cur, buf = None, []
            else:
                buf.append(ln)
    if cur:
        out[cur] = "".join(buf)
    return out

ASSIGN = re.compile(r'(?:^|\s|"\s*)([A-Za-z_][A-Za-z0-9_-]*)=')
GITHUB_OUTPUT = "$GITHUB_OUTPUT"

def run_outputs(script):
    """`run:` block me $GITHUB_OUTPUT par likhe gaye keys.
    Styles jo repo me use hote hain: echo "k=v", echo "k<<EOF" (multiline),
    python print("k=" + ...), aur { ... } >> "$GITHUB_OUTPUT" group me `k=v`."""
    P = [
        re.compile(r'echo\s+"?([A-Za-z_][A-Za-z0-9_-]*)=', re.I),     # echo "k=v"
        re.compile(r'echo\s+"?([A-Za-z_][A-Za-z0-9_-]*)<<', re.I),    # echo "k<<EOF"
        re.compile(r'print\s*\(\s*f?"([A-Za-z_][A-Za-z0-9_-]*)='),   # python print
        re.compile(r'printf\s+"?([A-Za-z_][A-Za-z0-9_-]*)=', re.I),   # printf
        re.compile(r'^([A-Za-z_][A-Za-z0-9_-]*)=', re.I),             # k=v line
    ]
    names, pending = set(), set()
    for line in script.splitlines():
        st = line.strip()
        if st.startswith("#"):
            continue
        for rx in P:
            m = rx.search(st if rx.pattern.startswith("^") else line)
            if m:
                pending.add(m.group(1))
        if GITHUB_OUTPUT in line:
            names |= pending
            pending = set()
    return names

def step_outputs(step):
    """None = pata nahi chalta (external action) -> skip"""
    if step.get("uses"):
        uses = step["uses"]
        if uses.startswith("./"):
            path = os.path.join(root, uses[2:])
            if os.path.isfile(path):
                return set((load(path).get("outputs") or {}).keys())
        return None
    if step.get("run") is not None:
        return run_outputs(str(step["run"]))
    return None

bad = []
for f in sorted(glob.glob(os.path.join(wf_dir, "*.yml"))):
    raw = open(f).read()
    doc = load(f)
    jobs = doc.get("jobs") or {}
    name = os.path.basename(f)

    declared = {}
    for jn, job in jobs.items():
        job = job or {}
        if job.get("uses"):
            outs = call_outputs(job["uses"])
            declared[jn] = outs if outs is not None else set()
        else:
            declared[jn] = set(job.get("outputs") or {})
    for m in re.finditer(r"needs\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", raw):
        j, o = m.groups()
        if j in declared and o not in declared[j]:
            bad.append("%s: needs.%s.outputs.%s undeclared" % (name, j, o))

    blocks = job_blocks(raw)
    for jn, job in jobs.items():
        job = job or {}
        if job.get("uses"):
            continue
        by_id = {}
        for st in (job.get("steps") or []):
            if isinstance(st, dict) and st.get("id"):
                by_id[st["id"]] = st
        for m in re.finditer(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", blocks.get(jn, "")):
            sid, sname = m.groups()
            if sid not in by_id:
                bad.append("%s: job `%s` me step id `%s` nahi hai (steps.%s.outputs.%s)" % (name, jn, sid, sid, sname))
                continue
            outs = step_outputs(by_id[sid])
            if outs is not None and sname not in outs:
                bad.append("%s: step `%s` (job `%s`) output `%s` nahi deta (steps.%s.outputs.%s)" % (name, sid, jn, sname, sid, sname))

print("\n".join(sorted(set(bad))))
PYEOF
)"
  if [ -z "$BADREFS" ]; then
    ok "needs.*.outputs.* / steps.*.outputs.* references all valid"
  else
    printf '%s\n' "$BADREFS" >&2
    bad "workflow output reference mismatch"
  fi
else
  ok "workflow output check skipped (python3 nahi mila)"
fi

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
