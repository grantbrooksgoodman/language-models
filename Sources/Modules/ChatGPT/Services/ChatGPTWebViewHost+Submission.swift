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

            try await sleep(for: Floats.readinessPollIntervalSeconds)
        }

        throw .sessionNotReady
    }

    func startNewChat() async throws(LanguageModelError) {
        guard currentURL != nil else {
            return resetStreamState()
        }

        _ = try? await evaluate(ChatGPTSubmissionScripts.startNewChat)

        let deadline = Date().addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))
        while Date() < deadline {
            if let state = try? await probePageState(),
               state.isComposerPresent,
               state.urlConversationID == nil {
                return
            }

            try await sleep(for: Floats.readinessPollIntervalSeconds)
        }

        throw .sessionNotReady
    }

    /// Inserts `prompt` into the live composer and submits it, then returns
    /// the assistant reply. The stream state is reset *before* submitting
    /// so no stream message is missed. If the prompt is still in the
    /// composer once the confirmation window elapses, it is submitted
    /// once more. A submission the page rejects is retried until the
    /// readiness window elapses. If the task is cancelled once the
    /// prompt has been submitted, the page's turn is stopped before the
    /// call throws.
    func respondViaComposer(_ prompt: String) async throws(LanguageModelError) -> String {
        try await prepareForSubmission()

        let transcript = await probeTranscript()
        resetStreamState()
        try await submitComposerWhenReady(prompt)

        do throws(LanguageModelError) {
            return try await replyAfterSubmission(
                of: prompt,
                since: transcript
            )
        } catch .cancelled {
            await stopStreaming()
            throw .cancelled
        }
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
    ) async throws(LanguageModelError) -> Bool {
        let deadline = Date().addingTimeInterval(Double(Floats.submissionConfirmationTimeoutSeconds))
        var transcript: ChatGPTTranscriptState?

        repeat {
            guard !hasStreamStarted else { return false }

            transcript = await probeTranscript()
            if let transcript,
               transcript.hasNewUserMessage(since: baseline) || !transcript.composerText.contains(prompt) {
                return false
            }

            try await sleep(for: Floats.turnPollIntervalSeconds)
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

    func replyAfterSubmission(
        of prompt: String,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String {
        guard try await isPromptUnsent(
            prompt,
            since: transcript
        ) else {
            return try await reply(since: transcript)
        }

        await logDiagnostics("The page left the prompt unsent; submitting it again.")
        try await submitComposerWhenReady(prompt)

        guard try await isPromptUnsent(
            prompt,
            since: transcript
        ) else {
            return try await reply(since: transcript)
        }

        await logDiagnostics("The prompt was not sent.")
        throw .submissionFailed("The prompt was not sent.")
    }

    func stopStreaming() async {
        _ = try? await evaluate(ChatGPTSubmissionScripts.stopStreaming)
    }

    func submitComposer(_ prompt: String) async throws(LanguageModelError) {
        let insertResult = try await evaluate(
            ChatGPTSubmissionScripts.insertPrompt,
            arguments: ["text": prompt]
        )

        guard isOK(insertResult) else {
            throw .submissionFailed("composer insertion failed: \(describe(insertResult))")
        }

        let sendResult = try await evaluate(ChatGPTSubmissionScripts.sendPrompt)
        guard isOK(sendResult) else {
            throw .submissionFailed("composer send failed: \(describe(sendResult))")
        }
    }

    func submitComposerWhenReady(_ prompt: String) async throws(LanguageModelError) {
        // The page serves its composer before it can accept input, so
        // a submission it rejects is retried, once readiness is
        // confirmed again, until the readiness window elapses.
        let deadline = Date().addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))

        while true {
            do throws(LanguageModelError) {
                return try await submitComposer(prompt)
            } catch let .submissionFailed(reason) {
                guard Date() < deadline else {
                    await logDiagnostics(reason)
                    throw .submissionFailed(reason)
                }
            }

            try await sleep(for: Floats.readinessPollIntervalSeconds)
            try await prepareForSubmission()
        }
    }
}
