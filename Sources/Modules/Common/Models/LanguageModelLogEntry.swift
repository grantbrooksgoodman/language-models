//
//  LanguageModelLogEntry.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// A message LanguageModels logs, with the source location that
/// produced it.
///
/// A ``LanguageModelLogDelegate`` receives entries, and can forward
/// them to the app's own logging. ``category`` names the part of the
/// package the entry comes from – `ChatGPT`, `Gemini`, or `Session` –
/// and ``error`` carries the error an entry reports, if any.
public struct LanguageModelLogEntry: Sendable {
    // MARK: - Types

    /// The severity of an entry.
    public enum Level: Sendable {
        /// Detail that helps diagnose a problem, such as the text of a
        /// prompt or reply.
        case debug

        /// A failure.
        case error

        /// A lifecycle event.
        case info
    }

    // MARK: - Properties

    /// The part of the package the entry comes from: `ChatGPT`,
    /// `Gemini`, or `Session`.
    public let category: String

    /// The error the entry reports, if any.
    public let error: LanguageModelError?

    /// The file the entry was logged from, as `#fileID` reports it.
    public let fileName: String

    /// The function the entry was logged from.
    public let function: String

    /// The severity of the entry.
    public let level: Level

    /// The line the entry was logged from.
    public let line: Int

    /// The message.
    public let message: String
}
