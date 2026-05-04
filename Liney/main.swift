//
//  main.swift
//  Liney
//
//  Author: everettjf
//

import Cocoa

// CLI dispatch: when invoked as `Liney <subcommand> ...` (or via a `liney`
// shim that execs the app binary), behave as a short-lived CLI client
// instead of starting the AppKit event loop. Anything else falls through
// to NSApplicationMain so Finder-launches and `open -a Liney` are
// unaffected.
let cliArguments = Array(CommandLine.arguments.dropFirst())
if let firstArgument = cliArguments.first {
    let rest = Array(cliArguments.dropFirst())
    switch firstArgument {
    case "notify":
        exit(AgentNotifyCLI.run(arguments: rest).rawValue)
    case "open":
        exit(LineyControlCLI.runOpen(arguments: rest).rawValue)
    case "split":
        exit(LineyControlCLI.runSplit(arguments: rest).rawValue)
    case "send-keys":
        exit(LineyControlCLI.runSendKeys(arguments: rest).rawValue)
    case "session":
        // `liney session list ...` — second token routes to the subcommand.
        let session = Array(rest.dropFirst())
        switch rest.first {
        case "list":
            exit(LineyControlCLI.runSessionList(arguments: session).rawValue)
        default:
            FileHandle.standardError.write(Data("liney session: unknown subcommand (try `list`)\n".utf8))
            exit(64)
        }
    default:
        break
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated {
    app.delegate = delegate
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
