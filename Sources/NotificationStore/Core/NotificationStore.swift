//
//  NotificationStore.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  usernoted's store (db2/db — the live one on macOS 27: usernoted holds it
//  open) read from a private copy. It holds what is still unhandled, not a
//  history. MEASURED with a person on macOS 27.0.1: a notification's row
//  appears within seconds of delivery; clearing it deletes the row; reading
//  the chat in Messages makes Messages withdraw its notification (row gone,
//  badge 0); untouched rows stay for days.
//

import Foundation

/// A Mac's unhandled notifications, read-only.
public struct NotificationStore: Sendable {

    public let locations: NotificationLocations

    public init(locations: NotificationLocations = NotificationLocations()) {
        self.locations = locations
    }

    /// Every notification macOS holds, newest first.
    public func notifications() throws(NotificationStoreError) -> [StoredNotification] {
        let snapshot = try DatabaseSnapshot(of: locations.database)
        let database = snapshot.database
        guard !database.columns(of: "record").isEmpty else {
            throw .unreadable(locations.database.path, reason: "no record table")
        }
        var delivered: Set<String> = []
        if !database.columns(of: "delivered").isEmpty {
            try database.query("SELECT list FROM delivered") { row in
                if let list = row.blob(0) { delivered.formUnion(NotificationDecoding.uuids(list)) }
            }
        }
        var notifications: [StoredNotification] = []
        try database.query("SELECT data, uuid, delivered_date FROM record ORDER BY delivered_date DESC") { row in
            guard let data = row.blob(0),
                  let notification = NotificationDecoding.notification(data, uuid: row.blob(1), deliveredDate: row.double(2), delivered: delivered)
            else { return }
            notifications.append(notification)
        }
        return notifications
    }

    /// Every app that has asked to notify, with its badge and how many it holds.
    public func apps() throws(NotificationStoreError) -> [NotifyingApp] {
        let snapshot = try DatabaseSnapshot(of: locations.database)
        var apps: [NotifyingApp] = []
        try snapshot.database.query("""
            SELECT a.identifier, a.badge, COUNT(r.rec_id) FROM app a LEFT JOIN record r ON r.app_id = a.app_id
            GROUP BY a.app_id ORDER BY COUNT(r.rec_id) DESC, a.identifier
            """) { row in
            guard let identifier = row.text(0) else { return }
            apps.append(NotifyingApp(identifier: identifier, badge: row.integer(1), held: row.integer(2) ?? 0))
        }
        return apps
    }
}
