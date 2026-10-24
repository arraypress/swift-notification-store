//
//  SenderKind.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//

/// Who a notification is from, by the app that posted it.
public enum SenderKind: String, Codable, Sendable, CaseIterable {

    /// A messaging, mail or calling app: a person wrote or called.
    case person

    /// Any other app.
    case app

    /// macOS itself (`_system_center_:` senders and Apple's background services).
    case system
}
