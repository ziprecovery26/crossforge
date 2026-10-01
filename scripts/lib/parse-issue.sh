#!/usr/bin/env bash
# Issue-form body parser.
#
# GitHub renders an issue form as markdown:
#   ### Project name
#   ripgrep
#   ### Repository URL
#   https://github.com/BurntSushi/ripgrep
#
#   parse-issue.sh <body-file> "<Field label>"     → prints the value (empty if none)
#   parse-issue.sh --list <body-file>              → prints "label<TAB>value" for all fields
set -euo pipefail

parse_field() {
  local file="$1" label="$2"
  awk -v label="$label" '
    /^### / {
      sec = $0
      sub(/^###[[:space:]]*/, "", sec)
      gsub(/\r$/, "", sec)
      next
    }
    {
      gsub(/\r$/, "", $0)
      if (sec == label) print
    }
  ' "$file" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

if [ "${1:-}" = "--list" ]; then
  awk '
    /^### / { sec=$0; sub(/^###[[:space:]]*/,"",sec); gsub(/\r$/,"",sec); insec=1; buf=""; next }
    { if (insec) { gsub(/\r$/,"",$0); if ($0 !~ /^[[:space:]]*$/) buf = (buf ? buf " " : "") $0 } }
    /^### / && NR>1 { }
    END { }
  ' "$2" >/dev/null # (kept simple: --list mode below)
  awk '
    /^### / {
      if (sec != "") printf "%s\t%s\n", sec, val
      sec=$0; sub(/^###[[:space:]]*/,"",sec); gsub(/\r$/,"",sec); val=""; next
    }
    { if (sec != "") { gsub(/\r$/,"",$0); if ($0 !~ /^[[:space:]]*$/) val = (val ? val " " : "") $0 } }
    END { if (sec != "") printf "%s\t%s\n", sec, val }
  ' "$2"
  exit 0
fi

BODY_FILE="${1:?usage: parse-issue.sh <body-file> \"<Field label>\"}"
LABEL="${2:?missing label}"

VALUE="$(parse_field "$BODY_FILE" "$LABEL" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//')"
[ "$VALUE" = "_No response_" ] && VALUE=""
printf '%s\n' "$VALUE"
