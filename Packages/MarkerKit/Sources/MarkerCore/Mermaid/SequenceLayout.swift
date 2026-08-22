import CoreGraphics
import Foundation

/// Lays out a sequence diagram.
///
/// Much simpler than a flowchart: participants are columns in declaration order,
/// messages are rows in source order. There is nothing to optimise, so the work is
/// all in measuring and in the small details that make one readable, mainly keeping
/// message text off the lifelines and giving self-calls a loop rather than a
/// zero-length arrow.
public enum SequenceLayout {

    public static func scene(
        for diagram: SequenceDiagram,
        style: MermaidStyle = MermaidStyle(),
        measure: TextMeasure = .deterministic
    ) -> MermaidScene {
        var shapes: [MermaidScene.Shape] = []
        var paths: [MermaidScene.Path] = []
        var texts: [MermaidScene.Text] = []
        var labelBackgrounds: [CGRect] = []

        let headHeight = style.fontSize * 2.6
        let rowHeight = style.fontSize * 2.9
        let selfLoopHeight = style.fontSize * 2.0

        var top = style.padding
        if let title = diagram.title {
            let size = measure.size(title, style.fontSize * 1.1)
            texts.append(MermaidScene.Text(
                string: title,
                frame: CGRect(x: style.padding, y: top, width: max(size.width, 1), height: size.height),
                role: .title
            ))
            top += size.height + style.fontSize
        }

        // Columns are wide enough for the widest thing that has to sit in them: the
        // participant's own name, or the longest message text on either side of it.
        var columnWidths: [CGFloat] = []
        for participant in diagram.participants {
            let name = measure.size(participant.label, style.fontSize).width + style.nodePaddingX * 2
            columnWidths.append(max(name, style.fontSize * 6))
        }
        for message in diagram.messages where message.from == message.to {
            guard let index = diagram.participants.firstIndex(where: { $0.id == message.from }) else { continue }
            let text = measure.size(message.text, style.edgeLabelFontSize).width
            columnWidths[index] = max(columnWidths[index], text + style.fontSize * 4)
        }

        var centres: [String: CGFloat] = [:]
        var cursor = style.padding
        for (index, participant) in diagram.participants.enumerated() {
            centres[participant.id] = cursor + columnWidths[index] / 2
            cursor += columnWidths[index] + style.nodeSpacing
        }
        let totalWidth = cursor - style.nodeSpacing + style.padding

        // Participant heads.
        for (index, participant) in diagram.participants.enumerated() {
            let centre = centres[participant.id] ?? 0
            let width = columnWidths[index]
            let frame = CGRect(
                x: centre - width / 2, y: top,
                width: width, height: headHeight
            )
            shapes.append(MermaidScene.Shape(
                kind: .rectangle(cornerRadius: participant.isActor ? headHeight / 2 : 4),
                frame: frame
            ))
            texts.append(MermaidScene.Text(string: participant.label, frame: frame, role: .participant))
        }

        let lifelineTop = top + headHeight
        var y = lifelineTop + style.fontSize

        for (index, message) in diagram.messages.enumerated() {
            let fromX = centres[message.from] ?? 0
            let toX = centres[message.to] ?? 0
            let stroke = strokeFor(message.style, style: style)

            if message.from == message.to {
                // A self call loops out to the right and back, because an arrow from a
                // point to itself is invisible.
                let reach = fromX + style.fontSize * 3.2
                let topY = y
                let bottomY = y + selfLoopHeight
                paths.append(MermaidScene.Path(
                    points: [
                        CGPoint(x: fromX, y: topY),
                        CGPoint(x: reach, y: topY),
                        CGPoint(x: reach, y: bottomY),
                        CGPoint(x: fromX, y: bottomY),
                    ],
                    stroke: stroke,
                    hasArrowHead: true,
                    isOpenHead: isOpen(message.style),
                    isCrossHead: message.style == .cross
                ))
                if !message.text.isEmpty {
                    let size = measure.size(message.text, style.edgeLabelFontSize)
                    let box = CGRect(
                        x: reach + 6, y: topY + (selfLoopHeight - size.height) / 2,
                        width: size.width, height: size.height
                    )
                    texts.append(MermaidScene.Text(string: message.text, frame: box, role: .edgeLabel))
                }
                y = bottomY + rowHeight * 0.6
            } else {
                if !message.text.isEmpty {
                    let size = measure.size(message.text, style.edgeLabelFontSize)
                    let midX = (fromX + toX) / 2
                    let box = CGRect(
                        x: midX - size.width / 2 - 5,
                        y: y - size.height - 5,
                        width: size.width + 10,
                        height: size.height + 2
                    )
                    labelBackgrounds.append(box)
                    texts.append(MermaidScene.Text(string: message.text, frame: box, role: .edgeLabel))
                }
                paths.append(MermaidScene.Path(
                    points: [CGPoint(x: fromX, y: y), CGPoint(x: toX, y: y)],
                    stroke: stroke,
                    hasArrowHead: true,
                    isOpenHead: isOpen(message.style),
                    isCrossHead: message.style == .cross
                ))
                y += rowHeight
            }

            // Notes attached to this message sit directly under it.
            for note in diagram.notes where note.afterMessage == index {
                let size = measure.size(note.text, style.edgeLabelFontSize)
                let width = size.width + style.fontSize * 1.6
                let height = size.height + style.fontSize
                let x: CGFloat
                switch note.placement {
                case .leftOf(let target):
                    x = (centres[target] ?? 0) - width - style.fontSize
                case .rightOf(let target):
                    x = (centres[target] ?? 0) + style.fontSize
                case .over(let targets):
                    let xs = targets.compactMap { centres[$0] }
                    let middle = xs.isEmpty ? totalWidth / 2 : xs.reduce(0, +) / CGFloat(xs.count)
                    x = middle - width / 2
                }
                let frame = CGRect(x: max(x, style.padding), y: y - rowHeight * 0.4, width: width, height: height)
                shapes.append(MermaidScene.Shape(kind: .note, frame: frame))
                texts.append(MermaidScene.Text(string: note.text, frame: frame, role: .note))
                y += height + style.fontSize * 0.5
            }
        }

        let bottom = y + style.fontSize
        // Lifelines are drawn last so they sit behind nothing and span the full run.
        var lifelines: [MermaidScene.Path] = []
        for participant in diagram.participants {
            let x = centres[participant.id] ?? 0
            lifelines.append(MermaidScene.Path(
                points: [CGPoint(x: x, y: lifelineTop), CGPoint(x: x, y: bottom)],
                stroke: .dashed(width: 1, pattern: [4, 4]),
                hasArrowHead: false
            ))
        }

        return MermaidScene(
            size: CGSize(width: totalWidth, height: bottom + style.padding),
            shapes: shapes,
            paths: lifelines + paths,
            texts: texts,
            labelBackgrounds: labelBackgrounds
        )
    }

    private static func strokeFor(
        _ style: SequenceDiagram.ArrowStyle, style layout: MermaidStyle
    ) -> MermaidScene.Stroke {
        switch style {
        case .dotted, .dottedOpen: return .dashed(width: 1.5, pattern: [5, 4])
        case .solid, .solidOpen, .cross: return .solid(width: 1.5)
        }
    }

    private static func isOpen(_ style: SequenceDiagram.ArrowStyle) -> Bool {
        style == .solidOpen || style == .dottedOpen
    }
}
