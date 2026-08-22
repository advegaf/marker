#!/usr/bin/env bash
# Captures the real Marker window through the window server.
#
# Usage: Scripts/window-shot.sh <out.png> [env assignments...]
#   Scripts/window-shot.sh QA/evidence/APP-3.png MARKER_OPEN=QA/fixtures/long.md MARKER_SCROLL=bottom
#
# In-process capture cannot see TextKit 2's layer-drawn text, so the app holds the
# window open, reports its number, and screencapture takes the shot. Needs Screen
# Recording permission for the terminal, granted once.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$1"; shift
APP="$(xcodebuild -project Marker.xcodeproj -scheme Marker -configuration Debug \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Marker.app"

mkdir -p "$(dirname "$OUT")"
META="$(mktemp)"
env "$@" MARKER_WINDOW_HOLD=1 "$APP/Contents/MacOS/Marker" > "$META" 2>/dev/null &
APP_PID=$!

# Wait for the window number rather than sleeping a fixed amount.
for _ in $(seq 1 60); do
  grep -q windownumber= "$META" && break
  /usr/bin/osascript -e 'delay 0.25' >/dev/null 2>&1
done

WINDOW="$(sed -n 's/.*windownumber=\([0-9]*\).*/\1/p' "$META" | head -1)"
METRICS="$(grep -o 'document=.*' "$META" | head -1 || true)"

if [ -z "$WINDOW" ]; then
  echo "no window number reported; app output was:" >&2
  cat "$META" >&2
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi

screencapture -x -o -l"$WINDOW" "$OUT"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
rm -f "$META"

echo "$OUT"
[ -n "$METRICS" ] && echo "$METRICS"
