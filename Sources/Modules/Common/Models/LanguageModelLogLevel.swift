//
//  LanguageModelLogLevel.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// The amount of detail LanguageModels logs.
///
/// Set ``LanguageModels/logLevel`` to choose a level. Each level
/// includes the levels below it:
///
/// ```swift
/// LanguageModels.logLevel = .debug
/// ```
public enum LanguageModelLogLevel: Int, Comparable, Sendable {
    // MARK: - Cases

    /// Nothing is logged.
    case off

    /// Failures are logged: errors a session throws, navigation
    /// failures, and interruptions.
    case errors

    /// Lifecycle events are logged as well: calls, provider choice,
    /// page loads, submissions, streams, and conversation changes.
    case info

    /// Everything is logged, including the text of every prompt and
    /// reply, and the page diagnostics that accompany a failure.
    case debug

    // MARK: - Methods

    /// Returns a Boolean value that indicates whether entries of the
    /// given level are logged at this level.
    ///
    /// - Parameter level: The level of the entries.
    public func includes(_ level: LanguageModelLogEntry.Level) -> Bool {
        switch level {
        case .debug: self >= .debug
        case .error: self >= .errors
        case .info: self >= .info
        }
    }

    public static func < (
        lhs: LanguageModelLogLevel,
        rhs: LanguageModelLogLevel
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
