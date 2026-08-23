#!/usr/bin/env bash
# Builds the release DMG, end to end, from a clean checkout.
#
#   Scripts/build-dmg.sh                 # Developer ID signed, not notarised
#   Scripts/build-dmg.sh --notarize      # also notarise and staple
#
# Notarising needs a keychain profile called "marker", created once with:
#
#   xcrun notarytool store-credentials marker \
#     --apple-id <your Apple ID> --team-id DV483F72N3 --password <app-specific password>
#
# The app-specific password comes from appleid.apple.com under Sign-In and Security.
# Without notarisation Gatekeeper still shows "Apple could not verify Marker is free
# of malware" on first open, so a release build should always use --notarize.
#
# Wave has no script for this at all, only prose in its CLAUDE.md, which is why its
# exact release commands had to be recovered from a permissions allowlist a year
# later. This file is that prose made runnable.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=0
[ "${1:-}" = "--notarize" ] && NOTARIZE=1

IDENTITY="Developer ID Application: Angel Vega Figueroa (DV483F72N3)"
TEAM="DV483F72N3"
PROFILE="marker"

# ds_store and mac_alias write the .DS_Store in phase two.
#   pip3 install --user ds-store mac-alias
DSSTORE_SITE="$HOME/Library/Python/3.9/lib/python/site-packages"

VERSION=$(awk -F'"' '/MARKETING_VERSION/{print $2; exit}' project.yml)
[ -n "$VERSION" ] || { echo "cannot read MARKETING_VERSION from project.yml" >&2; exit 1; }
DMG="dist/Marker-$VERSION.dmg"

PYTHONPATH="$DSSTORE_SITE" python3 -c "import ds_store, mac_alias" 2>/dev/null \
  || { echo "python ds_store missing: pip3 install --user ds-store mac-alias" >&2; exit 1; }
command -v npx > /dev/null || { echo "npx missing: brew install node" >&2; exit 1; }

echo "==> Marker $VERSION"

# ---------------------------------------------------------------- build
xcodegen generate > /dev/null

# Release, and Release only. A Debug build carries the test bundle in PlugIns,
# which would ship 7 MB of XCTest inside the app and fail notarisation on a
# bundle that has no business being there.
xcodebuild -project Marker.xcodeproj -scheme Marker -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | tail -3

