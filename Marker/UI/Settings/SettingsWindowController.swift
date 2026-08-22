import AppKit
import MarkerRender

/// Settings. Small on purpose: an appearance picker, the two network switches the
/// privacy claim rests on, and nothing else until a feature needs a knob.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        super.init(window: window)
        window.contentViewController = SettingsViewController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }
}

final class SettingsViewController: NSViewController {

    private let appearancePicker = NSSegmentedControl(
        labels: ["Liquid Glass", "Dark", "Light"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let updateCheckToggle = NSButton(checkboxWithTitle: "Check for updates", target: nil, action: nil)
    private let remoteImagesToggle = NSButton(checkboxWithTitle: "Load images linked from the web", target: nil, action: nil)

    override func loadView() {
        let stack = NSStackView(views: [
            labelled("Appearance", appearancePicker),
            updateCheckToggle,
            remoteImagesToggle,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        view = stack

        appearancePicker.target = self
        appearancePicker.action = #selector(appearanceChanged)
        appearancePicker.selectedSegment = MarkerTheme.Appearance.allCases
            .firstIndex(of: MarkerApp.appearance.appearance) ?? 0

        updateCheckToggle.target = self
        updateCheckToggle.action = #selector(updateCheckChanged)
        updateCheckToggle.state = Preferences.updateCheckEnabled ? .on : .off

        remoteImagesToggle.target = self
        remoteImagesToggle.action = #selector(remoteImagesChanged)
        remoteImagesToggle.state = Preferences.remoteImagesEnabled ? .on : .off
    }

    private func labelled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    @objc private func appearanceChanged() {
        let choices = MarkerTheme.Appearance.allCases
        guard choices.indices.contains(appearancePicker.selectedSegment) else { return }
        MarkerApp.appearance.set(choices[appearancePicker.selectedSegment])
    }

    @objc private func updateCheckChanged() {
        Preferences.updateCheckEnabled = updateCheckToggle.state == .on
    }

    @objc private func remoteImagesChanged() {
        Preferences.remoteImagesEnabled = remoteImagesToggle.state == .on
    }
}

/// The two switches behind the product's privacy claim, in one place so a guard
/// test can point at them and the QA rows can flip them.
enum Preferences {
    private static let updateKey = "MarkerUpdateCheckEnabled"
    private static let remoteImagesKey = "MarkerRemoteImagesEnabled"

    static var updateCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: updateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: updateKey) }
    }

    static var remoteImagesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: remoteImagesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: remoteImagesKey) }
    }
}
