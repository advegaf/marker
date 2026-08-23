# Defects

Found by walking `feature-stories.csv` and driving the shipped app. Severity is
`logistical` for wrong behaviour or a crash, `ux` for right behaviour that reads or
feels wrong.

Every editing probe asserts on `document.source.text`, not on what is displayed.
All four WYSIWYG corruption bugs in this project's history rendered correctly on
screen while destroying the Markdown behind them.

---

## D-1 Any paragraph containing an apostrophe rendered as a code block

**Row** REN-10 **Severity** logistical **Status** fixed in v1.0.2

Expected: a paragraph renders as a paragraph.
Actual: it rendered as raw Markdown in a monospaced panel, backticks and all.

cmark applies smart punctuation, which rewrites the text of a node: `'` becomes a
curly `’`, `"` becomes `“ ”`, `--` becomes an en dash, `...` becomes an ellipsis.
The source range it reports still covers the original bytes, so verify-by-slice
compared a 3-byte `’` against a 1-byte `'`, failed, and marked the block opaque. An
opaque block still renders, in source-reveal mode, which is why nothing crashed.

The trigger is an apostrophe, so it hit most English prose. Every test passed and
every screenshot looked right because no fixture contained one. Found by opening
this project's own `ARCHITECTURE.md` in the app.

Fix: parse with `.disableSmartOpts`. That is also the honest choice here, since the
page is meant to show what is in the file, and this project's writing rules ban em
and en dashes outright, so drawing one the author did not type would be wrong even
if the source map could cope with it.

Regression: `SmartPunctuationTests`, which pins it from both ends. The characters
survive the round trip, and the blocks do not go opaque.

Evidence `REN-10.png` before, `REN-10-fixed.png` after.

---

## D-2 The launch open panel opened on top of the welcome window

**Row** WEL-3 **Severity** ux **Status** fixed in v1.0.0

Expected: a fresh install shows the walkthrough and nothing else.
Actual: a modal file browser opened over it, so the first thing a new user saw was
a file picker covering the thing explaining the app.

`applicationShouldOpenUntitledFile` checked a flag set in
`applicationDidFinishLaunching`, and AppKit does not guarantee it is asked after
that method runs. Asked first, the flag was still false.

Fix: check the stored key as well, which answers correctly in either order.

---

## D-3 Footnotes render as literal text

**Row** REN-12 **Severity** logistical **Status** open, deferred

Expected: `a reference[^1]` renders as a footnote marker with its body collected.
Actual: `[^1]` and `[^1]: The footnote body.` both render as plain literal text.

The cmark-gfm footnote extension is not enabled in the parser, so footnotes are not
part of the AST at all. Visible in `QA/fixtures/kitchen-sink.md`, which advertises a
footnote it does not get.

Deferred rather than fixed: enabling the extension changes the block structure and
needs its own source-range verification pass, which is not a change to make in the
same commit as a release. The fixture keeps the case so it stays visible.

---

## D-4 The DMG shipped with no artwork and nothing reported a problem

**Row** DMG-2 **Severity** ux **Status** fixed in v1.0.3

Expected: the install window shows the background.
Actual: a plain panel. Both icons were positioned correctly and the volume icon was
right, so it looked like a working release until it was mounted.

Homebrew's `create-dmg` sets the background with the legacy HFS colon path form, and
on macOS 26 that silently does nothing. The `.DS_Store` came out recording
`backgroundType` as a colour. No command failed.

A first fix, writing the AppleScript by hand and waiting longer for Finder to flush,
did not help. The path form is what is broken, not the timing, which was the wrong
assumption.

Fix: mint working alias bytes with sindresorhus/create-dmg, then rewrite the
`.DS_Store` with our own artwork and geometry through `ds_store` and `mac_alias`.

Regression: the build fails unless the finished `.DS_Store` carries
`backgroundType` 2 and a non empty background alias. A DMG whose artwork silently
vanished is exactly the thing that ships, because every other check passes.

Evidence `DMG-2.png`.

---

## D-5 A narrow table column was squeezed until its words broke in half

**Row** TBL-5 **Severity** ux **Status** fixed

Expected: a column is at least as wide as the widest word it has to hold.
Actual: `MarkerRender` was wrapped as "Marker" over "Render" while the neighbouring
paragraph column still had room.

`TableLayout` shrank every column by the same factor when the table was too wide.
That is wrong when the columns are lopsided: a short identifier next to a paragraph
gets a proportional share of a width it never asked for, because its share is
computed against the paragraph's enormous natural width.

Fix: every column keeps its minimum, which is the width of its widest whitespace
delimited run measured in that cell's own font, and only the space each column asked
for on top of that minimum is what gets shrunk.

Regression: `TableWidthTests`. The assertion is that narrowing the table does not
change the identifier column at all, so it does not hardcode a point size and stays
honest if the theme's fonts change.

Evidence `TBL-5.png` before, `TBL-5-fixed.png` after.

---

## Not defects, recorded so they are not rediscovered

**The slash menu cannot be captured by a snapshot run.** `NSPopover` needs a key
window, and a scripted launch does not reliably get one, so `slashMenu=false` in the
harness metrics is the harness, not the feature. The menu itself works; `CMD-1.png`
shows all sixteen commands.

**`screencapture -l` intermittently fails on a window that is plainly on screen.**
Edit mode fails most often, which fits a blinking caret redrawing the window.
`window-shot.sh` retries across several blink cycles.

**A window caught mid-teardown is still in the window list at a shrinking size.**
This read as the app collapsing its own document window to 104x114. It was the
previous instance dying. Both scripts now wait for the process to exit rather than
sleeping a fixed amount.

**A stray character once appeared at the end of a line in one capture.** The
attributed string was verifiably correct (`attrLen=63` for the expected text) and
the source was clean, and it did not reproduce. A compositing race in that one shot.
