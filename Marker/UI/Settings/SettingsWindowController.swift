import AppKit
import SwiftUI
import MarkerRender

/// Settings, hosted from SwiftUI.
///
/// The previous version was a bare `NSStackView` with no constraints: the label
/// clipped, the segmented control overflowed the window, nothing was grouped. A
/// grouped `Form` is the system component for exactly this, and it brings correct
/// insets, control sizing, label alignment, section footers and Liquid Glass
/// without any of them being specified here.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isRestorable = false
        // Sized from what the form actually needs, so it can never clip again.
        window.setContentSize(hosting.view.fittingSize)
        window.contentMinSize = hosting.view.fittingSize
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Licence state, and a field to enter a key.
///
/// Shown as one row rather than a separate window, because there is very little to
/// say: what the state is, and where to type a key if it is not Pro.
private struct LicenseRow: View {

    @State private var state = MarkerApp.license.state
    @State private var entry = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(state.allowsEditing ? .primary : .secondary)
                Spacer()
                if case .pro = state {
                    Button("Remove") {
                        MarkerApp.license.deactivate()
                        state = MarkerApp.license.state
                    }
                }
            }

            if case .pro = state {} else {
                HStack {
                    // `prompt:` rather than the title argument: inside a Form, a
                    // TextField's title becomes a row label to the left of the field,
                    // which is not what placeholder text is for.
                    TextField("", text: $entry, prompt: Text("Paste your licence key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .onSubmit { activate() }
                    Button("Activate") { activate() }
                        .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem {
                    Text(problem)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
    }

    private var title: String {
        switch state {
        case .pro(let name): return "Licensed to \(name)"
        case .trial(let days): return "Trial, \(days) day\(days == 1 ? "" : "s") remaining"
        case .expired: return "Trial ended. Marker is a viewer"
        }
    }

    private var symbol: String {
        switch state {
        case .pro: return "checkmark.seal.fill"
        case .trial: return "clock"
        case .expired: return "lock"
        }
    }

    private func activate() {
        switch MarkerApp.license.activate(entry) {
        case .success:
            problem = nil
            entry = ""
            state = MarkerApp.license.state
        case .failure(let failure):
            // Distinguishing the two matters: one means retype it, the other means
            // the key is not real.
            problem = failure == .malformed
                ? "That does not look like a licence key. Check for a missing character."
                : "That key is not valid for this app."
        }
    }
}

private struct SettingsView: View {

    @State private var appearance = MarkerApp.appearance.appearance
    @AppStorage(Preferences.updateKey) private var checksForUpdates = true
    @AppStorage(Preferences.remoteImagesKey) private var loadsRemoteImages = true

    var body: some View {
        Form {
            Section {
                // Label hidden: the section header already says Appearance, and
                // repeating it in the row is the kind of thing that reads as
                // machine generated.
                Picker("Appearance", selection: $appearance) {
                    ForEach(MarkerTheme.Appearance.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Appearance")
            } footer: {
                Text("Liquid Glass makes the window translucent and follows your system setting. Dark and Light stay opaque.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                LicenseRow()
            } header: {
                Text("Marker Pro")
            }

            Section {
                Toggle("Check for updates", isOn: $checksForUpdates)
                Toggle("Load images linked from the web", isOn: $loadsRemoteImages)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Marker sends nothing about you or your files. Turning off remote images keeps a document from reaching the network at all.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: appearance) { _, new in
            MarkerApp.appearance.set(new)
        }
        .onReceive(NotificationCenter.default.publisher(for: .markerAppearanceDidChange)) { _ in
            // Keeps the picker honest when the theme is changed from the toolbar.
            appearance = MarkerApp.appearance.appearance
        }
    }
}

/// The two switches behind the product's privacy claim, in one place so a guard
/// test can point at them and the QA rows can flip them.
enum Preferences {
    static let updateKey = "MarkerUpdateCheckEnabled"
    static let remoteImagesKey = "MarkerRemoteImagesEnabled"

    static var updateCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: updateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: updateKey) }
    }

    static var remoteImagesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: remoteImagesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: remoteImagesKey) }
    }
}
