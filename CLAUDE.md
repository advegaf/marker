# Marker: project conventions for Claude Code

> Universal rules (no AI co-author trailers, no `git add -A`, no force-push without
> explicit authorization) live in `~/.claude/CLAUDE.md`. This file covers only what is
> specific to Marker.

## Build and test

- `project.yml` is the source of truth. `Marker.xcodeproj` is generated and gitignored.
  New Swift files under `Marker/` are picked up by the `sources` glob, so add the file
  and run `xcodegen generate`. Do not hand edit the pbxproj.
- `Scripts/test.sh` runs both suites. Two commands rather than one because XcodeGen
  cannot list a local SPM package's test targets in an Xcode scheme, and the package
  tests are the heaviest coverage in the repo. Running only `xcodebuild` silently skips
  all of it.
- Version lives in exactly one place, `MARKETING_VERSION` in `project.yml`. Both
  Info.plists read `$(MARKETING_VERSION)`.
- Release builds override the identity on the command line; `project.yml` stays ad-hoc
  signed for development. `Scripts/build-dmg.sh` is the whole release path.

## Where things live

- `MarkerCore` has **no AppKit**. If a type needs AppKit it belongs in `MarkerRender`.
  This boundary is what keeps the Mermaid engine and the highlighter testable in a
  second with no app host, so do not weaken it for convenience.
- `MarkerRender/MarkerTheme.swift` is the single token file. Read colours, spacing and
  metrics from it. `GuardTests` fails the suite on a hardcoded colour anywhere else.
- `Marker/UI/Theme/MarkerMotion.swift` holds the motion tokens. They are in the app
  target, not in `MarkerTheme`, because `MarkerTheme` links into the Quick Look appex
  and that extension animates nothing.
- `Marker/` is app only. The Quick Look extension may not import from it.

## Gotchas that have already cost a day

- **Never read `NSTextView.layoutManager`.** It is a permanent TextKit 1 fallback and
  it disables viewport layout with no warning. `.textStorage` is fine.
- **Editing probes print `document.source.text`.** Every WYSIWYG corruption bug so far
  rendered correctly on screen while destroying the Markdown behind it. Verifying the
  display proves nothing.
- **The Quick Look extension must stay sandboxed.** macOS deregisters a non-sandboxed
  preview extension and silently falls back to the plain text preview. It was
  unsandboxed once to read app preferences and it vanished from `pluginkit`. Theme is
  shared through `ThemeBridge` writing JSON into the extension's own container.
- **Intermittent failures are the interesting ones.** Autocorrect rewriting the
  rendered view showed up as three correct runs and one wrong. Rerunning would have
  hidden a bug that rewrites user files.
- **Measure before designing.** Four tiers of incremental reparse were planned and
  deleted by one measurement.

## Evidence capture

- Window scoped only: `screencapture -l <windowid>`, driven by `Scripts/window-shot.sh`.
  **Full screen and region capture are not used in this repo.** Both have already
  photographed unrelated personal content on this machine, and region capture was
  removed from the harness entirely so it cannot be reached for again.
- Any `MARKER_` prefixed variable arms the harness (`Harness.isActive`). That is what
  suppresses the first launch walkthrough during snapshots and deletes saved window
  state, which otherwise restored several windows that each acted on the launch flags.
- `docs/images/` is curated and committed. `QA/evidence/` is raw per row proof and
  churns; `_` prefixed files there are gitignored scratch.

## Commits

- `Marker vX.Y.Z: <one line>` with a body grouped by area, matching the existing log.
- Stage files by name. Never `git add -A`.
- `main` is public. Everything after the first push goes through a pull request.
