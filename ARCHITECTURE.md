# Architecture

Marker renders Markdown into one TextKit 2 `NSTextView` and edits it by splicing
bytes back into the original file. Everything below follows from those two
sentences.

## The pipeline

```mermaid
graph LR
    A[Markdown file] --> B[MarkdownSource]
    B --> C[MarkdownParser]
    C --> D[ASTLowering]
    D --> E[BlockNode list]
    E --> F[AttributedBuilder]
    F --> G[MarkdownTextView]
    G --> H[EditMapper]
    H --> I[TextEdit]
```

`EditMapper` produces a `TextEdit`, which is applied straight back to
`MarkdownSource` and starts the loop again.

`MarkdownSource` holds the file's UTF-8 bytes. `MarkdownParser` wraps swift-markdown
(cmark-gfm) and `ASTLowering` walks the AST into a flat list of `BlockNode` values
with source ranges attached. `AttributedBuilder` turns those into an
`NSAttributedString`. `EditMapper` runs the loop backwards: given a change to a
render range, it works out which bytes of the source that means, or refuses.

The loop closes on `MarkdownSource`, not on the attributed string. That is the point.

## Two targets, and the line between them

| Target | Contents |
|---|---|
| `MarkerCore` | No AppKit. Document model, parser bridge and lowering, the fourteen language highlighter, JSON printer, table model and Markdown writer, and the whole Mermaid engine: lexer, parser, flowchart and sequence layout, producing a value typed `MermaidScene` |
| `MarkerRender` | AppKit, default MainActor isolation. `MarkerTheme`, the attributed builder, math and Mermaid drawing, `TableLayout`, `MarkdownTextView`, `ZoomController`, `OffscreenRenderer` |

The boundary is compiler enforced and it earns its keep twice. Mermaid layout is
asserted on coordinates rather than on pixels, so roughly thirty fixture diagrams
run headless in `swift test` in about a second with no app host and no bundle
loader. And the Quick Look extension depends on `MarkerRender` only, so importing
editing code from render code fails to build rather than failing at runtime inside
an appex.

A trap worth writing down: swift-markdown's `Markup` is a struct wrapping shared
`RawMarkup` class storage and is **not** `Sendable`. No `Document` or `Markup` value
may cross an actor boundary. The rule is that parsing and lowering happen inside one
`nonisolated` function and only `[BlockNode]` comes back. Mermaid has the same shape:
only the value typed `MermaidScene` crosses.

## Why the raw string is the source of truth

The alternative is to treat the attributed string as authoritative and serialize the
AST back to Markdown on save. That normalizes everything. Setext `===` headings
become `#`, `*` bullets become `-`, table padding is rewritten, hard wrapped
paragraphs re-join. Someone opens a git tracked README, fixes one typo, and gets a
four hundred line diff. They do not use the app again.

Byte splicing means only the bytes the user changed change. Raw HTML, front matter
and reference links pass through byte identical for free, because nothing ever looks
at them.

The safety property that follows is the one that matters: **save serializes
`MarkdownSource.text`, which is a pure splice result and never consults the block
index. A fully corrupted source map produces a wrong render, never a wrong save.**

## Three coordinate spaces

Confusing these is the entire emoji and CJK bug class.

| Space | Unit | Spoken by |
|---|---|---|
| Source | UTF-8 byte offset into `MarkdownSource.text` | the model, and every `TextEdit` |
| Render | UTF-16 offset into `NSTextStorage` | AppKit, and nothing else |
| Line and column | swift-markdown's `SourceLocation` | the parser boundary only |

`SourceLocation.column` is a 1-based **UTF-8 byte** offset from the line start, so
with a `LineIndex` of line start offsets the conversion is exactly
`lineStarts[line - 1] + (column - 1)`.

The UTF-16 to UTF-8 conversion lives in exactly one place, `OffsetConversion`. It was
written twice once, and only one copy got fixed, so bolding a CJK selection styled
the first character and left the rest alone. One implementation, one place.

## Verify by slice

cmark computes inline positions against each block's reconstructed content buffer, so
for content that was dedented on the way in, list item continuations, block quotes,
indented code, the reported column can be off by the stripped prefix. If the map is
wrong, every edit corrupts the file.

So `SourceVerifier` checks rather than trusts. For every inline node it slices
`source[computedRange]` and compares it against the node's own literal, on a byte
fast path:

```swift
if let bytes = source.byteSlice(range), bytes.elementsEqual(literal.utf8) { return true }
```

On a mismatch it searches for the literal inside the enclosing block starting from
the computed offset and marks the run recovered. If that fails too the block is
marked opaque, which still renders but is edited through the Markdown source view and
therefore cannot be corrupted. `MARKER_MAP_DEBUG` prints every failure, so the rate is
known rather than assumed.

## EditMapper refuses rather than guesses

