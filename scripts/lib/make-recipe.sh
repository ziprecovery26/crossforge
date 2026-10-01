#!/usr/bin/env bash
# Builds a registry recipe JSON from an approved build-request issue.
#
#   make-recipe.sh --body /tmp/issue.md --out registry/ripgrep.json --issue 42
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

PARSE="$SCRIPT_DIR/parse-issue.sh"
BODY="" OUT="" ISSUE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --body)  BODY="$2"; shift 2 ;;
    --out)   OUT="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    *) cf::die "unknown argument: $1" ;;
  esac
done
[ -f "$BODY" ] || cf::die "--body must be a readable file"

get() { bash "$PARSE" "$BODY" "$1"; }

REPO_URL="$(get "Repository URL")"
NAME="$(get "Project name")"
REF_IN="$(get "Version / Tag / Commit")"
SYSTEM_IN="$(get "Build system")"
ENTRY="$(get "Entrypoint / build command (optional)")"
TARGETS_RAW="$(get "Targets")"

[ -n "$REPO_URL" ] || cf::die "Repository URL issue mein nahi mila"

# https://github.com/owner/name(.git) → owner/name
SLUG="$(printf '%s' "$REPO_URL" | sed -E 's#^https?://(www\.)?github\.com/##; s#\.git$##; s#/+$##')"
echo "$SLUG" | grep -qE '^[^/]+/[^/]+$' || cf::die "invalid GitHub repo url: $REPO_URL"

ID="$(printf '%s' "${NAME:-${SLUG#*/}}" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-')"
[ -n "$ID" ] || cf::die "could not derive project id"

REF="${REF_IN:-main}"

# --- map the checkbox list to CrossForge target ids ---------------------------
# Sirf CHECKED boxes count karte hain ("- [x] ..."), aur woh bhi Targets section ke andar.
target_checked() {
  awk '
    /^### / {
      sec = $0; sub(/^###[[:space:]]*/, "", sec); gsub(/\r$/, "", sec); next
    }
    {
      gsub(/\r$/, "", $0)
      if (sec == "Targets" && $0 ~ /^[[:space:]]*-[[:space:]]*\[[xX]\]/) print
    }
  ' "$BODY" | grep -qi -- "$1"
}

TARGETS="[]"
add_target() { TARGETS="$(jq -c --arg t "$1" '. + [$t] | unique' <<<"$TARGETS")"; }

target_checked "Windows (x64)"   && add_target "windows-x64"
target_checked "Windows (arm64)" && add_target "windows-arm64"
target_checked "Linux x64 (glibc)"   && add_target "linux-x64"
target_checked "Linux arm64 (glibc)" && add_target "linux-arm64"
if target_checked "Linux musl"; then add_target "linux-x64-musl"; add_target "linux-arm64-musl"; fi
if target_checked "macOS"; then add_target "darwin-x64"; add_target "darwin-arm64"; fi
target_checked "Termux" && add_target "android-arm64"

if [ -n "$TARGETS_RAW" ] && [ "$(jq 'length' <<<"$TARGETS")" -gt 0 ]; then
  cf::log "selected targets: $(jq -r 'join(", ")' <<<"$TARGETS")"
fi

if [ "$(jq 'length' <<<"$TARGETS")" = "0" ]; then
  TARGETS='["linux-x64","windows-x64","darwin-arm64","android-arm64"]'
  cf::warn "koi target select nahi hua tha — default set use kar raha hoon"
fi

# --- build system -----------------------------------------------------------------
SYSTEM="$(printf '%s' "${SYSTEM_IN:-auto-detect}" | tr '[:upper:]' '[:lower:]')"
case "$SYSTEM" in
  bun*) SYSTEM="bun" ;;
  node*) SYSTEM="bun" ;;   # bun bundler node code bhi compile kar leta hai
  go*) SYSTEM="go" ;;
  rust*|cargo*) SYSTEM="rust" ;;
  python*|other*|custom*|auto*) SYSTEM="custom" ;;
  *) SYSTEM="custom" ;;
esac

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg id "$ID" \
  --arg slug "$SLUG" \
  --arg ref "$REF" \
  --arg system "$SYSTEM" \
  --arg entry "$ENTRY" \
  --arg issue "${ISSUE:-0}" \
  --arg now "$NOW" \
  --argjson targets "$TARGETS" \
  '{
    "$schema": "./schema/recipe.schema.json",
    id: $id,
    name: $id,
    description: ("Auto-registered from build request issue #" + $issue),
    upstream: {
      repo: $slug,
      url: ("https://github.com/" + $slug),
      ref: $ref,
      refStrategy: (if $ref == "main" or $ref == "master" then "latest-tag-or-branch" else "pinned" end)
    },
    license: { spdx: "UNKNOWN", redistributable: false, notes: "Filled by the triage workflow after verification" },
    buildSystem: $system,
    custom: { build: $entry, binaryName: $id },
    targets: $targets,
    defaultTargets: $targets,
    nightly: false,
    enabled: true,
    notes: [("requested in issue #" + $issue + " at " + $now)]
  }' > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"
cf::log "wrote recipe: $OUT"
jq . "$OUT"