BUILT=$(xcodebuild -project Marker.xcodeproj -scheme Marker -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
APP="$BUILT/Marker.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

# A Release build must not carry a test bundle. Checked rather than assumed,
# because the Debug products directory does contain one and the two paths look
# identical apart from the configuration.
if [ -d "$APP/Contents/PlugIns/MarkerTests.xctest" ]; then
  echo "MarkerTests.xctest is embedded in the release app" >&2
  exit 1
fi

echo "==> signature"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -2
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Timestamp|flags" | head -3

# ------------------------------------------------------------ volume icon
# Built from the app icon's own slots rather than a separate asset, so the disk
# image and the app can never drift apart.
ICONSET=dist/Marker.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC=Marker/Assets.xcassets/AppIcon.appiconset
cp "$SRC/icon_16x16.png"      "$ICONSET/icon_16x16.png"
cp "$SRC/icon_16x16@2x.png"   "$ICONSET/icon_16x16@2x.png"
cp "$SRC/icon_32x32.png"      "$ICONSET/icon_32x32.png"
cp "$SRC/icon_32x32@2x.png"   "$ICONSET/icon_32x32@2x.png"
cp "$SRC/icon_128x128.png"    "$ICONSET/icon_128x128.png"
cp "$SRC/icon_128x128@2x.png" "$ICONSET/icon_128x128@2x.png"
cp "$SRC/icon_256x256.png"    "$ICONSET/icon_256x256.png"
cp "$SRC/icon_256x256@2x.png" "$ICONSET/icon_256x256@2x.png"
cp "$SRC/icon_512x512.png"    "$ICONSET/icon_512x512.png"
cp "$SRC/icon_512x512@2x.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns -o dist/VolumeIcon.icns "$ICONSET"
rm -rf "$ICONSET"

# ------------------------------------------------------------- background
MARKER_VERSION="$VERSION" swift Scripts/generate-dmg-background.swift dist/dmg-background.png

# ---------------------------------------------------------------- staging
STAGE=dist/staging
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# ------------------------------------------------------------------- dmg
rm -f "$DMG"
RW=dist/rw.dmg
rm -f "$RW"

# Two phases, and the reason is a Tahoe regression rather than a preference.
#
# Homebrew's create-dmg (andreyvit) sets the background with the legacy HFS colon
# path form, `set background picture of opts to file ".background:name.png"`, and
# on macOS 26 that silently does nothing. The DMG builds, both icons land exactly
# where they were told to, and the .DS_Store comes out recording backgroundType as
# a COLOUR. No command fails, so it looks like a working release until somebody
# mounts it. Writing the AppleScript by hand and waiting longer does not help: the
# path form is what is broken, not the timing.
#
# sindresorhus/create-dmg produces a working background alias, so phase one is
# only there to mint those alias bytes. Phase two replaces everything else: our
# artwork, our icon geometry, our volume icon.
#
# This is the same route selfcontrol takes, for the same reason.
STAGE_APP="$STAGE/Marker.app"
SINDRE="dist/Marker $VERSION.dmg"
rm -f "$SINDRE"

echo "==> phase 1: base image"
npx --yes create-dmg@latest --no-code-sign --overwrite "$STAGE_APP" dist/ 2>&1 | tail -3
[ -f "$SINDRE" ] || { echo "sindresorhus create-dmg did not produce $SINDRE" >&2; exit 1; }

echo "==> phase 2: our artwork and geometry"
hdiutil convert -quiet "$SINDRE" -format UDRW -o "$RW"
rm -f "$SINDRE"
hdiutil attach -readwrite -noverify "$RW" > /dev/null
MOUNT="/Volumes/Marker"
[ -d "$MOUNT" ] || { echo "expected a volume at $MOUNT" >&2; exit 1; }

cp dist/dmg-background.tiff "$MOUNT/.background/dmg-background.tiff"
cp dist/VolumeIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true

# Rewrite the .DS_Store from scratch, keeping the one thing phase one was for:
# alias bytes that Finder still honours. The background moves to a single
# dot-file at the volume root so .background/ does not show up for anyone
# browsing with hidden files on.
#
# Icon positions agree with the arrow in generate-dmg-background.swift, which
# runs from x=258 to x=402 at y=205, so the two icons sit either side of it.
PYTHONPATH="$DSSTORE_SITE" python3 - "$MOUNT" <<'PYEOF'
import os, shutil, sys
from ds_store import DSStore
from mac_alias import Alias

mount = sys.argv[1]
ds_path = os.path.join(mount, ".DS_Store")
old_bg = os.path.join(mount, ".background", "dmg-background.tiff")
new_bg = os.path.join(mount, ".bg.tiff")

shutil.move(old_bg, new_bg)
try:
    os.rmdir(os.path.join(mount, ".background"))
except OSError as error:
    print(f"warning: could not remove .background: {error}", file=sys.stderr)

alias = Alias.for_file(new_bg).to_bytes()

os.remove(ds_path)
with DSStore.open(ds_path, "w+") as ds:
    ds["."]["icvp"] = {
        "arrangeBy": "none",
        "backgroundColorBlue": 0.0,
        "backgroundColorGreen": 0.0,
        "backgroundColorRed": 0.0,
        "backgroundImageAlias": alias,
        "backgroundType": 2,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": 128.0,
        "labelOnBottom": True,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "showIconPreview": False,
        "showItemInfo": False,
        "textSize": 12.0,
        "viewOptionsVersion": 1,
    }
    ds["."]["bwsp"] = {
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "SidebarWidth": 0,
        "WindowBounds": "{{200, 160}, {660, 428}}",
    }
    ds["."]["icvl"] = (b"type", b"icnv")
    ds["Marker.app"]["Iloc"] = (175, 205)
    ds["Applications"]["Iloc"] = (485, 205)
print(f"wrote .DS_Store with a {len(alias)} byte background alias")
PYEOF

for f in "$MOUNT/.bg.tiff" "$MOUNT/.DS_Store" "$MOUNT/.VolumeIcon.icns"; do
  [ -e "$f" ] && chflags hidden "$f" 2>/dev/null || true
done

# Verify before sealing. A DMG whose artwork silently vanished is exactly the
# thing that ships, because every other check passes.
PYTHONPATH="$DSSTORE_SITE" python3 - "$MOUNT" <<'PYEOF'
import sys
from ds_store import DSStore
with DSStore.open(sys.argv[1] + "/.DS_Store", "r") as ds:
    icvp = ds["."]["icvp"]
if icvp.get("backgroundType") != 2 or not icvp.get("backgroundImageAlias"):
    sys.exit("the .DS_Store does not carry a background image alias")
print("background alias verified")
PYEOF

# macOS recreates .fseventsd on every filesystem event, so it goes last, then
# sync and detach immediately.
rm -rf "$MOUNT/.fseventsd"
sync; sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
sleep 1

hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"
rm -rf "$STAGE"

codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" -eq 1 ]; then
  if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
    cat >&2 <<EOF

No notarytool keychain profile called "$PROFILE".

Create it once, then run this again:

  xcrun notarytool store-credentials $PROFILE \\
    --apple-id <your Apple ID> --team-id $TEAM --password <app-specific password>

EOF
    exit 1
  fi
  echo "==> notarising, this waits on Apple"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tail -5
  xcrun stapler staple "$DMG" 2>&1 | tail -2
fi

# ----------------------------------------------------------------- verify
echo "==> verify"
MOUNT=$(hdiutil attach "$DMG" -nobrowse -readonly | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

# Gatekeeper is what a downloader actually meets, and it is the only check that
# tells notarised apart from merely signed.
#
# spctl exits 3 on "rejected", and under `set -euo pipefail` that killed the whole
# script here, silently: the DMG was already built so the run looked fine, but the
# size line and the final path never printed and the exit code was 3. It would have
# healed itself the moment notarisation started working, which is the worst kind of
# bug to leave in a release script.
#
# So: informational when we did not notarise, a hard gate when we did.
set +e
spctl -a -vv "$MOUNT/Marker.app" 2>&1 | sed 's/^/    /'
GATE=${PIPESTATUS[0]}
set -e

if [ "$NOTARIZE" -eq 1 ]; then
  [ "$GATE" -eq 0 ] || { echo "Gatekeeper rejected a notarised build" >&2; exit 1; }
  xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /'
elif [ "$GATE" -ne 0 ]; then
  echo "    (unnotarised, so Gatekeeper rejects it. Run with --notarize for a release.)"
fi

echo "    size: $(du -h "$DMG" | cut -f1)"
hdiutil detach "$MOUNT" -quiet
trap - EXIT

echo "==> $DMG"
