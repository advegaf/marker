import AppKit
import SwiftUI
import MarkerCore

/// The popover that appears when you type `/` in the editor.
///
/// Anchored at the caret rather than at the mouse, because the caret is where the
/// person is looking and the mouse is probably nowhere near.
@MainActor
final class SlashCommandMenu {

    private var popover: NSPopover?
    private let model = Model()

    var isVisible: Bool { popover?.isShown ?? false }

    /// How many commands the menu is currently offering, for the QA harness to
    /// assert on without needing a picture of a popover.
    var visibleCount: Int { isVisible ? model.commands.count : 0 }

    /// Called with the chosen command.
    var onPick: ((SlashCommand) -> Void)?

    // MARK: Showing

    func show(commands: [SlashCommand], at rect: NSRect, in view: NSView) {
        guard !commands.isEmpty else { return hide() }
        model.commands = commands
        model.selected = 0
        model.onPick = { [weak self] command in
            self?.hide()
            self?.onPick?(command)
        }

        if popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = NSHostingController(rootView: MenuView(model: model))
            self.popover = popover
        }
        popover?.contentSize = NSSize(width: 320, height: min(CGFloat(commands.count) * 38 + 12, 320))

        guard let popover, !popover.isShown else { return }
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    func update(commands: [SlashCommand]) {
        guard isVisible else { return }
        guard !commands.isEmpty else { return hide() }
        model.commands = commands
        model.selected = min(model.selected, commands.count - 1)
        popover?.contentSize = NSSize(width: 320, height: min(CGFloat(commands.count) * 38 + 12, 320))
    }

    func hide() {
        popover?.performClose(nil)
    }

    // MARK: Keyboard

    /// Returns true when the menu consumed the key, so the text view does not also
    /// act on it. Without this, the arrow keys move the caret behind the menu and
    /// Return inserts a newline as well as the command.
    func handle(_ selector: Selector) -> Bool {
        guard isVisible else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            model.selected = max(model.selected - 1, 0)
            return true
        case #selector(NSResponder.moveDown(_:)):
            model.selected = min(model.selected + 1, model.commands.count - 1)
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            if model.commands.indices.contains(model.selected) {
                let command = model.commands[model.selected]
                hide()
                onPick?(command)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    // MARK: Content

    @Observable
    final class Model {
        var commands: [SlashCommand] = []
        var selected = 0
        var onPick: ((SlashCommand) -> Void)?
    }

    private struct MenuView: View {
        @Bindable var model: Model

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.commands.enumerated()), id: \.element.id) { index, command in
                            Row(command: command, isSelected: index == model.selected)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { model.onPick?(command) }
                                // Hovering moves the selection, so the keyboard and
                                // the mouse never disagree about what Return will do.
                                .onHover { inside in if inside { model.selected = index } }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selected) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private struct Row: View {
        let command: SlashCommand
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.name)
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(command.detail)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : .clear)
            )
        }
    }
}