`EditMapper` maps a change to a render range back to a source edit. When it cannot do
that safely it throws, and the window subtitle explains why for a few seconds.

```swift
public enum Refusal: Error, Equatable {
    case syntheticText   // bullets, ordinals, checkboxes: drawn, not in the file
    case crossesBlocks
    case attachment      // tables, diagrams, formulas
    case opaqueBlock
}
```

A refused keystroke is a small annoyance. A guessed one silently rewrites somebody's
file.

## The mirror, and three bugs it caused

The rendered editor watches `NSTextStorageDelegate.textStorage(_:didProcessEditing:...)`
rather than returning `false` from `textView(_:shouldChangeTextIn:replacementString:)`.
That second one is the tempting chokepoint and it breaks IME outright, along with
autocorrect and dictation. Letting AppKit mutate the storage and reconciling
afterwards keeps input methods, spelling, Services and drag and drop working.

Three bugs came out of that path and all three rendered correctly on screen while
destroying the Markdown behind them:

1. `textDidChange` copied the storage into the source. Right in the Markdown source
   view, catastrophic in the rendered one.
2. The derived update flag covered only the mirror's own writes, so the first render
   arrived as one enormous user edit.
3. An end offset landing exactly at a run's start fell through to "past the last run",
   which turned insertions into replacements.

The lesson is in the test suite now: **editing probes print `document.source.text`, not
what is on screen.** A fourth bug had the same shape and a different cause. macOS
automatic substitutions were rewriting the rendered view and the mirror faithfully
wrote the rewrite into the file, so every automatic substitution is off in
`MarkdownTextView`, as a correctness requirement rather than as a preference.

## TextKit 2, and the things that silently break it

- **Never touch `.layoutManager`.** Reading that property is a permanent TextKit 1
  fallback and it disables viewport layout and `NSTextAttachmentViewProvider` with no
  warning. `.textStorage` is safe, since `NSTextContentStorage` is `NSTextStorageObserving`.
- **`isVerticallyResizable = false`.** The view owns its own frame. With it true,
  AppKit sizes the view from what has already been laid out, and TextKit 2 lays out
  lazily around the viewport, so a long document reports a short height and scrolling
  stops partway down. A 5450 line file reported 1731pt against a real 167925pt.
- **`ensureLayout(for: documentRange)` stays viewport bounded** once a viewport layout
  controller is attached, which is why the height is measured by enumerating every
  fragment with `.ensuresLayout` instead.
- **`drawsBackground` stays true even in glass**, with a clear `backgroundColor`.
  Code panels, quote bars and rules are painted in `drawBackground(in:)`, and AppKit
  only calls that when the view is drawing a background. Turning it off strips every
  decoration in one theme only.
- **Programmatic scrolling goes through `scrollToEndOfDocument`**, not by moving the
  clip view, which leaves TextKit 2's viewport at the old region and paints a blank
  page.

## Zoom

`NSScrollView.setMagnification(_:centeredAtPoint:)` scales the clip view's bounds
transform without re-rasterizing, and TextKit 2 renders each fragment into a CALayer
at the backing scale factor, so at 3x you are stretching a 2x bitmap. The gesture
scales live, then on `didEndLiveMagnifyNotification` the gesture is folded into
`ZoomController.scale`, magnification resets to 1.0, the theme is rebuilt at the new
base point size, and the page re-renders from the already parsed block list. Text
lays out at real point sizes and reflows to the window width rather than growing a
horizontal scrollbar.

## What is not built

Stated so that absent is a decision rather than an oversight.

- Table cell editing and a Mermaid source editor. Tables and diagrams render as
  images and are edited through the Markdown source view.
- Find does not reach text inside a live table attachment. Buying that back means a
  custom `NSTextFinderClient` over a flattened plain text projection. Searching the
  raw Markdown instead would be wrong, since `hello **world**` would not match a
  search for `hello world`.
- Mermaid covers `flowchart` and `sequenceDiagram`. Class, state, pie and gantt render
  as a styled code block that says the type is not supported yet.
- Flowchart layout ranks by longest path, which assumes a DAG. A cycle still renders
  but the back edge is placed by ranking rather than routed around the graph, so it
  reads as an arrow pointing the wrong way rather than as a loop.
- Incremental reparse. Four tiers of it were planned and then measured away: holding
  the UTF-8 bytes instead of rebuilding them per call took a 367 KB file from 100 ms
  to 1.4 ms, and a full reparse at that speed is cheap enough to be the only path.

## Performance notes worth keeping

`MarkdownSource` stores its bytes rather than recomputing them. `slice` is called once
per inline run during lowering, and rebuilding the array each time made parsing
quadratic in document size. That one change is why there is no incremental reparse
machinery in this repo.

Code fences fold intra-block newlines to U+2028, because `paragraphSpacing` fires at
every `\n` and a fenced block came out double spaced otherwise.
