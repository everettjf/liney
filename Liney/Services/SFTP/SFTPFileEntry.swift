//
//  SFTPFileEntry.swift
//  Liney
//
//  Author: everettjf
//

import Foundation

/// A single entry (file or directory) listed on a remote host over SSH.
///
/// Unlike `SFTPDirectoryEntry`, which is directory-only, this carries an
/// `isDirectory` flag so the file tree can render files and folders alike.
struct SFTPFileEntry: Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
}
