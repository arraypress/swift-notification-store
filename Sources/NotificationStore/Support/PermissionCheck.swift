//
//  PermissionCheck.swift
//  NotificationStore
//
//  Created by David Sherlock on 2026.
//
//  Telling "macOS said no" from "it is not there". Privacy protection
//  refuses with EPERM (TCC) and plain permissions with EACCES — but
//  Foundation reports a refusal on a PARENT folder as "file not found", so
//  every check here asks the kernel directly with open(2).
//

import Foundation

/// Classifying paths and file errors.
enum PermissionCheck {

    /// What opening a path for reading finds.
    enum Access: Equatable {
        case readable
        case missing
        case refused
    }

    /// Whether a file or folder can be opened for reading.
    static func access(_ path: String) -> Access {
        let descriptor = open(path, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return .readable
        }
        return isRefusal(errno: errno) ? .refused : .missing
    }

    /// Whether an error is a refusal to read.
    static func isRefusal(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isRefusal(underlying) }
        return false
    }

    /// Whether an errno is a refusal.
    static func isRefusal(errno code: Int32) -> Bool { code == EPERM || code == EACCES }
}
