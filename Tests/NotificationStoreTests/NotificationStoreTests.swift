//
//  NotificationStoreTests.swift
//  NotificationStoreTests
//
//  Created by David Sherlock on 2026.
//
//  A fixture home with usernoted's db2 in the real schema's shape; every
//  sender and word invented.
//

import Foundation
import SQLite3
import Testing
@testable import NotificationStore

struct Fixture {

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notification-store-\(UUID().uuidString.prefix(8))")
    var locations: NotificationLocations { NotificationLocations(home: root) }
    var store: NotificationStore { NotificationStore(locations: locations) }

    init() throws {
        try FileManager.default.createDirectory(at: locations.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func remove() {
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.database.deletingLastPathComponent().path)
        try? FileManager.default.removeItem(at: root)
    }

    struct Note {
        var app: String
        var appID: Int
        var uuid = UUID()
        var date: Double
        var request: [String: Any]
        var delivered = true
    }

    static func uuidData(_ uuid: UUID) -> Data { withUnsafeBytes(of: uuid.uuid) { Data($0) } }

    static func record(_ note: Note) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "app": note.app, "date": note.date, "orig": 2, "styl": 0, "uuid": uuidData(note.uuid), "req": note.request,
        ] as [String: Any], format: .binary, options: 0)
    }

    /// Writes the store; `walOnly` notes stay in the write-ahead log.
    func write(apps: [(Int, String, Int?)], notes: [Note], walOnly: [Note] = []) throws {
        var db: OpaquePointer?
        guard sqlite3_open(locations.database.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        func exec(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: sql]) }
        }
        func bind(_ sql: String, _ blobs: [Data], _ number: Double? = nil) throws {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            for (index, blob) in blobs.enumerated() {
                _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index + 1), $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown, userInfo: [NSDebugDescriptionErrorKey: sql]) }
            sqlite3_finalize(statement)
        }
        func insert(_ note: Note) throws {
            try bind("INSERT INTO record (app_id, uuid, data, request_date, delivered_date, presented, style) VALUES (\(note.appID), ?, ?, \(note.date), \(note.date), 0, 0)",
                     [Self.uuidData(note.uuid), try Self.record(note)])
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR, badge INTEGER NULL)")
        try exec("CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB, request_date REAL, request_last_date REAL, delivered_date REAL, presented Bool, style INTEGER, snooze_fire_date REAL)")
        try exec("CREATE TABLE delivered (app_id INTEGER PRIMARY KEY, list BLOB)")
        for (id, identifier, badge) in apps {
            try exec("INSERT INTO app VALUES (\(id), '\(identifier)', \(badge.map(String.init) ?? "NULL"))")
            let list = (notes + walOnly).filter { $0.appID == id && $0.delivered }.reduce(Data()) { $0 + Self.uuidData($1.uuid) }
            try bind("INSERT INTO delivered VALUES (\(id), ?)", [list])
        }
        for note in notes { try insert(note) }
        try exec("PRAGMA wal_checkpoint(TRUNCATE)")
        try exec("PRAGMA wal_autocheckpoint=0")
        for note in walOnly { try insert(note) }
    }
}

@Suite(.serialized)
struct StoreTests {

