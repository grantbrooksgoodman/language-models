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
        if currentURL == nil {
            await ChatGPTContentRules.waitUntilCompiled()
            load()
        }

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
    /// the assistant reply. The stream state is reset *before* submitting
    /// so no stream message is missed. If the prompt is still in the
    /// composer once the confirmation window elapses, it is submitted
    /// once more.
    func respondViaComposer(_ prompt: String) async throws(LanguageModelError) -> String {
        try await prepareForSubmission()

        let transcript = await probeTranscript()
        resetStreamState()
        try await submitComposer(prompt)

        guard await isPromptUnsent(
            prompt,
            since: transcript
        ) else {
            return try await reply(since: transcript)
        }

        await logDiagnostics("The page left the prompt unsent; submitting it again.")
        try await prepareForSubmission()
        try await submitComposer(prompt)

        guard await isPromptUnsent(
            prompt,
            since: transcript
        ) else {
            return try await reply(since: transcript)
        }

        await logDiagnostics("The prompt was not sent.")
        throw .submissionFailed("The prompt was not sent.")
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

    func isPromptUnsent(
        _ prompt: String,
        since baseline: ChatGPTTranscriptState?
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(Floats.submissionConfirmationTimeoutSeconds))
        var transcript: ChatGPTTranscriptState?

        repeat {
            guard !hasStreamStarted else { return false }

            transcript = await probeTranscript()
            if let transcript,
               transcript.hasNewUserMessage(since: baseline) || !transcript.composerText.contains(prompt) {
                return false
            }

            try? await Task.sleep(for: .seconds(Double(Floats.turnPollIntervalSeconds)))
        } while Date() < deadline

        // No signal confirmed the send. The prompt is unsent only if the
        // composer was last seen still holding it, so an unconfirmed but
        // successful send is never submitted twice.
        return !hasStreamStarted && transcript != nil
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
            let reason = "composer insertion failed: \(describe(insertResult))"
            await logDiagnostics(reason)
            throw .submissionFailed(reason)
        }

        let sendResult = try await evaluate(ChatGPTSubmissionScripts.sendPrompt)
        guard isOK(sendResult) else {
            let reason = "composer send failed: \(describe(sendResult))"
            await logDiagnostics(reason)
            throw .submissionFailed(reason)
        }
    }
}
