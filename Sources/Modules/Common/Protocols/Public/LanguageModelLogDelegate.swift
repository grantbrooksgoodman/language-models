//
//  LanguageModelLogDelegate.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// An interface for receiving the entries LanguageModels logs.
///
/// Conform to `LanguageModelLogDelegate` and register your
/// implementation with ``LanguageModels/registerLogDelegate(_:)`` to
/// route the package's logging through your own:
///
/// ```swift
/// struct LogForwarder: LanguageModelLogDelegate {
///     func log(_ entry: LanguageModelLogEntry) {
///         Logger.log(
///             entry.message,
///             domain: .init("languageModels"),
///             sender: self,
///             fileName: entry.fileName,
///             function: entry.function,
///             line: entry.line
///         )
///     }
/// }
///
/// LanguageModels.registerLogDelegate(LogForwarder())
/// LanguageModels.logLevel = .info
/// ```
///
/// Without a delegate, entries go to the unified logging system under
/// the `LanguageModels` subsystem, with the entry's category.
///
/// - Important: Entries arrive on the main actor, as they are logged,
///   and only for the levels ``LanguageModels/logLevel`` includes.
public protocol LanguageModelLogDelegate: Sendable {
    /// Receives an entry.
    ///
    /// - Parameter entry: The entry.
    func log(_ entry: LanguageModelLogEntry)
}