    @Test func notificationsAreDecodedNewestFirst() throws {
        let f = try Fixture()
        defer { f.remove() }
        let message = Fixture.Note(app: "com.apple.MobileSMS", appID: 1, date: 800_000_300,
                                   request: ["titl": "Ada", "body": "Running late, sorry", "cate": "com.apple.messages.IncomingMessageCategory.Madrid", "thre": "chat-1", "dest": 15, "iden": "m-1"])
        let backup = Fixture.Note(app: "com.example.Backup", appID: 2, date: 800_000_100,
                                  request: ["titl": "Backup finished", "body": "12 files", "dest": 7], delivered: false)
        let download = Fixture.Note(app: "net.whatsapp.WhatsApp", appID: 1, date: 800_000_050, request: ["body": "Download completed", "cate": "save_assets", "dest": 15])
        let system = Fixture.Note(app: "_system_center_:com.apple.diskspaced", appID: 3, date: 800_000_200, request: ["body": "Disk almost full", "dest": 6])
        try f.write(apps: [(1, "com.apple.mobilesms", 3), (2, "com.example.backup", nil), (3, "_system_center_:com.apple.diskspaced", nil), (4, "com.example.quiet", nil)],
                    notes: [message, backup, system, download])
        let all = try f.store.notifications()
        #expect(all.map(\.app) == ["com.apple.MobileSMS", "_system_center_:com.apple.diskspaced", "com.example.Backup", "net.whatsapp.WhatsApp"])
        #expect(all[3].sender == .app)   // WhatsApp talking, not a person
        let first = all[0]
        #expect(first.id == message.uuid.uuidString && first.title == "Ada" && first.body == "Running late, sorry")
        #expect(first.sender == .person && first.thread == "chat-1" && first.requestID == "m-1" && first.delivered)
        #expect(first.destinations == [.alert, .lockScreen, .notificationCenter, .carPlay])
        #expect(first.date == Date(timeIntervalSinceReferenceDate: 800_000_300))
        #expect(all[1].sender == .system && all[1].destinations == [.lockScreen, .notificationCenter] && all[1].title == nil)
        #expect(all[2].sender == .app && !all[2].delivered)
        let apps = try f.store.apps()
        #expect(apps.first { $0.identifier == "com.apple.mobilesms" }?.badge == 3)
        #expect(apps.first { $0.identifier == "com.example.quiet" }?.held == 0)
        #expect(apps.count == 4)
    }

