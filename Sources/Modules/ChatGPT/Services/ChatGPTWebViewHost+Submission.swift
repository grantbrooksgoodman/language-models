//
//  ChatGPTWebViewHost+Submission.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

extension ChatGPTWebViewHost {
    // MARK: - Constants Accessors

    private typealias Floats = Constants.CGFloats

    // MARK: - Methods

    func prepareForSubmission() async throws(LanguageModelError) {
        if currentURL == nil { load() }

        let deadline = Date().addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))
        var nextReloadDate = Date().addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))

        while Date() < deadline {
            // A transient failure to read the page state (e.g. mid-navigation)
            // shouldn't abort readiness; keep polling until the deadline.
            if let state = try? await probePageState() {
                if state.isChallengePresent {
                    throw .challengeRequired
                }

                if state.isLoggedOutModalPresent {
                    await dismissGate()
                }

                if state.isComposerPresent,
                   !state.isStreaming {
                    return
                }
            }

            // Recover from a stalled or failed page load: if the composer
            // hasn't appeared within the interval, reload and keep waiting.
            if Date() >= nextReloadDate {
                reload()
                nextReloadDate = Date().addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))
            }

            try? await Task.sleep(for: .seconds(Double(Floats.readinessPollIntervalSeconds)))
        }

        throw .sessionNotReady
    }

    func startNewChat() async throws(LanguageModelError) {
        _ = try? await evaluate(ChatGPTSubmissionScripts.startNewChat)

        let deadline = Date().addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))
        while Date() < deadline {
            let state = try await probePageState()
            if state.isComposerPresent,
               state.urlConversationID == nil {
                return
            }

            try? await Task.sleep(for: .seconds(Double(Floats.readinessPollIntervalSeconds)))
        }

        throw .sessionNotReady
    }

    /// Inserts `prompt` into the live composer and submits it, then returns
    /// the assistant reply assembled from the intercepted conversation
    /// stream. Subscribes for completion *before* submitting so no stream
    /// message is missed.
    func respondViaComposer(_ prompt: String) async throws(LanguageModelError) -> String {
        try await prepareForSubmission()

        let completion = Task { @MainActor in
            await waitForCompleted(
                within: .seconds(Double(Floats.responseTimeoutSeconds))
            )
        }

        do throws(LanguageModelError) {
            try await submitComposer(prompt)
        } catch {
            completion.cancel()
            throw error
        }

        guard let text = await completion.value else {
            throw .emptyResponse
        }

        return text
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Submission Helpers

    func describe(_ result: Any?) -> String {
        (result as? String) ?? "nil"
    }

    func dismissGate() async {
        _ = try? await evaluate(ChatGPTSubmissionScripts.dismissGate)
    }

    func isOK(_ result: Any?) -> Bool {
        guard let string = result as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["ok"] as? Bool) == true
    }

    func submitComposer(_ prompt: String) async throws(LanguageModelError) {
        let insertResult = try await evaluate(
            ChatGPTSubmissionScripts.insertPrompt,
            arguments: ["text": prompt]
        )

        guard isOK(insertResult) else {
            throw .submissionFailed(
                "composer insertion failed: \(describe(insertResult))"
            )
        }

        let sendResult = try await evaluate(ChatGPTSubmissionScripts.sendPrompt)
        guard isOK(sendResult) else {
            throw .submissionFailed(
                "composer send failed: \(describe(sendResult))"
            )
        }
    }

    func waitForCompleted(within duration: Duration) async -> String? {
        let observer = Task { @MainActor () -> String? in
            for await message in bridgeMessages() {
                if case let .completed(fullText) = message { return fullText }
            }
            return nil
        }

        let timeout = Task {
            try? await Task.sleep(for: duration)
            observer.cancel()
        }

        let result = await observer.value
        timeout.cancel()
        return result
    }
}
