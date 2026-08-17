//
//  LineyURLSchemeTests.swift
//  LineyTests
//

import XCTest
@testable import Liney

final class LineyURLSchemeTests: XCTestCase {
    private final class MemoryTokenStore: URLSchemeTokenStoring {
        var token: String?
        var allowsSave = true

        func load() -> String? { token }
        func save(_ token: String) -> Bool {
            guard allowsSave else { return false }
            self.token = token
            return true
        }
        func delete() { token = nil }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LineyURLSchemeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLegacyTokenMigratesFromDefaultsToSecretStore() {
        let store = MemoryTokenStore()
        defaults.set(" legacy-token ", forKey: LineyURLScheme.tokenDefaultsKey)

        XCTAssertEqual(LineyURLScheme.storedToken(tokenStore: store, defaults: defaults), "legacy-token")
        XCTAssertEqual(store.token, "legacy-token")
        XCTAssertNil(defaults.string(forKey: LineyURLScheme.tokenDefaultsKey))
    }

    func testFailedMigrationKeepsLegacyTokenForRetry() {
        let store = MemoryTokenStore()
        store.allowsSave = false
        defaults.set("legacy-token", forKey: LineyURLScheme.tokenDefaultsKey)

        XCTAssertEqual(LineyURLScheme.storedToken(tokenStore: store, defaults: defaults), "legacy-token")
        XCTAssertEqual(defaults.string(forKey: LineyURLScheme.tokenDefaultsKey), "legacy-token")
    }

    func testSetAndClearTokenUsesSecretStoreAndRemovesPlaintextDefault() {
        let store = MemoryTokenStore()
        defaults.set("old-plaintext", forKey: LineyURLScheme.tokenDefaultsKey)

        XCTAssertTrue(LineyURLScheme.setStoredToken(" new-token ", tokenStore: store, defaults: defaults))
        XCTAssertEqual(store.token, "new-token")
        XCTAssertNil(defaults.string(forKey: LineyURLScheme.tokenDefaultsKey))

        XCTAssertTrue(LineyURLScheme.setStoredToken(nil, tokenStore: store, defaults: defaults))
        XCTAssertNil(store.token)
    }

    func testMalformedURLNeverProducesRunRequest() {
        XCTAssertNil(LineyURLScheme.parseRunURL(URL(string: "liney://run?cmd=echo&token=secret")!))
        XCTAssertNil(LineyURLScheme.parseRunURL(URL(string: "liney://other?cmd=echo&cwd=/tmp&token=secret")!))
    }
}
