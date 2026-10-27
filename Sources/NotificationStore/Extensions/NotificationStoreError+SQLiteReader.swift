//
//  NotificationStoreError+SQLiteReader.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  The store is read through swift-sqlite-reader; its errors are reported
//  as this library's own, so callers and messages stay the same.
//

import Foundation
import SQLiteReader

extension NotificationStoreError {

    /// This library's error for a reader's.
    init(_ error: SQLiteReaderError) {
        switch error {
        case .notFound(let path): self = .noStore(path)
        case .permissionDenied(let path): self = .needsFullDiskAccess(path)
        case .unreadable(let path, let reason): self = .unreadable(path, reason: reason)
        }
    }
}
