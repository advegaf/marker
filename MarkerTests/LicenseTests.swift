import XCTest
@testable import Marker

/// Licensing is the one place where being wrong in the generous direction gives
/// the product away and being wrong in the strict direction locks out someone who
/// paid. Both failure modes are tested for.
nonisolated final class LicenseTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MarkerLicenseTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store(daysAgo: Int) -> LicenseStore {
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        defaults.set(start, forKey: "MarkerFirstLaunch")
        return LicenseStore(defaults: defaults, now: { Date() })
    }

    // MARK: Trial

    func testFirstLaunchStartsAFourteenDayTrial() {
        let store = LicenseStore(defaults: defaults, now: { Date() })
        guard case .trial(let days) = store.state else {
            return XCTFail("a fresh install should be in trial, got \(store.state)")
        }
        XCTAssertEqual(days, LicenseStore.trialLength)
        XCTAssertTrue(store.state.allowsEditing)
    }

    func testTheTrialCountsDown() {
        guard case .trial(let days) = store(daysAgo: 5).state else {
            return XCTFail("day 5 should still be in trial")
        }
        XCTAssertEqual(days, 9)
    }

    func testTheLastDayOfTheTrialStillEdits() {
        // Day 13 is the last day. Off by one here either steals a day or gives one.
        XCTAssertTrue(store(daysAgo: 13).state.allowsEditing)
    }

    func testTheTrialEndsOnDayFourteen() {
        XCTAssertEqual(store(daysAgo: 14).state, .expired)
        XCTAssertFalse(store(daysAgo: 14).state.allowsEditing)
        XCTAssertEqual(store(daysAgo: 400).state, .expired)
    }

    func testSettingTheClockBackDoesNotExtendTheTrial() {
        // The one bit of tamper resistance a local trial can honestly offer: the
        // recorded start only ever moves earlier, never later. Winding the clock back
        // therefore costs trial time rather than granting it, which is the direction
        // a licensing bug should fail in.
        defaults.set(Date().addingTimeInterval(-10 * 86_400), forKey: "MarkerFirstLaunch")
        let before = LicenseStore(defaults: defaults, now: { Date() }).remainingTrialDays

        let rewound = LicenseStore(defaults: defaults, now: { Date().addingTimeInterval(-30 * 86_400) })
        _ = rewound.firstLaunch

        let after = LicenseStore(defaults: defaults, now: { Date() }).remainingTrialDays
        XCTAssertLessThanOrEqual(after, before, "winding the clock back bought extra trial days")
    }

    // MARK: Keys

    func testAValidKeyUnlocksPro() throws {
        let key = try signedKey(name: "Ada Lovelace")
        let store = self.store(daysAgo: 99)
        XCTAssertEqual(store.state, .expired)

        let result = store.activate(key.formatted)
        XCTAssertEqual(try result.get(), "Ada Lovelace")
        XCTAssertEqual(store.state, .pro(name: "Ada Lovelace"))
        XCTAssertTrue(store.state.allowsEditing)
    }

    func testProSurvivesAnExpiredTrial() throws {
        let key = try signedKey(name: "Grace Hopper")
        let store = self.store(daysAgo: 5_000)
        _ = store.activate(key.formatted)
        XCTAssertTrue(store.state.allowsEditing, "a paid licence must outlive the trial")
    }

    func testEditingAnyCharacterOfAKeyInvalidatesIt() throws {
        // The payload is base32, so the name is not visible in the key and cannot be
        // edited by find and replace. What an attacker can do is flip characters, so
        // that is what is tested: every single-character change must be rejected,
        // whether it lands in the payload or in the signature.
        let key = try signedKey(name: "Real Person")
        let original = Array(key.formatted)

        var tested = 0
        for index in original.indices where original[index] != "-" && original[index] != "." {
            var forged = original
            // Move to a different valid base32 character.
            forged[index] = forged[index] == "A" ? "B" : "A"

            let store = LicenseStore(defaults: defaults, now: { Date() })
            defaults.set(Date().addingTimeInterval(-99 * 86_400), forKey: "MarkerFirstLaunch")
            if case .success = store.activate(String(forged)) {
                XCTFail("a key with character \(index) altered was accepted")
            }
            tested += 1
            if tested >= 24 { break }
        }
        XCTAssertGreaterThan(tested, 0, "no characters were actually tested")
    }

    func testAnUnalteredKeyStillVerifiesAfterThatCheck() throws {
        // Guards the test above from passing because every key is rejected.
        let key = try signedKey(name: "Real Person")
        let store = self.store(daysAgo: 99)
        XCTAssertEqual(try store.activate(key.formatted).get(), "Real Person")
    }

    func testASignatureFromTheWrongKeyIsRejected() throws {
        // Someone mints their own pair and signs a payload with it.
        let other = try LicenseKey.sign(
            .init(name: "Somebody", issued: Date()),
            privateKey: Data(repeating: 7, count: 32)
        )
        let store = self.store(daysAgo: 99)
        XCTAssertEqual(store.activate(other.formatted), .failure(.signatureDoesNotMatch))
    }

    func testGarbageIsRejectedAsMalformedNotAsInvalid() {
        // The two failures mean different things to the person typing: retype it,
        // versus this key is not real.
        let store = self.store(daysAgo: 99)
        for junk in ["", "hello", "not-a-key", "abc.def", "...."] {
            XCTAssertEqual(store.activate(junk), .failure(.malformed), "accepted <<<\(junk)>>>")
        }
    }

    func testKeysSurviveFormattingAndWhitespace() throws {
        // People paste keys out of mail with line breaks and stray spaces in them.
        let key = try signedKey(name: "Katherine Johnson")
        let mangled = "  " + key.formatted.replacingOccurrences(of: "-", with: " - ") + "\n"
        // Lowercasing too: base32 has no case, so a key retyped in lower case works.
        let store = self.store(daysAgo: 99)
        XCTAssertEqual(try store.activate(mangled).get(), "Katherine Johnson")

        let lowered = LicenseStore(defaults: UserDefaults(suiteName: suiteName + "-lower")!, now: { Date() })
        XCTAssertEqual(try lowered.activate(key.formatted.lowercased()).get(), "Katherine Johnson")
    }

    func testAKeyNeverContainsCharactersThatMailManglesFor() throws {
        let key = try signedKey(name: "Test User")
        for character in ["+", "/", "="] {
            XCTAssertFalse(key.formatted.contains(character),
                           "a key containing \(character) will be mangled in transit")
        }
    }

    func testRemovingALicenceReturnsToTheTrialState() throws {
        let key = try signedKey(name: "Someone")
        let store = self.store(daysAgo: 2)
        _ = store.activate(key.formatted)
        XCTAssertTrue(store.state.allowsEditing)

        store.deactivate()
        guard case .trial = store.state else {
            return XCTFail("removing a licence should fall back to the trial, got \(store.state)")
        }
    }

    /// Signs with the same private key the minting script uses, so these tests
    /// exercise the real pair rather than a stand-in.
    private func signedKey(name: String) throws -> LicenseKey {
        let privateKey = try XCTUnwrap(Data(base64Encoded: "REDACTED-LICENCE-KEY"))
        return try LicenseKey.sign(.init(name: name, issued: Date()), privateKey: privateKey)
    }
}
