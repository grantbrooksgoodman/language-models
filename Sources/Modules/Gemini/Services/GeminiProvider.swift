//
//  GeminiProvider.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

struct GeminiProvider: LanguageModelResponding {
    // MARK: - Constants Accessors

    private typealias Floats = Constants.CGFloats
    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private let config: GeminiConfig

    // MARK: - Init

    init(config: GeminiConfig) {
        self.config = config
    }

    // MARK: - Methods

    func prewarm() {}

    func response(to prompt: String) async throws(LanguageModelError) -> String {
        guard let apiKey = LanguageModels.geminiAPIKeyDelegate?.apiKey else {
            throw .missingAPIKey
        }

        let urlRequest = try makeURLRequest(
            geminiRequest(for: prompt),
            apiKey: apiKey
        )

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw .requestFailed(error.localizedDescription)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw .requestFailed("The server did not return a success status code.")
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

        return text
    }

    func startNewConversation() async throws(LanguageModelError) {}

    // MARK: - Auxiliary

    private func geminiRequest(for prompt: String) -> GeminiRequest {
        .init(
            contents: [.init(
                parts: [.init(text: prompt)],
                role: "user"
            )],
            systemInstruction: config.systemMessage.map { systemMessage in
                .init(
                    parts: [.init(text: systemMessage)],
                    role: "system"
                )
            }
        )
    }

    private func makeURLRequest(
        _ geminiRequest: GeminiRequest,
        apiKey: String
    ) throws(LanguageModelError) -> URLRequest {
        guard let url = URL(
            string: "\(Strings.geminiEndpointPrefix)\(config.model.rawValue):generateContent?key=\(apiKey)"
        ) else {
            throw .requestFailed("The request URL could not be constructed.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.assumesHTTP3Capable = true
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = Double(Floats.geminiRequestTimeoutSeconds)

        guard let httpBody = try? JSONEncoder().encode(geminiRequest) else {
            throw .requestFailed("The request body could not be encoded.")
        }

        urlRequest.httpBody = httpBody
        return urlRequest
    }
}
