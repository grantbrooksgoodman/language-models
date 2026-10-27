//
//  ChatGPTWebViewHost+Reply.swift
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

    func reply(
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String {
        try await unsanitizedReply(since: transcript)
            .replacingOccurrences(
                of: Constants.Strings.citationMarkerPattern,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Reply Helpers

    func unsanitizedReply(
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String {
        // The reply is read from the intercepted conversation stream, and
        // from the page itself when the stream yields no text, omits part
        // of the reply, or is never recognized. This throws early once
        // the stream-start window elapses with no stream, no reply, and
        // no turn in flight.
        let startDate = Date()
        let deadline = startDate.addingTimeInterval(Double(Floats.responseTimeoutSeconds))
        let streamStartDeadline = startDate.addingTimeInterval(Double(Floats.streamStartTimeoutSeconds))

        while Date() < deadline {
            if let streamCompletion {
                return try await replyText(
                    from: streamCompletion,
                    since: transcript
                )
            }

            if !hasStreamStarted {
                let renderedReply = await probeRenderedReply(
                    messageID: nil,
                    since: transcript
                )

                if let renderedReply,
                   renderedReply.isComplete,
                   !renderedReply.text.isEmpty {
                    await logDiagnostics("No conversation stream was recognized; the reply was read from the page.")
                    return renderedReply.text
                }

                if Date() >= streamStartDeadline,
                   renderedReply?.messageID == nil,
                   await (try? probePageState())?.isStreaming != true {
                    await logDiagnostics("Neither a conversation stream nor a reply appeared.")
                    throw .emptyResponse
                }
            }

            try? await Task.sleep(for: .seconds(Double(Floats.turnPollIntervalSeconds)))
        }

        await logDiagnostics("The reply did not complete in time.")
        throw .emptyResponse
    }

    func completedRenderedText(
        messageID: String?,
        since transcript: ChatGPTTranscriptState?
    ) async -> String? {
        let deadline = Date().addingTimeInterval(Double(Floats.renderedReplyTimeoutSeconds))

        repeat {
            if let renderedReply = await probeRenderedReply(
                messageID: messageID,
                since: transcript
            ),
                renderedReply.isComplete,
                !renderedReply.text.isEmpty {
                return renderedReply.text
            }

            try? await Task.sleep(for: .seconds(Double(Floats.turnPollIntervalSeconds)))
        } while Date() < deadline

        return nil
    }

    func replyText(
        from completion: ChatGPTStreamCompletion,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String {
        guard completion.fullText.isEmpty || completion.isFullTextIncomplete else {
            return completion.fullText
        }

        if let renderedText = await completedRenderedText(
            messageID: completion.messageID,
            since: transcript
        ) {
            if completion.fullText.isEmpty {
                await logDiagnostics("The conversation stream yielded no text; the reply was read from the page.")
            }

            return renderedText
        }

        guard !completion.fullText.isEmpty else {
            await logDiagnostics("The conversation stream yielded no text, and the page showed no reply.")
            throw .emptyResponse
        }

        await logDiagnostics("The reply's omitted content could not be read from the page.")
        return completion.fullText
    }
}
