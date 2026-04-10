//
//  RemoteGitInspectionTests.swift
//  LineyTests
//
//  Author: everettjf
//

import XCTest
@testable import Liney

final class RemoteGitInspectionTests: XCTestCase {
    func testParseRemoteGitInspectionOutput() {
        let output = """
        __BRANCH__
        main
        __HEAD__
        abc1234
        __STATUS__
        M  file1.txt
        ?? file2.txt
        __AHEAD_BEHIND__
        2\t1
        """

        let snapshot = GitRepositoryService.parseRemoteInspection(output)

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.head, "abc1234")
        XCTAssertEqual(snapshot.changedFileCount, 2)
        XCTAssertEqual(snapshot.aheadCount, 2)
        XCTAssertEqual(snapshot.behindCount, 1)
    }

    func testParseRemoteGitInspectionEmptyStatus() {
        let output = """
        __BRANCH__
        develop
        __HEAD__
        ff00112
        __STATUS__
        __AHEAD_BEHIND__
        0\t0
        """

        let snapshot = GitRepositoryService.parseRemoteInspection(output)

        XCTAssertEqual(snapshot.branch, "develop")
        XCTAssertEqual(snapshot.head, "ff00112")
        XCTAssertEqual(snapshot.changedFileCount, 0)
        XCTAssertEqual(snapshot.aheadCount, 0)
        XCTAssertEqual(snapshot.behindCount, 0)
    }

    func testParseRemoteGitInspectionNoUpstream() {
        let output = """
        __BRANCH__
        feature/test
        __HEAD__
        deadbeef
        __STATUS__
        A  newfile.swift
        __AHEAD_BEHIND__
        """

        let snapshot = GitRepositoryService.parseRemoteInspection(output)

        XCTAssertEqual(snapshot.branch, "feature/test")
        XCTAssertEqual(snapshot.head, "deadbeef")
        XCTAssertEqual(snapshot.changedFileCount, 1)
        XCTAssertEqual(snapshot.aheadCount, 0)
        XCTAssertEqual(snapshot.behindCount, 0)
    }
}
