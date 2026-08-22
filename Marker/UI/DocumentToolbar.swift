import AppKit
import MarkerRender

/// The document window's toolbar.
///
/// Everything here is a second route to something that already works from the
/// keyboard, which is the point: the shortcuts stay authoritative and the toolbar
/// makes them discoverable. Nothing in here owns state.
final class DocumentToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate {

    private enum ItemID {
        static let textSize = NSToolbarItem.Identifier("marker.textSize")
        static let theme = NSToolbarItem.Identifier("marker.theme")
        static let find = NSToolbarItem.Identifier("marker.find")
        static let edit = NSToolbarItem.Identifier("marker.edit")
    }

    private unowned let controller: DocumentViewController
    private var editItem: NSToolbarItem?

    init(controller: DocumentViewController) {
        self.controller = controller
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "marker.document")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    // MARK: Delegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Everything is right aligned: the document is the subject, the controls are
        // secondary, and a left-aligned control would compete with the title.
        // Left as four items. NSToolbarItemGroup was tried and rendered exactly the
        // same: on macOS 26 each item gets its own glass capsule regardless, and
        // sharing one background needs the items to collapse into a single
        // NSSegmentedControl, which would cost the theme menu its chevron. A group
        // that changes nothing is complexity with no result.
        [.flexibleSpace, ItemID.textSize, ItemID.theme, ItemID.find, ItemID.edit]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case ItemID.textSize: return textSizeItem()
        case ItemID.theme: return themeItem()
        case ItemID.find: return findItem()
        case ItemID.edit: return makeEditItem()
        default: return nil
        }
    }

    // MARK: Items

    private func textSizeItem() -> NSToolbarItem {
        let images = [
            symbol("textformat.size.smaller", "Smaller"),
            symbol("textformat.size.larger", "Larger"),
        ].compactMap { $0 }
        let segmented = NSSegmentedControl(
            images: images,
            trackingMode: .momentary,
            target: self,
            action: #selector(textSizeChanged(_:))
        )
        segmented.segmentDistribution = NSSegmentedControl.Distribution.fillEqually

        let item = NSToolbarItem(itemIdentifier: ItemID.textSize)
        item.view = segmented
        item.label = "Text Size"
        item.paletteLabel = "Text Size"
        item.toolTip = "Text size (⌘+ and ⌘-, ⌘0 to reset)"
        return item
    }

    private func themeItem() -> NSToolbarItem {
        let menu = NSMenu()
        // The delegate refreshes the checkmarks every time the menu opens. Setting
        // state once here is what left the tick sitting on Liquid Glass after
        // switching to Dark: the menu was built at launch and never revisited.
        menu.delegate = self
        for (index, appearance) in MarkerTheme.Appearance.allCases.enumerated() {
            let item = NSMenuItem(
                title: appearance.displayName,
                action: #selector(themeChanged(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            menu.addItem(item)
        }

        let item = NSMenuToolbarItem(itemIdentifier: ItemID.theme)
        item.menu = menu
        item.image = symbol("circle.lefthalf.filled", "Theme")
        item.label = "Theme"
        item.paletteLabel = "Theme"
        item.toolTip = "Liquid Glass, Dark or Light"
        item.showsIndicator = true
        return item
    }

    private func findItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ItemID.find)
        item.image = symbol("magnifyingglass", "Find")
        item.label = "Find"
        item.paletteLabel = "Find"
        item.toolTip = "Find in document (⌘F)"
        item.target = self
        item.action = #selector(findPressed)
        item.isBordered = true
        return item
    }

    private func makeEditItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ItemID.edit)
        item.label = "Edit"
        item.paletteLabel = "Edit"
        item.target = self
        item.action = #selector(editPressed)
        item.isBordered = true
        item.style = .prominent
        editItem = item
        syncEditItem()
        return item
    }

    /// Keeps the button's title, symbol and tooltip agreeing with the mode. Called
    /// whenever the mode changes, so the control can never claim the wrong state.
    func syncEditItem() {
        guard let editItem else { return }
        let editing = controller.editMode == .editing
        let state = MarkerApp.license.state

        editItem.title = editing ? "Done" : "Edit"
        editItem.image = symbol(
            editing ? "checkmark" : "square.and.pencil",
            editing ? "Done" : "Edit"
        )
        // A disabled button with no reason is the worst kind. The tooltip says what
        // happened and what to do about it, and the button stays enabled so pressing
        // it explains rather than doing nothing.
        if editing {
            editItem.toolTip = "Finish editing and render the document"
        } else {
            switch state {
            case .pro(let name): editItem.toolTip = "Edit the markdown source. Licensed to \(name)"
            case .trial(let days):
                editItem.toolTip = "Edit the markdown source. \(days) day\(days == 1 ? "" : "s") left in your trial"
            case .expired: editItem.toolTip = "Editing needs Marker Pro. Your trial has ended"
            }
        }
    }

    private func symbol(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = MarkerApp.appearance.appearance
        let choices = MarkerTheme.Appearance.allCases
        for item in menu.items where choices.indices.contains(item.tag) {
            item.state = choices[item.tag] == current ? .on : .off
        }
    }

    // MARK: Actions

    @objc private func textSizeChanged(_ sender: NSSegmentedControl) {
        sender.selectedSegment == 0 ? controller.zoomOut(sender) : controller.zoomIn(sender)
    }

    @objc private func themeChanged(_ sender: NSMenuItem) {
        let choices = MarkerTheme.Appearance.allCases
        guard choices.indices.contains(sender.tag) else { return }
        MarkerApp.appearance.set(choices[sender.tag])
    }

    @objc private func findPressed() {
        controller.showFindBar()
    }

    @objc private func editPressed() {
        controller.toggleEditMode()
        syncEditItem()
    }
}

extension MarkerTheme.Appearance {
    var displayName: String {
        switch self {
        case .glass: return "Liquid Glass"
        case .dark: return "Dark Mode"
        case .light: return "Light Mode"
        }
    }
}
