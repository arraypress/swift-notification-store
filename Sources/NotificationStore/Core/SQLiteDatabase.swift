//
//  SQLiteDatabase.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  The smallest SQLite wrapper that runs this library's queries, opened only
//  ever on a private COPY of a store (see DatabaseSnapshot): the live stores
//  are never opened at all, so nothing here can write to them.
//

import Foundation
import SQLite3

/// A SQLite connection to a snapshot.
final class SQLiteDatabase {

    private let handle: OpaquePointer
    private let path: String

    /// Opens a snapshot file.
    ///
    /// Read-write on purpose: the copy carries the live store's write-ahead
    /// log, and folding a WAL into a read needs to build its index beside it.
    /// Only SELECTs are ever run, and the copy is deleted afterwards.
    init(path: String) throws(NotificationStoreError) {
        self.path = path
        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(path, &pointer, SQLITE_OPEN_READWRITE, nil)
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            if let pointer { sqlite3_close_v2(pointer) }
            throw .unreadable(path, reason: message)
        }
        handle = pointer
    }

    deinit { sqlite3_close_v2(handle) }

    /// Runs a query, handing each row over.
    func query(_ sql: String, row: (Row) -> Void) throws(NotificationStoreError) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw .unreadable(path, reason: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW { row(Row(statement: statement)); continue }
            if step == SQLITE_DONE { return }
            throw .unreadable(path, reason: String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// The columns a table has, upper-cased — they come and go between macOS
    /// releases, and a query naming a missing one fails outright.
    func columns(of table: String) -> Set<String> {
        var found: Set<String> = []
        try? query("PRAGMA table_info(\(table))") { row in
            if let name = row.text(1) { found.insert(name.uppercased()) }
        }
        return found
    }

    /// One row of a result.
    struct Row {

        let statement: OpaquePointer

        /// A column as a double, `nil` for NULL.
        func double(_ index: Int32) -> Double? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
        }

        /// A column as an integer, `nil` for NULL.
        func integer(_ index: Int32) -> Int? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, index))
        }

        /// A column as text, `nil` for NULL or empty.
        func text(_ index: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, index) else { return nil }
            let value = String(cString: bytes)
            return value.isEmpty ? nil : value
        }

        /// A column as bytes, `nil` for NULL.
        func blob(_ index: Int32) -> Data? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }
}
