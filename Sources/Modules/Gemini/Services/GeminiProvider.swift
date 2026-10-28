//
//  GeminiProvider.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

@MainActor
final class GeminiProvider: LanguageModelResponding {
    // MARK: - Constants Accessors

    private typealias Floats = Constants.CGFloats

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private let config: GeminiConfig

    private var history = [GeminiRequest.Content]()

    // MARK: - Init

    init(config: GeminiConfig) {
        self.config = config
    }

    // MARK: - Methods

    func prewarm() {}

    func response(to prompt: String) async throws(LanguageModelError) -> String {
        let startDate = Date.now
        log("Requesting a reply from \(config.model.rawValue) with \(history.count) prior turns.")
        log(
            "Prompt: \(prompt)",
            level: .debug
        )

        do throws(LanguageModelError) {
            let reply = try await reply(to: prompt)
            log("Received a \(reply.count)-char reply in \(String(format: "%.2f s", Date.now.timeIntervalSince(startDate))).")
            log(
                "Reply: \(reply)",
                level: .debug
            )

            return reply
        } catch {
            if case .cancelled = error {
                log("The request was cancelled.")
            } else {
                log(
                    error.localizedDescription,
                    level: .error,
                    error: error
                )
            }

            throw error
        }
    }

    func startNewConversation() async throws(LanguageModelError) {
        log("Cleared the conversation history.")
        history = []
    }

    // MARK: - Auxiliary

    private func failureDescription(
        statusCode: Int,
        data: Data
    ) -> String {
        let description = "HTTP \(statusCode)"
        guard let message = try? JSONDecoder().decode(
            GeminiErrorResponse.self,
            from: data
        ).error?.message,
            !message.isEmpty else { return description }

        return "\(description): \(message)"
    }

    private func geminiRequest(for userTurn: GeminiRequest.Content) -> GeminiRequest {
        .init(
            contents: history + [userTurn],
            systemInstruction: config.systemMessage.map { systemMessage in
                .init(
                    parts: [.init(text: systemMessage)],
                    role: "system"
                )
            }
        )
    }

    private func log(
        _ message: String,
        level: LanguageModelLogEntry.Level = .info,
        error: LanguageModelError? = nil,
        fileName: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        LoggingService.log(
            message,
            level: level,
            category: Strings.geminiLoggerCategory,
            error: error,
            fileName: fileName,
            function: function,
            line: line
        )
    }

    private func makeURLRequest(
        _ geminiRequest: GeminiRequest,
        apiKey: String
    ) throws(LanguageModelError) -> URLRequest {
        guard let url = URL(
            string: "\(Strings.geminiEndpointPrefix)\(config.model.rawValue):generateContent"
        ) else {
            throw .requestFailed("The request URL could not be constructed.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.assumesHTTP3Capable = true
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Double(Floats.geminiRequestTimeoutSeconds)

        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        urlRequest.setValue(
            apiKey,
            forHTTPHeaderField: "x-goog-api-key"
        )

        guard let httpBody = try? JSONEncoder().encode(geminiRequest) else {
            throw .requestFailed("The request body could not be encoded.")
        }

        urlRequest.httpBody = httpBody
        return urlRequest
    }

    private func reply(to prompt: String) async throws(LanguageModelError) -> String {
        guard !Task.isCancelled else {
            throw .cancelled
        }

        guard let apiKey = LanguageModels.geminiAPIKeyDelegate?.apiKey else {
            throw .missingAPIKey
        }

        let userTurn = GeminiRequest.Content(
            parts: [.init(text: prompt)],
            role: "user"
        )

        let urlRequest = try makeURLRequest(
            geminiRequest(for: userTurn),
            apiKey: apiKey
        )

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw .timedOut
        } catch {
            throw .requestFailed(error.localizedDescription)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw .requestFailed("The server did not return an HTTP response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw .requestFailed(failureDescription(
                statusCode: httpResponse.statusCode,
                data: data
            ))
        }

        guard let geminiResponse = try? JSONDecoder().decode(
            GeminiResponse.self,
            from: data
        ) else {
            throw .requestFailed("The response could not be decoded.")
        }

        guard let text = geminiResponse.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw .emptyResponse
        }

        history.append(userTurn)
        history.append(.init(
            parts: [.init(text: text)],
            role: "model"
        ))

        return text
    }
}
