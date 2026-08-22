#!/usr/bin/env bash
# Runs every test in the project.
#
# Two commands rather than one because XcodeGen cannot list a local SPM package's
# test targets in an Xcode scheme, and the package tests are the heaviest coverage
# in the repo (source-range golden tests, highlighter tables, mermaid geometry,
# the edit fuzz test). Running only xcodebuild would silently skip all of it.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> package tests (no app host)"
( cd Packages/MarkerKit && swift test )

echo "==> app tests"
xcodebuild -project Marker.xcodeproj -scheme Marker test \
  | grep -E "Test Suite|Test Case.*(failed|error)|Executed .* tests|\*\* TEST"
