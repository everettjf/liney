//
//  CurrentUserLoginShell.swift
//  Liney
//
//  Author: Codex
//

import Darwin
import Foundation

enum CurrentUserLoginShell {
    static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let entry = getpwuid(getuid()) {
            let shellPath = String(cString: entry.pointee.pw_shell)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !shellPath.isEmpty {
                return shellPath
            }
        }

        if let shellPath = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shellPath.isEmpty {
            return shellPath
        }

        return nil
    }
}
