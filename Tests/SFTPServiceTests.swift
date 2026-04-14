import XCTest
@testable import Liney

final class SFTPServiceTests: XCTestCase {

    // MARK: - SFTPDirectoryEntry Sorting

    func testDirectoryEntrySortingAlphabetical() {
        let entries = [
            SFTPDirectoryEntry(name: "zebra", path: "/zebra"),
            SFTPDirectoryEntry(name: "alpha", path: "/alpha"),
            SFTPDirectoryEntry(name: "middle", path: "/middle"),
        ]
        let sorted = entries.sorted()
        XCTAssertEqual(sorted.map(\.name), ["alpha", "middle", "zebra"])
    }

    func testDirectoryEntrySortingCaseInsensitive() {
        let entries = [
            SFTPDirectoryEntry(name: "Banana", path: "/Banana"),
            SFTPDirectoryEntry(name: "apple", path: "/apple"),
            SFTPDirectoryEntry(name: "Cherry", path: "/Cherry"),
        ]
        let sorted = entries.sorted()
        XCTAssertEqual(sorted.map(\.name), ["apple", "Banana", "Cherry"])
    }

    func testDirectoryEntrySortingNumericAware() {
        let entries = [
            SFTPDirectoryEntry(name: "file10", path: "/file10"),
            SFTPDirectoryEntry(name: "file2", path: "/file2"),
            SFTPDirectoryEntry(name: "file1", path: "/file1"),
        ]
        let sorted = entries.sorted()
        XCTAssertEqual(sorted.map(\.name), ["file1", "file2", "file10"])
    }

    func testDirectoryEntryEquality() {
        let a = SFTPDirectoryEntry(name: "docs", path: "/home/docs")
        let b = SFTPDirectoryEntry(name: "docs", path: "/home/docs")
        XCTAssertEqual(a, b)
    }

    func testDirectoryEntryHashable() {
        let a = SFTPDirectoryEntry(name: "docs", path: "/home/docs")
        let b = SFTPDirectoryEntry(name: "src", path: "/home/src")
        let set: Set<SFTPDirectoryEntry> = [a, b, a]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - SFTPServiceError Descriptions

    func testNotConnectedErrorDescription() {
        let error = SFTPServiceError.notConnected
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testAuthenticationFailedErrorDescription() {
        let error = SFTPServiceError.authenticationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testKeyFileNotFoundErrorDescription() {
        let error = SFTPServiceError.keyFileNotFound("/home/.ssh/id_rsa")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("id_rsa"))
    }

    func testCommandFailedErrorDescription() {
        let error = SFTPServiceError.commandFailed("permission denied")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("permission denied"))
    }

    // MARK: - SFTPServiceError Equatable

    func testErrorEquatableNotConnected() {
        XCTAssertEqual(SFTPServiceError.notConnected, SFTPServiceError.notConnected)
    }

    func testErrorEquatableAuthenticationFailed() {
        XCTAssertEqual(SFTPServiceError.authenticationFailed, SFTPServiceError.authenticationFailed)
    }

    func testErrorEquatableKeyFileNotFound() {
        XCTAssertEqual(
            SFTPServiceError.keyFileNotFound("/path/a"),
            SFTPServiceError.keyFileNotFound("/path/a")
        )
        XCTAssertNotEqual(
            SFTPServiceError.keyFileNotFound("/path/a"),
            SFTPServiceError.keyFileNotFound("/path/b")
        )
    }

    func testErrorEquatableCommandFailed() {
        XCTAssertEqual(
            SFTPServiceError.commandFailed("err"),
            SFTPServiceError.commandFailed("err")
        )
        XCTAssertNotEqual(
            SFTPServiceError.commandFailed("err"),
            SFTPServiceError.commandFailed("other")
        )
    }

    func testErrorNotEqualAcrossCases() {
        XCTAssertNotEqual(SFTPServiceError.notConnected, SFTPServiceError.authenticationFailed)
    }

    // MARK: - SFTPService Disconnect

    func testDisconnectResetsState() async {
        let service = SFTPService()
        // After disconnect, listing should throw notConnected
        await service.disconnect()
        do {
            _ = try await service.listDirectories(at: "/tmp")
            XCTFail("Expected notConnected error")
        } catch let error as SFTPServiceError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testHomeDirectoryWithoutConnectionThrows() async {
        let service = SFTPService()
        do {
            _ = try await service.homeDirectory()
            XCTFail("Expected notConnected error")
        } catch let error as SFTPServiceError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testConnectWithMissingKeyFileThrows() async {
        let target = SSHSessionConfiguration(
            host: "example.com",
            user: "testuser",
            port: nil,
            identityFilePath: "/nonexistent/path/id_rsa",
            remoteWorkingDirectory: nil,
            remoteCommand: nil
        )
        let service = SFTPService()
        do {
            try await service.connect(target: target)
            XCTFail("Expected keyFileNotFound error")
        } catch let error as SFTPServiceError {
            XCTAssertEqual(error, .keyFileNotFound("/nonexistent/path/id_rsa"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
