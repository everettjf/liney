import XCTest
@testable import Liney

final class RemoteSessionCoordinatorTests: XCTestCase {
    func testRemoteRepositoryBrowserCommandUsesRemoteWorkingDirectoryAndInteractiveShell() {
        let target = RemoteWorkspaceTarget(
            id: UUID(),
            name: "prod",
            ssh: SSHSessionConfiguration(
                host: "prod.example.com",
                user: "deploy",
                port: 2222,
                identityFilePath: nil,
                remoteWorkingDirectory: "/srv/app",
                remoteCommand: nil
            ),
            agentPresetID: nil
        )

        let command = RemoteSessionCoordinator.remoteRepositoryBrowserCommand(for: target)

        XCTAssertEqual(
            command,
            "cd '/srv/app' && pwd && printf '\\n' && ls -la && printf '\\n' && git status --short --branch || true && printf '\\n' && exec ${SHELL:-/bin/zsh} -l"
        )
    }
}
