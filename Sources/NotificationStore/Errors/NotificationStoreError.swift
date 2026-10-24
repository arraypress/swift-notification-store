//
//  NotificationStoreError.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong reading a Mac's notifications.
public enum NotificationStoreError: Error, Equatable, Sendable, LocalizedError {

    /// macOS refused to let this process read the store — what a missing
    /// Full Disk Access grant looks like. Carries the path.
    case needsFullDiskAccess(String)

    /// No store at the path. Carries it.
    case noStore(String)

    /// The store is there but could not be understood.
    case unreadable(String, reason: String)

    /// A sentence a person can act on.
    public var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess(let path):
            "Not allowed to read \(path) — macOS keeps notifications behind Full Disk Access"
        case .noStore(let path):
            "Nothing at \(path)"
        case .unreadable(let path, let reason):
            "Could not read \(path): \(reason)"
        }
    }
}