    @Test func rowsOnlyInTheWriteAheadLogAreRead() throws {
        let f = try Fixture()
        defer { f.remove() }
        try f.write(apps: [(1, "com.example.app", nil)],
                    notes: [Fixture.Note(app: "com.example.App", appID: 1, date: 1, request: ["body": "old"])],
                    walOnly: [Fixture.Note(app: "com.example.App", appID: 1, date: 2, request: ["body": "new"])])
        let folder = f.locations.database.deletingLastPathComponent()
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(try f.store.notifications().map(\.body) == ["new", "old"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
    }

    @Test func refusalAndAbsence() throws {
        let f = try Fixture()
        defer { f.remove() }
        #expect(throws: NotificationStoreError.noStore(f.locations.database.path)) { try f.store.notifications() }
        try f.write(apps: [], notes: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.locations.database.deletingLastPathComponent().path)
        #expect(throws: NotificationStoreError.needsFullDiskAccess(f.locations.database.path)) { try f.store.notifications() }
    }
}

struct DecodingTests {

    /// The bits as Apple's UNNotificationDestinationStrings() names them.
    @Test func destinations() {
        #expect(NotificationDecoding.destinations(15) == [.alert, .lockScreen, .notificationCenter, .carPlay])
        #expect(NotificationDecoding.destinations(7) == [.alert, .lockScreen, .notificationCenter])
        #expect(NotificationDecoding.destinations(4) == [.notificationCenter])
        #expect(NotificationDecoding.destinations(16).isEmpty)
    }

    @Test func deliveredListsAreRawUUIDs() {
        let a = UUID(), b = UUID()
        #expect(NotificationDecoding.uuids(Fixture.uuidData(a) + Fixture.uuidData(b)) == [a.uuidString, b.uuidString])
        #expect(NotificationDecoding.uuids(Data([1, 2, 3])).isEmpty)
        #expect(NotificationDecoding.uuids(Data()).isEmpty)
    }

    @Test func notARecordIsSkipped() {
        #expect(NotificationDecoding.notification(Data("nope".utf8), uuid: nil, deliveredDate: 1, delivered: []) == nil)
        let noApp = try! PropertyListSerialization.data(fromPropertyList: ["req": ["body": "x"]], format: .binary, options: 0)
        #expect(NotificationDecoding.notification(noApp, uuid: Fixture.uuidData(UUID()), deliveredDate: 1, delivered: []) == nil)
    }

    /// Classified as measured on a real Mac's 112 notifying apps.
    @Test func senderKinds() {
        for person in ["com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.apple.mail", "com.apple.FaceTime", "com.tinyspeck.slackmacgap"] {
            #expect(SenderKinds.kind(of: person) == .person, "\(person)")
        }
        for system in ["_system_center_:com.apple.sharingd", "com.apple.tccd", "com.apple.icloudwebd", "com.apple.identityservicesd.firewall",
                       "com.apple.wifi.usernotifications.join", "com.apple.screentimenotifications", "com.apple.lockdownmode",
                       "com.apple.timezoneupdates.tznotify"] {
            #expect(SenderKinds.kind(of: system) == .system, "\(system)")
        }
        // From a messaging app: a person only with a sender or a conversation.
        #expect(SenderKinds.kind(of: "net.whatsapp.WhatsApp", title: nil, thread: nil) == .app)
        #expect(SenderKinds.kind(of: "net.whatsapp.WhatsApp", title: "Ada", thread: nil) == .person)
        #expect(SenderKinds.kind(of: "com.apple.MobileSMS", title: nil, thread: "chat-1") == .person)
        #expect(SenderKinds.kind(of: "com.example.Bank", title: "Payment", thread: "x") == .app)
        for app in ["com.apple.ical", "com.apple.findmy", "com.apple.dt.xcode", "com.apple.reminders", "com.getdropbox.dropbox",
                    "com.google.chrome", "com.apple.passbook", "com.apple.home"] {
            #expect(SenderKinds.kind(of: app) == .app, "\(app)")
        }
    }
}

struct QueryTests {

    let notes: [StoredNotification] = [
        StoredNotification(id: "1", app: "com.apple.MobileSMS", sender: .person, date: Date(timeIntervalSince1970: 300), title: "Ada", body: "Lunch tomorrow?"),
        StoredNotification(id: "2", app: "net.whatsapp.WhatsApp", sender: .person, date: Date(timeIntervalSince1970: 200), body: "Café at noon"),
        StoredNotification(id: "3", app: "com.example.Bank", sender: .app, date: Date(timeIntervalSince1970: 100), title: "Payment", body: "£40 to Ada"),
        StoredNotification(id: "4", app: "_system_center_:com.apple.diskspaced", sender: .system, date: Date(timeIntervalSince1970: 50), body: "Disk full"),
    ]

    @Test func filters() {
        #expect(NotificationFilter(since: Date(timeIntervalSince1970: 150)).apply(notes).map(\.id) == ["1", "2"])
        #expect(NotificationFilter(senders: [.person]).apply(notes).map(\.id) == ["1", "2"])
        #expect(NotificationFilter(apps: ["COM.EXAMPLE.BANK"]).apply(notes).map(\.id) == ["3"])
        #expect(NotificationFilter(excludedApps: ["com.example.bank"]).apply(notes).map(\.id) == ["1", "2", "4"])
        // Word starts, case and accents ignored, title and text both searched.
        #expect(NotificationFilter(search: "cafe").apply(notes).map(\.id) == ["2"])
        #expect(NotificationFilter(search: "ada").apply(notes).map(\.id) == ["1", "3"])
        #expect(NotificationFilter(search: "da").apply(notes).isEmpty)
    }

    @Test func perApp() {
        let more = notes + [StoredNotification(id: "5", app: "net.whatsapp.whatsapp", sender: .person, date: Date(timeIntervalSince1970: 400), body: "x")]
        let summary = NotificationQueries.byApp(more)
        #expect(summary.first?.count == 2 && summary.first?.app.lowercased() == "net.whatsapp.whatsapp")
        #expect(summary.first?.newest == Date(timeIntervalSince1970: 400) && summary.first?.oldest == Date(timeIntervalSince1970: 200))
        #expect(summary.count == 4)
    }
}
