//
//  NotificationDecoding.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  A record's `data` column is a binary property list. MEASURED shape
//  (macOS 27.0.1):
//
//    {app, date, orig, styl, srce, uuid,
//     req: {titl, subt, body, cate, thre, iden, dest, usda, scat, ddac, unicon},
//     resp: {act, for}}
//
//  Messages puts the sender in `titl` and the text in `body`; WhatsApp
//  Desktop sends `body` only. `usda` is the app's private payload and is
//  not read. The `dest` bits are named by Apple's own
//  UNNotificationDestinationStrings(): 1 Alert, 2 LockScreen,
//  4 NotificationCenter, 8 CarPlay.
//

import Foundation

/// Decoding records. Pure.
public enum NotificationDecoding {

    /// The destinations in a `dest` bitmask, in bit order.
    public static func destinations(_ bits: Int) -> [NotificationDestination] {
        let named: [(bit: Int, destination: NotificationDestination)] = [
            (1, .alert), (2, .lockScreen), (4, .notificationCenter), (8, .carPlay),
        ]
        return named.filter { bits & $0.bit != 0 }.map(\.destination)
    }

    /// The record UUIDs in a `delivered` list: raw 16-byte UUIDs, concatenated.
    public static func uuids(_ list: Data) -> [String] {
        stride(from: 0, to: list.count - list.count % 16, by: 16).map { offset in
            let bytes = Array(list[(list.startIndex + offset)..<(list.startIndex + offset + 16)])
            return NSUUID(uuidBytes: bytes).uuidString
        }
    }

    /// One record, or `nil` when the data is not a notification record.
    ///
    /// - Parameters:
    ///   - uuid: the row's `uuid` column, when the plist lacks its own.
    ///   - delivered: the ids macOS lists as delivered now.
    public static func notification(_ data: Data, uuid: Data?, deliveredDate: Double?, delivered: Set<String>) -> StoredNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let request = plist["req"] as? [String: Any] ?? [:]
        let idData = (plist["uuid"] as? Data) ?? uuid
        guard let app = plist["app"] as? String,
              let id = idData.flatMap({ $0.count == 16 ? NSUUID(uuidBytes: Array($0)).uuidString : nil }) else { return nil }
        let seconds = deliveredDate ?? (plist["date"] as? Double) ?? 0
        let text = { (key: String) -> String? in
            guard let value = request[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        let title = text("titl"), thread = text("thre")
        return StoredNotification(
            id: id,
            app: app,
            sender: SenderKinds.kind(of: app, title: title, thread: thread),
            date: Date(timeIntervalSinceReferenceDate: seconds),
            title: title,
            subtitle: text("subt"),
            body: text("body"),
            category: text("cate"),
            thread: thread,
            requestID: text("iden"),
            destinations: destinations((request["dest"] as? Int) ?? 0),
            delivered: delivered.contains(id),
            styleCode: plist["styl"] as? Int,
            originCode: plist["orig"] as? Int,
            responseAction: (plist["resp"] as? [String: Any])?["act"] as? Int
        )
    }
}

/// Telling people from apps from macOS. Pure.
public enum SenderKinds {

    /// Apps whose notifications are a person writing or calling (lower case).
    public static let peopleApps: Set<String> = [
        "com.apple.mobilesms", "com.apple.ichat", "com.apple.mail", "com.apple.facetime", "com.apple.mobilephone",
        "com.apple.telephonyutilities", "net.whatsapp.whatsapp", "desktop.whatsapp", "ru.keepcoder.telegram",
        "org.telegram.desktop", "org.whispersystems.signal-desktop", "com.tinyspeck.slackmacgap", "com.hnc.discord",
        "com.microsoft.teams2", "com.microsoft.teams", "com.microsoft.outlook", "us.zoom.xos", "com.facebook.archon",
        "com.readdle.smartemail-mac", "com.superhuman.mail", "it.bloop.airmail2", "com.google.chrome.app.messages",
    ]

    /// Apple services that notify but are neither apps nor named like daemons (measured, macOS 27.0.1).
    public static let appleServices: Set<String> = ["com.apple.lockdownmode", "com.apple.timezoneupdates.tznotify"]

    /// The kind for a bundle identifier: listed messaging apps are people;
    /// `_system_center_:` senders and Apple's notification-only services are
    /// macOS; everything else is an app.
    public static func kind(of app: String) -> SenderKind {
        let id = app.lowercased()
        if peopleApps.contains(id) { return .person }
        if id.hasPrefix("_system_center_:") || appleServices.contains(id) { return .system }
        if id.hasPrefix("com.apple."), id.contains("notification") || isDaemon(id) { return .system }
        return .app
    }

    /// The kind for one notification. From a messaging app, it is a person
    /// only when it names a sender (title) or a conversation (thread) —
    /// MEASURED: a friend's iMessage carried both, while WhatsApp's own
    /// "Download completed" notices (category `save_assets`) carried neither.
    public static func kind(of app: String, title: String?, thread: String?) -> SenderKind {
        let kind = kind(of: app)
        guard kind == .person else { return kind }
        return title != nil || thread != nil ? .person : .app
    }

    /// Apple background services carry a daemon's name, ending in `d`, in
    /// some part of their id (`com.apple.tccd`, `com.apple.identityservicesd.firewall`)
    /// — never an app's word like `ical`, `findmy` or `dt`.
    static func isDaemon(_ id: String) -> Bool {
        id.split(separator: ".").dropFirst(2).contains { $0.count > 3 && $0.hasSuffix("d") }
    }
}
