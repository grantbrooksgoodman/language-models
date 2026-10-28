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
        var idleStartDate: Date?
        var nextReloadDate = Date().addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))

        while Date() < deadline {
            try throwIfOffline()

            // A transient failure to read the page state (e.g. mid-navigation)
            // shouldn't abort readiness; keep polling until the deadline.
            let state = try? await probePageState()
            if let state {
                if state.isChallengePresent {
                    try await resolveChallenge()
                    idleStartDate = nil
                    continue
                }

                if state.isLoggedOutModalPresent {
                    await dismissGate()
                }

                if state.isComposerPresent,
                   !state.isStreaming {
                    return
                }
            }

            // A page that has finished loading with nothing to show is
            // idle; it is reloaded once it has been idle for the full
            // interval, as is a page whose navigation failed.
            if isLoading || state?.isStreaming == true {
                idleStartDate = nil
            } else if idleStartDate == nil {
                idleStartDate = Date()
            }

            if shouldReload(
                idleStartDate: idleStartDate,
                nextReloadDate: nextReloadDate
            ) {
                reload()
                idleStartDate = nil
                nextReloadDate = Date().addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))
            }

            try await sleep(for: Floats.readinessPollIntervalSeconds)
        }

        guard let lastNavigationError else {
            throw .sessionNotReady
        }

        throw .requestFailed(lastNavigationError.localizedDescription)
    }

    func startNewChat() async throws(LanguageModelError) {
        clearConversation()
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
    /// the assistant reply. A follow-up is submitted only once the page
    /// is verified to show the conversation, restoring it once if it
    /// does not. The stream state is reset *before* submitting so no
    /// stream message is missed. If the prompt is still in the composer
    /// once the confirmation window elapses, it is submitted once more.
    /// A submission the page rejects is retried until the readiness
    /// window elapses. If the task is cancelled once the prompt has
    /// been submitted, the page's turn is stopped before the call
    /// throws. The conversation's anchors are recorded once the reply
    /// is read.
    func respondViaComposer(_ prompt: String) async throws(LanguageModelError) -> String {
        try await prepareForTurn()

        let transcript = await probeTranscript()
        resetStreamState()
        try await submitComposerWhenReady(prompt)

        let reply: String
        do throws(LanguageModelError) {
            reply = try await replyAfterSubmission(
                of: prompt,
                since: transcript
            )
        } catch .cancelled {
            await stopStreaming()
            throw .cancelled
        }

        await recordConversation()
        return reply
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Conversation Helpers

    func isConversationIntact() async -> Bool {
        guard !isPageStateLost else { return false }

        if let conversationID {
            guard let pageState = try? await probePageState(),
                  pageState.urlConversationID == conversationID else { return false }
        }

        guard let anchorMessageID else { return true }
        return await probeTranscript(anchorMessageID: anchorMessageID)?.isAnchorPresent == true
    }

    func loadConversation(_ url: URL) async {
        if currentURL == nil {
            await ChatGPTContentRules.waitUntilCompiled()
        }

        guard currentURL != url else {
            return reload()
        }

        load(url)
    }

    func loseConversation() async throws(LanguageModelError) -> Never {
        await logDiagnostics("The page no longer shows the conversation.")
        clearConversation()
        throw .conversationLost
    }

    func prepareForTurn() async throws(LanguageModelError) {
        guard isConversationActive else {
            return try await prepareForSubmission()
        }

        // A conversation whose page was lost is restored before the
        // readiness wait, which would otherwise load a new chat.
        if !isPageStateLost {
            try await prepareForSubmission()
            if try await waitForConversation() {
                return
            }
        }

        guard let conversationURL else {
            try await loseConversation()
        }

        await loadConversation(conversationURL)
        try await prepareForSubmission()

        guard try await waitForConversation() else {
            try await loseConversation()
        }
    }

    /// The page may still be rendering its messages once its composer
    /// is ready, so the check is repeated until it passes or the window
    /// elapses.
    func waitForConversation() async throws(LanguageModelError) -> Bool {
        let deadline = Date().addingTimeInterval(Double(Floats.conversationVerificationTimeoutSeconds))

        repeat {
            if await isConversationIntact() {
                return true
            }

            try await sleep(for: Floats.readinessPollIntervalSeconds)
        } while Date() < deadline

        return false
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
