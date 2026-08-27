//
//  LineyTheme.swift
//  Liney
//
//  Author: everettjf
//

import AppKit
import SwiftUI

enum LineyTheme {
    static let appBackground = Color(nsColor: NSColor(calibratedRed: 0.045, green: 0.05, blue: 0.062, alpha: 1))
    static let canvasBackground = Color(nsColor: NSColor(calibratedRed: 0.05, green: 0.055, blue: 0.069, alpha: 1))
    static let panelBackground = Color(nsColor: NSColor(calibratedRed: 0.067, green: 0.073, blue: 0.089, alpha: 1))
    static let panelRaised = Color(nsColor: NSColor(calibratedRed: 0.074, green: 0.081, blue: 0.099, alpha: 1))
    static let chromeBackground = Color(nsColor: NSColor(calibratedRed: 0.056, green: 0.062, blue: 0.076, alpha: 0.96))
    static let sidebarBackground = Color(nsColor: NSColor(calibratedRed: 0.058, green: 0.064, blue: 0.079, alpha: 1))
    static let sidebarSearchBackground = Color(nsColor: NSColor(calibratedRed: 0.078, green: 0.085, blue: 0.102, alpha: 1))
    static let paneBackground = Color(nsColor: NSColor(calibratedRed: 0.061, green: 0.068, blue: 0.083, alpha: 1))
    static let paneHeaderBackground = Color(nsColor: NSColor(calibratedRed: 0.072, green: 0.078, blue: 0.094, alpha: 1))
    static let backdropBlue = Color(nsColor: NSColor(calibratedRed: 0.11, green: 0.24, blue: 0.47, alpha: 0.18))
    static let backdropTeal = Color(nsColor: NSColor(calibratedRed: 0.11, green: 0.39, blue: 0.34, alpha: 0.14))
    static let border = Color.white.opacity(0.085)
    static let strongBorder = Color.white.opacity(0.16)
    static let accent = Color(nsColor: NSColor(calibratedRed: 0.25, green: 0.54, blue: 0.98, alpha: 1))
    static let accentMuted = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.27, blue: 0.42, alpha: 1))
    static let localAccent = Color(nsColor: NSColor(calibratedRed: 0.2, green: 0.72, blue: 0.63, alpha: 1))
    static let success = Color(nsColor: NSColor(calibratedRed: 0.31, green: 0.84, blue: 0.52, alpha: 1))
    static let warning = Color(nsColor: NSColor(calibratedRed: 0.94, green: 0.66, blue: 0.21, alpha: 1))
    static let danger = Color(nsColor: NSColor(calibratedRed: 0.92, green: 0.42, blue: 0.34, alpha: 1))
    static let mutedText = Color.white.opacity(0.58)
    static let secondaryText = Color.white.opacity(0.74)
    static let tertiaryText = Color.white.opacity(0.9)
    static let subtleFill = Color.white.opacity(0.05)
    static let subtleRaisedFill = Color.white.opacity(0.08)

    static let sidebarSelectionFill = NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.24, alpha: 1)
    static let sidebarSelectionStroke = NSColor(calibratedRed: 0.26, green: 0.45, blue: 0.78, alpha: 0.92)
    static let sidebarHoverFill = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    static let dividerColor = NSColor(calibratedWhite: 1, alpha: 0.08)
}

/// Shared geometry keeps dense developer-tool surfaces visually consistent.
/// Values are intentionally compact for macOS and should be preferred over
/// one-off padding, radius, and control-size literals in new UI.
enum LineyMetrics {
    static let controlRadius: CGFloat = 5
    static let panelRadius: CGFloat = 9
    static let paneRadius: CGFloat = 8
    static let compactControlHeight: CGFloat = 24
    static let toolbarControlHeight: CGFloat = 28
    static let paneHeaderHeight: CGFloat = 30
    static let hairline: CGFloat = 1

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
}

enum LineyTypography {
    static let micro = Font.system(size: 9, weight: .semibold)
    static let caption = Font.system(size: 10, weight: .medium)
    static let secondary = Font.system(size: 11, weight: .medium)
    static let body = Font.system(size: 12, weight: .medium)
    static let emphasizedBody = Font.system(size: 12, weight: .semibold)
    static let title = Font.system(size: 16, weight: .bold)
    static let monospacedCaption = Font.system(size: 10, weight: .semibold, design: .monospaced)
}
