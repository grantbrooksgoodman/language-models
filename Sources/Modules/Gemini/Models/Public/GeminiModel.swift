//
//  GeminiModel.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// A Gemini model.
///
/// Set a model on a ``GeminiConfig`` to control which model answers the
/// prompt.
public enum GeminiModel: String, Sendable {
    /// Gemini 2.0 Flash.
    case flash20 = "gemini-2.0-flash"

    /// Gemini 2.5 Flash.
    case flash25 = "gemini-2.5-flash"
}
