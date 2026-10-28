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

        let deadline = Date.now.addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))
        var reloadDate = Date.now.addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))

        while true {
            try throwIfOffline()

            if let state = events.pageState {
                if state.isChallengePresent {
                    try await resolveChallenge()
                    reloadDate = Date.now.addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))
                    continue
                }

                if state.isComposerPresent,
                   !state.isStreaming {
                    // A pushed state may trail the page by the push
                    // interval, so readiness is confirmed by a probe.
                    guard let confirmed = try? await probePageState() else { return }
                    events.record(pageState: confirmed)
                    guard confirmed.isChallengePresent || confirmed.isStreaming || !confirmed.isComposerPresent else { return }
                    continue
                }

                if state.isLoggedOutModalPresent {
                    await dismissGate()
                }
            }

            // The page is waited on until it needs attention or its
            // navigation fails, or until the reload decision is due.
            let sequence = events.sequence
            let didChange = try await events.wait(
                until: { [self] in
                    events.sequence != sequence && (needsReadinessAttention(events.pageState) || lastNavigationError != nil)
                },
                deadline: min(
                    deadline,
                    reloadDate
                )
            )

            if didChange {
                continue
            }

            guard Date.now < deadline else {
                try throwReadinessFailure()
            }

            if shouldReload() {
                reload()
            }

            reloadDate = Date.now.addingTimeInterval(Double(Floats.readinessReloadIntervalSeconds))
        }
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
        beginTurn()
        defer { endTurn() }
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

    func startNewChat() async throws(LanguageModelError) {
        clearConversation()
        guard currentURL != nil else {
            return events.resetStreamState()
        }

        _ = try? await evaluate(ChatGPTSubmissionScripts.startNewChat)

        try await events.wait(
            until: { [self] in
                guard let state = events.pageState else { return false }
                return state.isComposerPresent && state.urlConversationID == nil
            },
            deadline: Date.now.addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds)),
            timeoutError: .sessionNotReady
        )
    }
}

private extension ChatGPTWebViewHost {
    func describe(_ result: Any?) -> String {
        (result as? String) ?? "nil"
    }

    func dismissGate() async {
        _ = try? await evaluate(ChatGPTSubmissionScripts.dismissGate)
    }

    func isConversationIntact() async -> Bool {
        guard !isPageStateLost else { return false }

        if let conversationID {
            guard events.pageState?.urlConversationID == conversationID else { return false }
        }

        guard let anchorMessageID else { return true }
        return await probeTranscript(anchorMessageID: anchorMessageID)?.isAnchorPresent == true
    }

    func isOK(_ result: Any?) -> Bool {
        guard let string = result as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["ok"] as? Bool) == true
    }

    func isPromptUnsent(
        _ prompt: String,
        since baseline: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> Bool {
        // A send is confirmed by its stream, or by a new user message.
        let isSent = try await events.wait(
            until: { [self] in
                guard !events.hasStreamStarted else { return true }
                guard let lastUserMessageID = events.pageState?.lastUserMessageID else { return false }
                return lastUserMessageID != baseline?.lastUserMessageID
            },
            deadline: Date.now.addingTimeInterval(Double(Floats.submissionConfirmationTimeoutSeconds))
        )

        guard !isSent else { return false }

        // No signal confirmed the send. The prompt is unsent only if the
        // composer still holds it, so an unconfirmed but successful send
        // is never submitted twice.
        guard let transcript = await probeTranscript(),
              !transcript.hasNewUserMessage(since: baseline) else { return false }

        return !events.hasStreamStarted && transcript.composerText.contains(prompt)
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

    func needsReadinessAttention(_ state: ChatGPTPageState?) -> Bool {
        guard let state else { return false }
        return state.isChallengePresent || state.isLoggedOutModalPresent || (state.isComposerPresent && !state.isStreaming)
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

        let sendResult = try await evaluate(
            ChatGPTSubmissionScripts.sendPrompt,
            arguments: ["generation": events.turnGeneration]
        )

        guard isOK(sendResult) else {
            throw .submissionFailed("composer send failed: \(describe(sendResult))")
        }
    }

    func submitComposerWhenReady(_ prompt: String) async throws(LanguageModelError) {
        // The page serves its composer before it can accept input, so
        // a submission it rejects is retried, once the page changes
        // and readiness is confirmed again, until the readiness window
        // elapses.
        let deadline = Date.now.addingTimeInterval(Double(Floats.sessionReadyTimeoutSeconds))

        while true {
            do throws(LanguageModelError) {
                return try await submitComposer(prompt)
            } catch let .submissionFailed(reason) {
                guard Date.now < deadline else {
                    await logDiagnostics(reason)
                    throw .submissionFailed(reason)
                }
            }

            let sequence = events.sequence
            _ = try await events.wait(
                until: { [self] in events.sequence != sequence },
                deadline: deadline
            )

            try await prepareForSubmission()
        }
    }

    func throwReadinessFailure() throws(LanguageModelError) -> Never {
        guard let lastNavigationError else {
            throw .sessionNotReady
        }

        throw .requestFailed(lastNavigationError.localizedDescription)
    }

    /// The page may still be rendering its messages once its composer
    /// is ready, so the check is repeated after every change until it
    /// passes or the window elapses.
    func waitForConversation() async throws(LanguageModelError) -> Bool {
        let deadline = Date.now.addingTimeInterval(Double(Floats.conversationVerificationTimeoutSeconds))

        while true {
            if await isConversationIntact() {
                return true
            }

            let sequence = events.sequence
            guard try await events.wait(
                until: { [self] in events.sequence != sequence },
                deadline: deadline
            ) else { return false }
        }
    }
}
