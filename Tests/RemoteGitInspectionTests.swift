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
        XCTAssertTrue(snapshot.worktrees.isEmpty)
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
        XCTAssertTrue(snapshot.worktrees.isEmpty)
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
        XCTAssertTrue(snapshot.worktrees.isEmpty)
    }

    func testParseRemoteGitInspectionWithWorktrees() {
        let output = "__BRANCH__\nmain\n__HEAD__\nabc1234\n__WORKTREE__\nworktree /home/user/project\nHEAD abc1234567890abcdef1234567890abcdef12345678\nbranch refs/heads/main\n\nworktree /home/user/project/.worktrees/feature-branch\nHEAD def5678901234567890abcdef1234567890abcdef12\nbranch refs/heads/feature-branch\n\n__STATUS__\nM  file1.txt\n__AHEAD_BEHIND__\n1\t0"

        let snapshot = GitRepositoryService.parseRemoteInspection(output)

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.head, "abc1234")
        XCTAssertEqual(snapshot.changedFileCount, 1)
        XCTAssertEqual(snapshot.aheadCount, 1)
        XCTAssertEqual(snapshot.behindCount, 0)
        XCTAssertEqual(snapshot.worktrees.count, 2)

        let mainWorktree = snapshot.worktrees.first { $0.isMainWorktree }
        XCTAssertNotNil(mainWorktree)
        XCTAssertEqual(mainWorktree?.path, "/home/user/project")
        XCTAssertEqual(mainWorktree?.branch, "main")
        XCTAssertEqual(mainWorktree?.head, "abc1234567890abcdef1234567890abcdef12345678")

        let featureWorktree = snapshot.worktrees.first { !$0.isMainWorktree }
        XCTAssertNotNil(featureWorktree)
        XCTAssertEqual(featureWorktree?.path, "/home/user/project/.worktrees/feature-branch")
        XCTAssertEqual(featureWorktree?.branch, "feature-branch")
        XCTAssertEqual(featureWorktree?.head, "def5678901234567890abcdef1234567890abcdef12")
    }

    func testParseRemoteWorktreeStatuses() {
        let output = "__WT_PATH__\n/home/user/project\n__WT_STATUS__\nM  file1.txt\n__WT_AHEAD_BEHIND__\n1\t0\n__WT_PATH__\n/home/user/project-feature\n__WT_STATUS__\n__WT_AHEAD_BEHIND__\n0\t2"

        let statuses = GitRepositoryService.parseRemoteWorktreeStatuses(output)

        XCTAssertEqual(statuses.count, 2)
        XCTAssertEqual(statuses["/home/user/project"]?.changedFileCount, 1)
        XCTAssertEqual(statuses["/home/user/project"]?.aheadCount, 1)
        XCTAssertEqual(statuses["/home/user/project"]?.behindCount, 0)
        XCTAssertEqual(statuses["/home/user/project-feature"]?.changedFileCount, 0)
        XCTAssertEqual(statuses["/home/user/project-feature"]?.aheadCount, 0)
        XCTAssertEqual(statuses["/home/user/project-feature"]?.behindCount, 2)
    }

    func testParseRemoteWorktreeStatusesSingleWorktree() {
        let output = "__WT_PATH__\n/home/user/project\n__WT_STATUS__\n__WT_AHEAD_BEHIND__\n0\t0"

        let statuses = GitRepositoryService.parseRemoteWorktreeStatuses(output)

        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses["/home/user/project"]?.changedFileCount, 0)
    }

    func testParseRemoteWorktreeStatusesEmpty() {
        let statuses = GitRepositoryService.parseRemoteWorktreeStatuses("")
        XCTAssertTrue(statuses.isEmpty)
    }
}
