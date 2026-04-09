//
//  AppLogger.swift
//  Liney
//
//  Author: everettjf
//

import Foundation
import os

enum AppLogger {
    private static let subsystem = "com.xnuapp.liney"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let workspace = Logger(subsystem: subsystem, category: "workspace")
    static let git = Logger(subsystem: subsystem, category: "git")
    static let shell = Logger(subsystem: subsystem, category: "shell")
    static let sidebar = Logger(subsystem: subsystem, category: "sidebar")

    private(set) static var level: AppLogLevel = .off

    static func updateLevel(_ newLevel: AppLogLevel) {
        level = newLevel
    }

    static var isVerbose: Bool { level == .verbose }
    static var isEnabled: Bool { level != .off }
}
