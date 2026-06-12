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

/// Result of listing a remote directory: the absolute directory the listing
/// actually ran in, plus its entries. A relative input path (e.g. `.` before
/// the remote shell has reported a cwd) is resolved on the remote host, so
/// `path` is always absolute and entry paths are rooted on it.
struct SFTPDirectoryListing: Hashable {
    let path: String
    let entries: [SFTPFileEntry]
}
