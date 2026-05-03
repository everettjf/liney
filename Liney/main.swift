//
//  main.swift
//  Liney
//
//  Author: everettjf
//

import Cocoa

// CLI dispatch: when invoked as `Liney notify ...` (or via a `liney`
// shim that execs the app binary), behave as a short-lived CLI client
// instead of starting the AppKit event loop. Anything else falls through
// to NSApplicationMain so Finder-launches and `open -a Liney` are
// unaffected.
let cliArguments = Array(CommandLine.arguments.dropFirst())
if let firstArgument = cliArguments.first {
    switch firstArgument {
    case "notify":
        let exitCode = AgentNotifyCLI.run(arguments: Array(cliArguments.dropFirst()))
        exit(exitCode.rawValue)
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
