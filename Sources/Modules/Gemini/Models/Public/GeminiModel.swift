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
    /// Gemini 2.5 Flash.
    case flash25 = "gemini-2.5-flash"

    /// Gemini 3.8 Flash.
    case flash38 = "gemini-3.8-flash"
}
