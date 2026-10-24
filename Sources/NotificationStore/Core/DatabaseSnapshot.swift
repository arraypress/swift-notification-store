//
//  DatabaseSnapshot.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  The store is live: usernoted holds it open and writes it through a
//  write-ahead log, adding and deleting rows as notifications arrive and are
//  cleared. Rather than open it at all, the database and its -wal/-shm are
//  copied into a private temporary folder, read there, and the folder is
//  deleted.
//

import Foundation

/// A private copy of a SQLite database and its log.
final class DatabaseSnapshot {

    /// The copied database.
    let database: SQLiteDatabase

    private let folder: URL

    /// Copies the database at `source` and opens the copy.
    init(of source: URL) throws(NotificationStoreError) {
        let fileManager = FileManager.default
        switch PermissionCheck.access(source.path) {
        case .readable: break
        case .missing: throw .noStore(source.path)
        case .refused: throw .needsFullDiskAccess(source.path)
        }
        folder = fileManager.temporaryDirectory.appendingPathComponent("notification-store-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: source.path + suffix)
                guard suffix.isEmpty || fileManager.fileExists(atPath: from.path) else { continue }
                try fileManager.copyItem(at: from, to: folder.appendingPathComponent(source.lastPathComponent + suffix))
            }
        } catch {
            try? fileManager.removeItem(at: folder)
            if PermissionCheck.isRefusal(error) { throw .needsFullDiskAccess(source.path) }
            throw .unreadable(source.path, reason: error.localizedDescription)
        }
        do {
            database = try SQLiteDatabase(path: folder.appendingPathComponent(source.lastPathComponent).path)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: folder) }
}
