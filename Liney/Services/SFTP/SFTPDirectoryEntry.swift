//
//  SFTPDirectoryEntry.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

struct SFTPDirectoryEntry: Hashable, Comparable {
    let name: String
    let path: String

    static func < (lhs: SFTPDirectoryEntry, rhs: SFTPDirectoryEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
