//
//  NotificationStore.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  usernoted's store (db2/db — the live one on macOS 27: usernoted holds it
//  open) read from a private copy, through swift-sqlite-reader's snapshot. It holds what is still unhandled, not a
//  history. MEASURED with a person on macOS 27.0.1: a notification's row
//  appears within seconds of delivery; clearing it deletes the row; reading
//  the chat in Messages makes Messages withdraw its notification (row gone,
//  badge 0); untouched rows stay for days.
//

import Foundation
import SQLiteReader

/// A Mac's unhandled notifications, read-only.
public struct NotificationStore: Sendable {

    public let locations: NotificationLocations

    public init(locations: NotificationLocations = NotificationLocations()) {
        self.locations = locations
    }

    /// Every notification macOS holds, newest first.
    public func notifications() throws(NotificationStoreError) -> [StoredNotification] {
        let database = try open()
        guard !database.columns(of: "record").isEmpty else {
            throw .unreadable(locations.database.path, reason: "no record table")
        }
        var delivered: Set<String> = []
        if !database.columns(of: "delivered").isEmpty {
            do {
                try database.query("SELECT list FROM delivered") { row in
                    if let list = row[0].data { delivered.formUnion(NotificationDecoding.uuids(list)) }
                }
            } catch { throw NotificationStoreError(error) }
        }
        var notifications: [StoredNotification] = []
        do {
            try database.query("SELECT data, uuid, delivered_date FROM record ORDER BY delivered_date DESC") { row in
                guard let data = row[0].data,
                      let notification = NotificationDecoding.notification(data, uuid: row[1].data, deliveredDate: row[2].double, delivered: delivered)
                else { return }
                notifications.append(notification)
            }
        } catch { throw NotificationStoreError(error) }
        return notifications
    }

    /// Every app that has asked to notify, with its badge and how many it holds.
    public func apps() throws(NotificationStoreError) -> [NotifyingApp] {
        let database = try open()
        var apps: [NotifyingApp] = []
        do {
            try database.query("""
                SELECT a.identifier, a.badge, COUNT(r.rec_id) FROM app a LEFT JOIN record r ON r.app_id = a.app_id
                GROUP BY a.app_id ORDER BY COUNT(r.rec_id) DESC, a.identifier
                """) { row in
                guard let identifier = row[0].nonEmptyString else { return }
                apps.append(NotifyingApp(identifier: identifier, badge: row[1].int, held: row[2].int ?? 0))
            }
        } catch { throw NotificationStoreError(error) }
        return apps
    }

    /// A private copy of the store and its log, deleted when the reader goes:
    /// usernoted holds the live store open and writes it through its log, so
    /// it is never opened in place.
    private func open() throws(NotificationStoreError) -> SQLiteReader {
        do { return try SQLiteReader(path: locations.database, opening: .snapshot) } catch { throw NotificationStoreError(error) }
    }
}
