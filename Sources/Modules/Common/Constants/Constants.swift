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
        static let geminiRequestTimeoutSeconds: CGFloat = 60
        static let readinessPollIntervalSeconds: CGFloat = 0.5
        static let readinessReloadIntervalSeconds: CGFloat = 10
        static let responseTimeoutSeconds: CGFloat = 90
        static let sessionReadyTimeoutSeconds: CGFloat = 30
    }

    // MARK: - String

    enum Strings {
        /// The base ChatGPT URL.
        static let baseURLString = "https://chatgpt.com/"

        /// The name of the script message handler the injected bridge
        /// posts to.
        static let bridgeMessageHandlerName = "chatGPTBridge"

        /// A fixed identifier for the persistent website data store shared
        /// by every host. Must remain stable across launches; not a
        /// ChatGPT detail.
        static let dataStoreIdentifier = "F9C0A1B2-3D4E-4F5A-8B6C-7D8E9F0A1B2C"

        /// A desktop macOS Safari user agent, set as the web view's
        /// `customUserAgent`.
        static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

        /// The prefix of the Gemini `generateContent` endpoint, before
        /// the model name.
        static let geminiEndpointPrefix = "https://generativelanguage.googleapis.com/v1beta/models/"
    }
}
