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
        // A turn may span several conversation streams – one per
        // message, with a pause between while the model works – so
        // the reply is read once the turn has settled: every stream
        // has completed, the page no longer shows the turn in flight,
        // and no follow-up stream has begun. The reply is read from
        // the streams, and from the page itself when a stream yields
        // no text, omits part of its message, or is never recognized.
        // This throws early once the stream-start window elapses with
        // no stream, no reply, and no turn in flight. The response
        // window extends while the page shows the turn in flight, up
        // to the in-flight limit.
        let startDate = Date()
        let deadline = startDate.addingTimeInterval(Double(Floats.responseTimeoutSeconds))
        let inFlightDeadline = startDate.addingTimeInterval(Double(Floats.inFlightResponseTimeoutSeconds))
        let streamStartDeadline = startDate.addingTimeInterval(Double(Floats.streamStartTimeoutSeconds))

        while Date() < inFlightDeadline {
            if let lastStreamCompletionDate {
                if await hasTurnSettled(since: lastStreamCompletionDate) {
                    return try await replyText(
                        from: streamCompletions,
                        since: transcript
                    )
                }
            } else if !hasStreamStarted {
                let renderedReply = await probeRenderedReply(
                    messageID: nil,
                    since: transcript
                )

                if let renderedReply,
                   renderedReply.isComplete,
                   !renderedReply.text.isEmpty,
                   await !isTurnInFlight() {
                    await logDiagnostics("No conversation stream was recognized; the reply was read from the page.")
                    logLinks(in: renderedReply)
                    return renderedReply.text
                }

                if Date() >= streamStartDeadline,
                   renderedReply?.messageID == nil,
                   await !isTurnInFlight() {
                    await logDiagnostics("Neither a conversation stream nor a reply appeared.")
                    throw .emptyResponse
                }
            }

            if Date() >= deadline,
               await !isTurnInFlight() {
                break
            }

            try await sleep(for: Floats.turnPollIntervalSeconds)
        }

        await logDiagnostics("The reply did not complete in time.")
        throw .emptyResponse
    }

    func completedRenderedText(
        messageID: String?,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String? {
        let deadline = Date().addingTimeInterval(Double(Floats.renderedReplyTimeoutSeconds))

        repeat {
            if let renderedReply = await probeRenderedReply(
                messageID: messageID,
                since: transcript
            ),
                renderedReply.isComplete,
                !renderedReply.text.isEmpty {
                logLinks(in: renderedReply)
                return renderedReply.text
            }

            try await sleep(for: Floats.turnPollIntervalSeconds)
        } while Date() < deadline

        return nil
    }

    /// Whether the turn has produced no further stream since the last
    /// one completed. A stream that is still open keeps the turn in
    /// flight; otherwise, the turn is in flight only while the page
    /// shows it so, and for no longer than the follow-up window.
    func hasTurnSettled(
        since lastStreamCompletionDate: Date
    ) async -> Bool {
        let elapsed = Date().timeIntervalSince(lastStreamCompletionDate)
        guard elapsed >= Double(Floats.streamSettleIntervalSeconds),
              openStreamCount == 0 else { return false }

        guard elapsed < Double(Floats.followUpStreamTimeoutSeconds) else { return true }
        return await !isTurnInFlight()
    }

    func isTurnInFlight() async -> Bool {
        await (try? probePageState())?.isStreaming == true
    }

    func replyText(
        from completions: [ChatGPTStreamCompletion],
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String {
        // The latest completion of each message supersedes the others.
        var completedMessageIDs = Set<String>()
        var texts = [String]()

        for completion in completions.reversed() {
            if let messageID = completion.messageID,
               !completedMessageIDs.insert(messageID).inserted {
                continue
            }

            if let text = try await replyText(
                from: completion,
                since: transcript
            ),
                !texts.contains(text) {
                texts.insert(
                    text,
                    at: 0
                )
            }
        }

        guard !texts.isEmpty else {
            await logDiagnostics("The conversation stream yielded no text, and the page showed no reply.")
            throw .emptyResponse
        }

        return texts.joined(separator: "\n\n")
    }

    func replyText(
        from completion: ChatGPTStreamCompletion,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String? {
        guard let text = try await unsanitizedReplyText(
            from: completion,
            since: transcript
        )?.strippingCitationLabels(completion.citationLabels),
            !text.isEmpty else { return nil }

        return text
    }

    func unsanitizedReplyText(
        from completion: ChatGPTStreamCompletion,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String? {
        guard completion.fullText.isEmpty || completion.isFullTextIncomplete else {
            return completion.fullText
        }

        if let renderedText = try await completedRenderedText(
            messageID: completion.messageID,
            since: transcript
        ) {
            if completion.fullText.isEmpty {
                await logDiagnostics("The conversation stream yielded no text; the reply was read from the page.")
            }

            return renderedText
        }

        guard !completion.fullText.isEmpty else { return nil }

        await logDiagnostics("The reply's omitted content could not be read from the page.")
        return completion.fullText
    }
}

private extension String {
    /// Removes a source citation rendered at the end of any line – a
    /// label among `labels`, or a "+N" sources badge – repeatedly, so
    /// a run of citations is removed. A label elsewhere in a line is
    /// kept.
    func strippingCitationLabels(_ labels: [String]) -> String {
        guard !labels.isEmpty else { return self }

        let labels = labels.sorted { $0.count > $1.count }
        return components(separatedBy: "\n").map { line in
            var line = line.trimmingTrailingWhitespace
            while true {
                if let badgeRange = line.range(
                    of: #"\s*\+\d+$"#,
                    options: .regularExpression
                ) {
                    line.removeSubrange(badgeRange)
                    continue
                }

                guard let label = labels.first(where: { line.hasSuffix($0) && line.isLabelOnlyOrPrecededByWhitespace(before: $0) }) else { break }
                line.removeLast(label.count)
                line = line.trimmingTrailingWhitespace
            }

            return line
        }.joined(separator: "\n")
    }

    var trimmingTrailingWhitespace: String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }

    func isLabelOnlyOrPrecededByWhitespace(before suffix: String) -> Bool {
        guard count > suffix.count else { return true }
        return self[index(endIndex, offsetBy: -suffix.count - 1)].isWhitespace
    }
}
