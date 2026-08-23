# Changelog

Versions below 1.0.4 were development milestones. 1.0.4 is the first public
release, so everything under it is what is in that build.

## 1.0.4

- A narrow table column was squeezed until its words broke in half. `MarkerRender`
  came out wrapped as "Marker" over "Render" while the paragraph column beside it
  still had room. Every column now keeps the width of its widest whitespace
  delimited run, and only the space asked for on top of that gets shrunk.
- `QA/feature-stories.csv`, 142 rows, one per observable behaviour, each citing a
  concrete code gate. `QA/defects.md` records five defects, four fixed.
- Known: footnotes render as literal text. The cmark-gfm footnote extension is not
  enabled.

## 1.0.3

- `Scripts/build-dmg.sh` builds the release DMG end to end, Developer ID signed,
  with `--notarize` when credentials exist.
- `Scripts/generate-dmg-background.swift` draws the install window art.
- Fixed: the DMG shipped with no artwork and nothing reported a problem. Homebrew's
  create-dmg sets the background with a path form that macOS 26 ignores, so the
  `.DS_Store` recorded a colour instead. The build now fails unless the finished
  `.DS_Store` carries a background alias.

## 1.0.1

- `Scripts/frame-shot.swift` and `Scripts/make-docs-images.sh` regenerate every
  screenshot in `docs/images` from the real app in one command.
- `MARKER_FIND=<query>` opens the find bar already searching, which is what makes
  the all matches highlighted claim capturable.
- Fixed: seeding the find pasteboard looked right and was wrong. The bar held the
  query, the count read 0, and one match highlighted. Incremental searching starts
  only when the finder is handed a string through its client.
- Fixed: `window-shot.sh` waited 0.4s after killing a previous instance, and
  screencapture answered "could not create image from window" for a window that was
  plainly on screen.

## 1.0.0

- A walkthrough on first launch: the icon, the version, four lines naming what the
  app does, and a button that opens a bundled welcome document. The document is
  copied to Application Support first, so pressing Edit on it cannot fail on
  permissions or invalidate the code signature.
- A Help menu, which did not exist, so the walkthrough is reachable again.
- `MarkerMotion` holds the app's motion tokens: springs, no timing curves, and a
  reduce motion substitute that keeps the fade and drops the travel.
- Fixed: the launch open panel opened on top of the welcome window. AppKit does not
  guarantee `applicationShouldOpenUntitledFile` is asked after
  `applicationDidFinishLaunching`.
- Fixed: the welcome window measured its height before SwiftUI applied the design
  width, so every row wrapped and the panel sat in a window with dead space under it.
- `MARKETING_VERSION` had never been bumped past 0.1.0, so the About panel and any
  DMG would have shipped saying 0.1.0.

## 0.10.0

- Every feature is free. The 14 day trial, the Ed25519 licence verifier, the key
  entry UI and the trial ended alert are gone. Nothing gates editing.

## 0.9.0

- Inline formatting: Command B, Command I, Command Shift X and Command E, driven off
  parsed runs rather than asterisk matching, so it recognises both `*` and `_` forms.
- Fixed: macOS automatic substitutions were rewriting the rendered view and the
  mirror wrote the rewrite into the file. All automatic substitutions are now off as
  a correctness requirement, not a preference.
- Fixed: the UTF-16 to UTF-8 conversion existed twice and only one copy was correct,
  so bolding a CJK selection styled the first character and left the rest alone.

## 0.8.0

- Editing the rendered page. Keystrokes become byte splices into the original file
  through `EditMapper`, which refuses rather than guesses when a change cannot be
  mapped back safely.
- Fixed three ways the mirror destroyed Markdown while rendering correctly on screen.

## 0.7.1

- The caret scrolls into view when typing past the fold.
- Parsing stopped being quadratic. `MarkdownSource` holds its UTF-8 bytes instead of
  rebuilding them per call: a 367 KB file went from 100 ms to 1.4 ms. This is why
  there is no incremental reparse machinery in the repo.

## 0.7.0

- Slash commands in the editor: 16 snippets, inserted at the caret.

## 0.6.1

- The open file is watched with `DispatchSourceFileSystemObject`, handling both
  modify and rename-over. A clean document reloads; a dirty one gets a banner.

## 0.6.0

- Quick Look follows the app's theme, shared through a JSON file written into the
  extension's own container. The extension stays sandboxed: macOS deregisters a
  preview extension that is not.

## 0.5.0

- GFM tables, and a native Mermaid engine covering `flowchart` and `sequenceDiagram`.
  No JavaScript, no WebView. Anything else renders as a styled code block that says
  the type is not supported yet.

## 0.4.0

- LaTeX typeset natively through SwiftMath, inline and display.
- Zoom around the pointer, re-laying out at real point sizes rather than scaling a
  bitmap, so text stays sharp at any scale.

## 0.3.0

- Syntax highlighting for fourteen languages, hand written rather than shipping
  JavaScriptCore to colour a fenced block.
- Liquid Glass as a material rather than as a third palette. Before this, Glass and
  Dark resolved to the same colours and the setting appeared to do nothing.

## 0.2.1

- App icon, Quick Look verification, and evidence capture scoped to a single window.

## 0.2.0

- Toolbar, read only by default, and a Markdown source view.

## 0.1.0

- Native macOS Markdown viewer: TextKit 2, swift-markdown, three themes, find,
  scrolling, and Quick Look.
