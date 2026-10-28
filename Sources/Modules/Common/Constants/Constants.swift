//
//  Constants.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

enum Constants {
    // MARK: - CGFloat

    enum CGFloats {
        static let challengeAutoResolutionTimeoutSeconds: CGFloat = 15
        static let challengeCloseButtonInset: CGFloat = 16
        static let challengePresentationTimeoutSeconds: CGFloat = 120
        static let conversationVerificationTimeoutSeconds: CGFloat = 5
        static let fallbackRefreshIntervalSeconds: CGFloat = 2
        static let followUpStreamTimeoutSeconds: CGFloat = 10
        static let geminiRequestTimeoutSeconds: CGFloat = 60
        static let inFlightResponseTimeoutSeconds: CGFloat = 300
        static let readinessReloadIntervalSeconds: CGFloat = 10
        static let renderedReplyTimeoutSeconds: CGFloat = 5
        static let responseTimeoutSeconds: CGFloat = 90
        static let sessionReadyTimeoutSeconds: CGFloat = 30
        static let streamStartTimeoutSeconds: CGFloat = 15
        static let streamSettleIntervalSeconds: CGFloat = 0.5
        static let submissionConfirmationTimeoutSeconds: CGFloat = 3
    }

    // MARK: - Int

    enum Ints {
        /// WebKit's legacy "frame load interrupted" error code, raised by
        /// in-page navigation.
        static let frameLoadInterruptedErrorCode = 102

        static let maxConcurrentChatGPTOperations = 2
        static let maxConcurrentGeminiOperations = 10
        static let pageStatePushIntervalMilliseconds = 100
    }

    // MARK: - String

    enum Strings {
        /// The name of the background task a session runs its calls in.
        static let backgroundTaskName = "LanguageModelSession"

        /// The base ChatGPT URL.
        static let baseURLString = "https://chatgpt.com/"

        /// The name of the script message handler the injected bridge
        /// posts to.
        static let bridgeMessageHandlerName = "chatGPTBridge"

        /// Matches the private-use citation markers the conversation
        /// stream embeds in a reply, and any stray private-use character.
        static let citationMarkerPattern = #"\x{E200}.*?\x{E201}|[\x{E000}-\x{F8FF}]"#

        /// A fixed identifier for the persistent website data store shared
        /// by every host. Must remain stable across launches.
        static let dataStoreIdentifier = "F9C0A1B2-3D4E-4F5A-8B6C-7D8E9F0A1B2C"

        /// A desktop macOS Safari user agent, set as the web view's
        /// `customUserAgent`.
        static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

        /// The prefix of the Gemini `generateContent` endpoint, before
        /// the model name.
        static let geminiEndpointPrefix = "https://generativelanguage.googleapis.com/v1beta/models/"

        static let geminiLoggerCategory = "Gemini"
        static let loggerCategory = "ChatGPT"
        static let loggerSubsystem = "LanguageModels"
        static let sessionLoggerCategory = "Session"

        /// The error domain of WebKit's legacy navigation errors.
        static let webKitErrorDomain = "WebKitErrorDomain"
    }
}
