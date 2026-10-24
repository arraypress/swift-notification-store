//
//  StoredNotification.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One notification macOS still holds — every field the record carries,
/// decoded, except the app's private payload.
///
/// A notification stays only until it is handled: clearing it deletes it,
/// and messaging apps withdraw their own once the chat is read (measured).
public struct StoredNotification: Codable, Sendable, Hashable, Identifiable {

    /// The record's id (a UUID string).
    public var id: String

    /// The posting app's bundle identifier, as the app wrote it.
    public var app: String

    /// Who it is from, by that app.
    public var sender: SenderKind

    /// When it was delivered.
    public var date: Date

    /// Title, subtitle and text — what someone (or something) wrote.
    public var title: String?
    public var subtitle: String?
    public var body: String?

    /// The app's category (`com.apple.messages.IncomingMessageCategory.Madrid`)
    /// and conversation thread, when it gives them.
    public var category: String?
    public var thread: String?

    /// The app's own identifier for it.
    public var requestID: String?

    /// Where it may appear.
    public var destinations: [NotificationDestination]

    /// Whether macOS lists it as delivered to Notification Center right now.
    public var delivered: Bool

    /// The raw codes whose meanings are not published.
    public var styleCode: Int?
    public var originCode: Int?

    /// How it was answered, if it was: an action index and whether it was in the foreground.
    public var responseAction: Int?

    public init(
        id: String, app: String, sender: SenderKind, date: Date, title: String? = nil, subtitle: String? = nil,
        body: String? = nil, category: String? = nil, thread: String? = nil, requestID: String? = nil,
        destinations: [NotificationDestination] = [], delivered: Bool = true, styleCode: Int? = nil,
        originCode: Int? = nil, responseAction: Int? = nil
    ) {
        self.id = id
        self.app = app
        self.sender = sender
        self.date = date
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.category = category
        self.thread = thread
        self.requestID = requestID
        self.destinations = destinations
        self.delivered = delivered
        self.styleCode = styleCode
        self.originCode = originCode
        self.responseAction = responseAction
    }
}

/// An app that can notify, and its badge.
public struct NotifyingApp: Codable, Sendable, Hashable {

    /// The bundle identifier, as macOS stores it (lower case).
    public var identifier: String

    /// The number on its icon, if it shows one.
    public var badge: Int?

    /// How many notifications macOS still holds from it.
    public var held: Int

    public init(identifier: String, badge: Int?, held: Int) {
        self.identifier = identifier
        self.badge = badge
        self.held = held
    }
}

/// Where a home folder keeps the store — a real home, or a fixture one.
public struct NotificationLocations: Sendable, Hashable {

    public var database: URL

    public init(database: URL) {
        self.database = database
    }

    /// usernoted's store under `home`, where macOS 26 and 27 keep it.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(database: home.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db"))
    }
}
