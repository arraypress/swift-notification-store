//
//  NotificationDestination.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//

/// Where a notification may appear — the `dest` bits, named as Apple's own
/// `UNNotificationDestinationStrings()` names them (measured, macOS 27.0.1).
public enum NotificationDestination: String, Codable, Sendable, CaseIterable {

    /// The banner or alert when it arrives (bit 1).
    case alert

    /// The Lock Screen (bit 2).
    case lockScreen

    /// Notification Center (bit 4).
    case notificationCenter

    /// CarPlay (bit 8).
    case carPlay
}
