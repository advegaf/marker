# Welcome to Marker

This is a Markdown file, open in Marker. Everything below is being rendered right
now by the app you just installed. There is no browser engine involved: the page is
one TextKit 2 text view, and the diagrams and formulas are drawn by Swift.

You can edit this file. Press **Edit** in the toolbar and type anywhere on the page.

## Try these four things

- [x] Press `Command F` and search for the word *native*. Every match stays lit.
- [ ] Pinch on the trackpad. The text re-lays out instead of stretching, so it
      never goes soft.
- [ ] Press `Control Command 1`, `2` and `3` to move between Liquid Glass, Dark
      and Light.
- [ ] Quit Marker, find a `.md` file in Finder, and press space.

## It reads real Markdown

Tables come out as tables:

| What | Rendered by | Ships as |
|:-----|:------------|---------:|
| Text | TextKit 2 | native |
| Math | SwiftMath | native |
| Diagrams | a Swift engine | native |
| Everything else | AppKit | native |

Code gets highlighted per language, with no JavaScript anywhere near it:

```swift
func slice(_ range: Range<Int>) -> String? {
    guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
    return String(decoding: bytes[range], as: UTF8.self)
}
```

> Blockquotes get a bar. Horizontal rules get a hairline. Links get a colour and
> nothing else, because a document is for reading.

## Math is typeset, not screenshotted

Inline, like $e^{i\pi} + 1 = 0$, and on its own line:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

## Diagrams are laid out, not fetched

```mermaid
graph LR
    A[Markdown file] --> B[Parse]
    B --> C[Block list]
    C --> D[Attributed string]
    D --> E[TextKit 2]
```

## Editing writes Markdown, not something like it

Marker keeps the raw text of your file as the source of truth and splices your
edits into it byte by byte. Only the bytes you changed change. Setext headings stay
setext, `*` bullets stay `*`, and your table padding stays exactly as you left it.

Open a README you track in git, fix one typo, and the diff is one line.

Type `/` on an empty line to insert a table, a code block, a diagram or a formula.

---

Delete all of this and start writing. It is your file now: this copy lives in
`~/Library/Application Support/Marker/`, so nothing here is precious.
