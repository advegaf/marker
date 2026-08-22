import Foundation

/// What the app is allowed to do right now.
public nonisolated enum LicenseState: Equatable, Sendable {
    /// Inside the 14 day trial. Editing is available.
    case trial(daysRemaining: Int)
    /// The trial ended and no licence was entered. The app is a viewer.
    case expired
    /// A valid licence was entered.
    case pro(name: String)

    public var allowsEditing: Bool {
        switch self {
        case .trial, .pro: return true
        case .expired: return false
        }
    }
}

/// Owns the trial clock and the stored licence.
///
/// Everything here is local. There is no server to ask and no account to have, so
/// the only questions are when the app first ran and whether the stored key
/// verifies against the public key compiled into the binary.
/// Nonisolated for the same reason as `LicenseKey`: this reads a date and a string
/// out of `UserDefaults`, which is thread safe, and verifies a signature. None of
/// that belongs to the main actor.
public nonisolated final class LicenseStore {

    /// The public half of the signing key. The private half never ships.
    static let publicKey = Data(base64Encoded: "edgQUjKKdu+N7XOrZV8OsKVXyuevMhQiL/eLr57sA4s=")!

    public static let trialLength = 14

    private enum Keys {
        static let firstLaunch = "MarkerFirstLaunch"
        static let licenseKey = "MarkerLicenseKey"
    }

    private let defaults: UserDefaults
    private let now: () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    // MARK: State

    public var state: LicenseState {
        // Test-only overrides, read first so the QA harness can reach states that
        // otherwise need waiting two weeks or owning a private key.
        if let forced = Self.forcedState(now: now) { return forced }

        if let stored = defaults.string(forKey: Keys.licenseKey),
           let key = try? LicenseKey.verify(stored, publicKey: Self.publicKey) {
            return .pro(name: key.payload.name)
        }

        let remaining = Self.trialLength - daysSinceFirstLaunch
        return remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    /// Days left, floored at zero. Separate from `state` so a test can compare two
    /// numbers without unwrapping an enum.
    public var remainingTrialDays: Int {
        max(Self.trialLength - daysSinceFirstLaunch, 0)
    }

    public var daysSinceFirstLaunch: Int {
        if let override = ProcessInfo.processInfo.environment["MARKER_TRIAL_DAY"],
           let day = Int(override) {
            return day
        }
        let start = firstLaunch
        return Calendar.current.dateComponents([.day], from: start, to: now()).day ?? 0
    }

    /// Recorded once, the first time the app runs. Not moved backwards if the clock
    /// is set back, which is the one bit of tamper resistance a local trial can
    /// honestly offer.
    public var firstLaunch: Date {
        if let stored = defaults.object(forKey: Keys.firstLaunch) as? Date {
            let current = now()
            if current < stored {
                defaults.set(current, forKey: Keys.firstLaunch)
                return current
            }
            return stored
        }
        let current = now()
        defaults.set(current, forKey: Keys.firstLaunch)
        return current
    }

    // MARK: Licence entry

    @discardableResult
    public func activate(_ text: String) -> Result<String, LicenseKey.Failure> {
        do {
            let key = try LicenseKey.verify(text, publicKey: Self.publicKey)
            defaults.set(text, forKey: Keys.licenseKey)
            return .success(key.payload.name)
        } catch let failure as LicenseKey.Failure {
            return .failure(failure)
        } catch {
            return .failure(.malformed)
        }
    }

    public func deactivate() {
        defaults.removeObject(forKey: Keys.licenseKey)
    }

    // MARK: Overrides

    private static func forcedState(now: () -> Date) -> LicenseState? {
        guard let forced = ProcessInfo.processInfo.environment["MARKER_LICENSE"] else { return nil }
        switch forced {
        case "pro": return .pro(name: "QA")
        case "expired": return .expired
        case "trial", "free":
            let day = ProcessInfo.processInfo.environment["MARKER_TRIAL_DAY"].flatMap(Int.init) ?? 0
            return .trial(daysRemaining: max(trialLength - day, 1))
        default: return nil
        }
    }
}
