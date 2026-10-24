//
//  NotificationQueries.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  Narrowing, searching and counting notifications. Pure.
//

import Foundation

/// Conditions on notifications.
public struct NotificationFilter: Sendable {
    public var since: Date?
    public var senders: Set<SenderKind>?
    /// Bundle identifiers (any case) to keep, or to leave out.
    public var apps: Set<String>?
    public var excludedApps: Set<String>
    /// Words that must start a word in the title, subtitle or text (ignoring case and accents).
    public var search: String?

    public init(since: Date? = nil, senders: Set<SenderKind>? = nil, apps: Set<String>? = nil,
                excludedApps: Set<String> = [], search: String? = nil) {
        self.since = since
        self.senders = senders
        self.apps = apps
        self.excludedApps = excludedApps
        self.search = search
    }

    public func apply(_ notifications: [StoredNotification]) -> [StoredNotification] {
        let keep = apps.map { Set($0.map { $0.lowercased() }) }
        let drop = Set(excludedApps.map { $0.lowercased() })
        let wanted = search.map(NotificationQueries.fold)?.trimmingCharacters(in: .whitespaces)
        return notifications.filter { n in
            if let since, n.date < since { return false }
            if let senders, !senders.contains(n.sender) { return false }
            if let keep, !keep.contains(n.app.lowercased()) { return false }
            if drop.contains(n.app.lowercased()) { return false }
            if let wanted, !wanted.isEmpty {
                let text = [n.title, n.subtitle, n.body].compactMap { $0 }.joined(separator: " ")
                guard NotificationQueries.startsAWord(wanted, in: NotificationQueries.fold(text)) else { return false }
            }
            return true
        }
    }
}

/// Counting.
public enum NotificationQueries {

    /// One app's held notifications.
    public struct AppSummary: Codable, Sendable, Hashable {
        public var app: String
        public var sender: SenderKind
        public var count: Int
        public var newest: Date
        public var oldest: Date
    }

    /// Per app, most notifications first (newest breaks ties).
    public static func byApp(_ notifications: [StoredNotification]) -> [AppSummary] {
        Dictionary(grouping: notifications) { $0.app.lowercased() }.map { _, group in
            AppSummary(app: group[0].app, sender: group[0].sender, count: group.count,
                       newest: group.map(\.date).max() ?? .distantPast, oldest: group.map(\.date).min() ?? .distantPast)
        }
        .sorted { ($0.count, $0.newest) > ($1.count, $1.newest) }
    }

    /// Whether `needle` starts a word in `text` (both folded).
    static func startsAWord(_ needle: String, in text: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: range) {
            if found.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber) { return true }
            range = found.upperBound..<text.endIndex
        }
        return false
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
