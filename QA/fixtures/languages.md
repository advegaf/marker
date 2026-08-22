# Syntax highlighting

One fence per language, so a screenshot shows every palette at once.

```swift
@MainActor final class Renderer: Sendable {
    private let theme: MarkerTheme          // token colours live here
    func render(_ source: MarkdownSource) -> NSAttributedString {
        guard source.byteCount > 0 else { return .init() }
        return build(parse(source), scale: 1.5, retries: 0x1F)
    }
}
```

```python
@dataclass
class Layout:
    """Rank nodes, then order them."""
    nodes: list[str] = field(default_factory=list)

    def rank(self, edges: dict) -> bool:
        return len(self.nodes) > 0 and None not in edges  # done
```

```javascript
/* Fetch and cache. */
export const load = async (url) => {
  const res = await fetch(`${base}/${url}`, { cache: "force-cache" });
  if (!res.ok) throw new Error("failed");
  return res.json();
};
```

```rust
#[derive(Debug, Clone)]
pub struct Scene { pub nodes: Vec<Node> }

impl Scene {
    pub fn width(&self) -> u32 { self.nodes.len() as u32 * 120 }
}
```

```go
package layout

import "fmt"

func Rank(nodes []string) (int, error) {
    if len(nodes) == 0 {
        return 0, fmt.Errorf("empty: %q", `no nodes`)
    }
    var depth int64 = 1
    return int(depth), nil
}
```

```bash
#!/usr/bin/env bash
set -euo pipefail
for f in QA/fixtures/*.md; do
  echo "rendering $f"        # one per fixture
done
```

```sql
SELECT id, name FROM documents
WHERE kind = 'markdown' AND size > 1024
ORDER BY name ASC LIMIT 10;  -- newest first
```

```html
<!-- a small page -->
<article class="doc" data-theme="dark">
  <h1>Marker</h1>
  <p>Renders &amp; scrolls.</p>
</article>
```

```yaml
# project settings
name: Marker
version: 0.3.0
targets:
  - app
  - quicklook
settings:
  sandbox: false      # the app, not the extension
  hardened: true
```

```json
{"name":"marker","version":"0.3.0","types":["md","markdown"],"pro":{"editing":true,"tables":true},"empty":{}}
```

```
No language on this fence, so it renders as plain code
rather than being guessed at.
```
