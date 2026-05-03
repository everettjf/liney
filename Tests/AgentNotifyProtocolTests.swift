//
//  AgentNotifyProtocolTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class AgentNotifyProtocolTests: XCTestCase {
    func testEncodeDecodeRoundTripPreservesAllFields() throws {
        let original = AgentNotifyRequest(
            title: "Build finished",
            body: "All tests pass",
            paneID: "abc-pane",
            workspaceID: "ws-1",
            agentName: "Claude"
        )
        let frame = try AgentNotifyProtocol.encode(original)
        XCTAssertEqual(frame.last, 0x0A, "frame must end with newline")

        let decoded = try AgentNotifyProtocol.decode(frame)
        XCTAssertEqual(decoded, original)
    }

    func testEncodeRejectsEmptyTitleAndBody() {
        let request = AgentNotifyRequest(title: "   ", body: "")
        XCTAssertThrowsError(try AgentNotifyProtocol.encode(request)) { error in
            XCTAssertEqual(error as? AgentNotifyError, .missingTitle)
        }
    }

    func testEncodeAcceptsBodyWhenTitleIsBlank() throws {
        let request = AgentNotifyRequest(title: "", body: "agent waiting")
        let frame = try AgentNotifyProtocol.encode(request)
        XCTAssertFalse(frame.isEmpty)
    }

    func testEncodeRejectsOversizedPayload() {
        let huge = String(repeating: "x", count: AgentNotifyProtocol.maxFrameBytes + 100)
        let request = AgentNotifyRequest(title: "x", body: huge)
        XCTAssertThrowsError(try AgentNotifyProtocol.encode(request)) { error in
            switch error as? AgentNotifyError {
            case .payloadTooLarge:
                break
            default:
                XCTFail("expected payloadTooLarge, got \(error)")
            }
        }
    }

    func testDecodeIgnoresUnknownFields() throws {
        // Forward compatibility: fields the server doesn't recognize must not
        // cause a hard failure, so newer CLI versions can talk to older apps.
        let json = #"{"v":1,"title":"Hello","body":"World","futureField":"x"}"#
        let data = Data(json.utf8)
        let decoded = try AgentNotifyProtocol.decode(data)
        XCTAssertEqual(decoded.title, "Hello")
        XCTAssertEqual(decoded.body, "World")
    }

    func testDecodeAcceptsTrailingNewline() throws {
        let json = #"{"v":1,"title":"Hello"}"# + "\n"
        let data = Data(json.utf8)
        let decoded = try AgentNotifyProtocol.decode(data)
        XCTAssertEqual(decoded.title, "Hello")
    }

    func testDecodeRejectsMalformedJSON() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try AgentNotifyProtocol.decode(data)) { error in
            switch error as? AgentNotifyError {
            case .decode:
                break
            default:
                XCTFail("expected decode error, got \(error)")
            }
        }
    }

    func testSocketPathStaysWithinSunPathLimit() {
        let url = AgentNotifySocketPath.resolveSocketURL(homeDirectory: "/Users/everettjf")
        XCTAssertLessThanOrEqual(url.path.utf8.count, 103, "socket path must fit sockaddr_un.sun_path on Darwin")
    }

    func testSocketPathDirectoryMatchesSocketURL() {
        let dir = AgentNotifySocketPath.resolveDirectory(homeDirectory: "/Users/eve")
        let url = AgentNotifySocketPath.resolveSocketURL(homeDirectory: "/Users/eve")
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(url.lastPathComponent, AgentNotifySocketPath.socketFileName)
    }
}
