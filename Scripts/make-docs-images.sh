#!/usr/bin/env bash
# Regenerates every screenshot in docs/images/.
#
# Two steps per shot: window-shot.sh takes the window through the window server
# with its own shadow, then frame-shot.swift stands it on a backdrop. Nothing here
# draws a window frame, because the capture already contains the real one.
#
# docs/images/ is curated and committed. QA/evidence/ is the raw per-row proof and
# churns; the two are deliberately not the same directory.
set -euo pipefail
cd "$(dirname "$0")/.."

RAW="$(mktemp -d)"
trap 'rm -rf "$RAW"' EXIT
mkdir -p docs/images

shot() {              # shot <name> <ground> [env...]
  local name="$1" ground="$2"; shift 2
  Scripts/window-shot.sh --shadow "$RAW/$name.png" "$@" > /dev/null
  swift Scripts/frame-shot.swift "$RAW/$name.png" "docs/images/$name.png" "$ground"
}

shot hero      dark  MARKER_OPEN=QA/fixtures/kitchen-sink.md MARKER_THEME=glass
shot diagrams  dark  MARKER_OPEN=QA/fixtures/diagrams.md     MARKER_THEME=dark
shot math      light MARKER_OPEN=QA/fixtures/math.md         MARKER_THEME=light
shot code      dark  MARKER_OPEN=QA/fixtures/languages.md    MARKER_THEME=dark
shot tables    light MARKER_OPEN=QA/fixtures/tables.md       MARKER_THEME=light
shot find      dark  MARKER_OPEN=QA/fixtures/kitchen-sink.md MARKER_THEME=dark MARKER_FIND=item
shot editing   dark  MARKER_OPEN=QA/fixtures/plain.md        MARKER_THEME=dark MARKER_EDIT=1
shot welcome   dark  MARKER_WELCOME=1

# Quick Look goes to QA evidence, not to docs/images.
#
# qlmanage -p drives the real preview extension, which is what makes it good
# evidence, but it stamps "[DEBUG]" onto the window title and a README image
# reading [DEBUG] tells the reader something untrue about the app. Driving Finder
# to press space instead needs UI automation that does not fire reliably here, so
# the honest answer is to keep the shot where its provenance is the point.
Scripts/ql-shot.sh QA/fixtures/kitchen-sink.md QA/evidence/_quicklook.png > /dev/null 2>&1 \
  || echo "quicklook: qlmanage produced no window" >&2

# The README hero icon, straight from the app icon's largest slot.
cp Marker/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png docs/images/logo.png
echo "logo: docs/images/logo.png"
