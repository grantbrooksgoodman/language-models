//
//  LoggingService.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation
import os

/// Logs an entry to the registered delegate, or to the unified
/// logging system, when ``LanguageModels/logLevel`` includes its level.
@MainActor
enum LoggingService {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private static var loggers = [String: Logger]()

    // MARK: - Methods

    static func log(
        _ message: String,
        level: LanguageModelLogEntry.Level = .info,
        category: String,
        error: LanguageModelError? = nil,
        fileName: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LanguageModels.logLevel.includes(level) else { return }

        let entry = LanguageModelLogEntry(
            category: category,
            error: error,
            fileName: fileName,
            function: function,
            level: level,
            line: line,
            message: message
        )

        guard let delegate = LanguageModels.logDelegate else {
            return logToUnifiedLogging(entry)
        }

        delegate.log(entry)
    }

    // MARK: - Auxiliary

    private static func logToUnifiedLogging(_ entry: LanguageModelLogEntry) {
        let logger = loggers[entry.category] ?? Logger(
            subsystem: Strings.loggerSubsystem,
            category: entry.category
        )

        loggers[entry.category] = logger

        switch entry.level {
        case .debug: logger.debug("\(entry.message, privacy: .public)")
        case .error: logger.error("\(entry.message, privacy: .public)")
        case .info: logger.info("\(entry.message, privacy: .public)")
        }
    }
}
