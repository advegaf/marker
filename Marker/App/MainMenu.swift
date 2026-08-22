import AppKit

/// The menu bar, built in code rather than from a nib.
///
/// Most of these are AppKit's own first-responder actions, which is the point:
/// find, zoom, undo and the document commands route to NSTextView and NSDocument
/// without any glue of ours.
enum MainMenu {

    static func install() {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem())
        main.addItem(viewMenuItem())
        main.addItem(windowMenuItem(applicationMenu: main))
        NSApp.mainMenu = main
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(item("About Marker", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings...", #selector(MarkerApp.showSettings(_:)), ","))
        menu.addItem(.separator())
        menu.addItem(item("Hide Marker", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                          modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Marker", #selector(NSApplication.terminate(_:)), "q"))

        let root = NSMenuItem()
        root.submenu = menu
        return root
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open...", #selector(NSDocumentController.openDocument(_:)), "o"))

        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        // AppKit populates this by name; the title is load bearing.
        recentMenu.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        recent.submenu = recentMenu
        menu.addItem(recent)

        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))

        let root = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        // Tags are NSTextFinder.Action values; NSTextView reads them off the sender.
        findMenu.addItem(item("Find...", #selector(NSTextView.performTextFinderAction(_:)), "f",
                              tag: NSTextFinder.Action.showFindInterface.rawValue))
        findMenu.addItem(item("Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g",
                              tag: NSTextFinder.Action.nextMatch.rawValue))
        findMenu.addItem(item("Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g",
                              modifiers: [.command, .shift],
                              tag: NSTextFinder.Action.previousMatch.rawValue))
        findMenu.addItem(item("Use Selection for Find", #selector(NSTextView.performTextFinderAction(_:)), "e",
                              tag: NSTextFinder.Action.setSearchString.rawValue))
        find.submenu = findMenu
        menu.addItem(find)

        let root = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Actual Size", #selector(DocumentViewController.resetZoom(_:)), "0"))
        menu.addItem(item("Zoom In", #selector(DocumentViewController.zoomIn(_:)), "+"))
        menu.addItem(item("Zoom Out", #selector(DocumentViewController.zoomOut(_:)), "-"))
        menu.addItem(.separator())
        menu.addItem(item("Liquid Glass", #selector(MarkerApp.selectAppearance(_:)), "1",
                          modifiers: [.command, .control], tag: 0))
        menu.addItem(item("Dark Mode", #selector(MarkerApp.selectAppearance(_:)), "2",
                          modifiers: [.command, .control], tag: 1))
        menu.addItem(item("Light Mode", #selector(MarkerApp.selectAppearance(_:)), "3",
                          modifiers: [.command, .control], tag: 2))

        let root = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    private static func windowMenuItem(applicationMenu: NSMenu) -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))

        let root = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        root.submenu = menu
        NSApp.windowsMenu = menu
        return root
    }
}
