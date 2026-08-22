#!/usr/bin/env bash
# Captures the Quick Look preview of a file, scoped to that one window.
#
# Usage: Scripts/ql-shot.sh QA/fixtures/long.md QA/evidence/QL-1.png
#
# qlmanage -p drives the same preview extension that pressing space in Finder
# does, so this exercises the real path. The capture is scoped to the preview
# window by id: a full screen shot would photograph whatever else is open, and
# this repository is public.
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="$1"
OUT="$2"
mkdir -p "$(dirname "$OUT")"

qlmanage -p "$FILE" >/dev/null 2>&1 &
QL_PID=$!

WINDOW=""
for _ in $(seq 1 40); do
  /usr/bin/osascript -e 'delay 0.4' >/dev/null 2>&1
  for owner in qlmanage QuickLookUIService; do
    if WINDOW="$(swift Scripts/window-id.swift "$owner" 2>/dev/null)" && [ -n "$WINDOW" ]; then
      break 2
    fi
  done
  WINDOW=""
done

if [ -z "$WINDOW" ]; then
  echo "no Quick Look window appeared for $FILE" >&2
  kill "$QL_PID" 2>/dev/null || true
  exit 1
fi

screencapture -x -o -l"$WINDOW" "$OUT"
kill "$QL_PID" 2>/dev/null || true
pkill -f "qlmanage -p" 2>/dev/null || true
echo "$OUT"
