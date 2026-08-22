# Diagrams

## Flowchart, top down

```mermaid
graph TD
    A[Open file] --> B{Markdown?}
    B -->|yes| C[Parse with cmark]
    B -->|no| D[Pretty print]
    C --> E[Render natively]
    D --> E
    E --> F((Done))
```

## Flowchart, left to right

```mermaid
flowchart LR
    Source[Raw markdown] --> Parse[swift-markdown]
    Parse --> Lower[Block model]
    Lower --> Build[Attributed string]
    Build --> View[TextKit 2]
```

## Every shape and edge style

```mermaid
graph TD
    A[rectangle] --> B(rounded)
    B --- C{diamond}
    C -.-> D((circle))
    D ==> E([stadium])
    E --> F{{hexagon}}
    F --> G[[subroutine]]
    G --> H[(cylinder)]
```

## A wider graph

```mermaid
graph TD
    Start --> A1
    Start --> A2
    Start --> A3
    A1 --> Join
    A2 --> Join
    A3 --> Join
    Join --> End
```

## Sequence

```mermaid
sequenceDiagram
    participant U as User
    participant M as Marker
    participant D as Disk
    U->>M: Press space in Finder
    M->>D: Read the file
    D-->>M: Bytes
    M->>M: Parse and lay out
    M-->>U: Rendered page
    Note right of M: No WebView involved
```

## Unsupported, on purpose

```mermaid
gantt
    title A schedule
    section One
    Task :a1, 2026-01-01, 30d
```

## Broken, on purpose

```mermaid
graph TD
    A --> 
```
