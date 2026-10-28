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
    // MARK: - Properties

    var isPageStreaming: Bool {
        events.pageState?.isStreaming == true
    }

    // MARK: - Methods

    func completedRenderedText(
        messageID: String?,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String? {
        let deadline = Date.now.addingTimeInterval(Double(Floats.renderedReplyTimeoutSeconds))
        var probedRefreshCount = -1

        while true {
            // The page is read once it shows its last reply complete,
            // and after every fallback refresh.
            if events.pageState?.isLastAssistantMessageComplete == true || events.refreshCount != probedRefreshCount {
                probedRefreshCount = events.refreshCount
                if let renderedReply = await probeRenderedReply(
                    messageID: messageID,
                    since: transcript
                ),
                    renderedReply.isComplete,
                    !renderedReply.text.isEmpty {
                    logLinks(in: renderedReply)
                    return renderedReply.text
                }
            }

            let sequence = events.sequence
            guard try await events.wait(
                until: { [self] in events.sequence != sequence },
                deadline: deadline
            ) else { return nil }
        }
    }

    /// Whether the turn has produced no further stream since the last
    /// one completed. A stream that is still open keeps the turn in
    /// flight; otherwise, the turn is in flight only while the page
    /// shows it so, and for no longer than the follow-up window.
    func hasTurnSettled(
        since lastStreamCompletionDate: Date
    ) -> Bool {
        let elapsed = Date.now.timeIntervalSince(lastStreamCompletionDate)
        guard elapsed >= Double(Floats.streamSettleIntervalSeconds),
              events.openStreamCount == 0 else { return false }

        guard elapsed < Double(Floats.followUpStreamTimeoutSeconds) else { return true }
        return !isPageStreaming
    }

    /// Whether the page shows a reply other than the one that was
    /// last at the baseline, complete.
    func isReplyShown(since transcript: ChatGPTTranscriptState?) -> Bool {
        guard let state = events.pageState,
              let messageID = state.lastAssistantMessageID else { return false }
        return state.isLastAssistantMessageComplete && messageID != transcript?.lastAssistantMessageID
    }

    func nextReplyWakeDate(
        deadline: Date,
        inFlightDeadline: Date,
        streamStartDeadline: Date
    ) -> Date {
        var candidates = [inFlightDeadline]
        if let lastStreamCompletionDate = events.lastStreamCompletionDate {
            candidates.append(lastStreamCompletionDate.addingTimeInterval(Double(Floats.streamSettleIntervalSeconds)))
            candidates.append(lastStreamCompletionDate.addingTimeInterval(Double(Floats.followUpStreamTimeoutSeconds)))
        } else if !events.hasStreamStarted {
            candidates.append(streamStartDeadline)
        }

        candidates.append(deadline)
        let now = Date.now
        return candidates.filter { $0 > now }.min() ?? inFlightDeadline
    }

    func renderedReplyText(
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> String? {
        let renderedReply = await probeRenderedReply(
            messageID: nil,
            since: transcript
        )

        guard let renderedReply,
              renderedReply.isComplete,
              !renderedReply.text.isEmpty,
              !isPageStreaming else { return nil }

        await logDiagnostics("No conversation stream was recognized; the reply was read from the page.")
        logLinks(in: renderedReply)
        return renderedReply.text
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
        guard let unsanitized = try await unsanitizedReplyText(
            from: completion,
            since: transcript
        ) else { return nil }

        // Only the page and the stream's fallback rendering show a
        // citation as its label.
        let text = unsanitized.isLabeled
            ? unsanitized.text.strippingCitationLabels(completion.citationLabels)
            : unsanitized.text
        return text.isEmpty ? nil : text
    }

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
        // to the in-flight limit. The wait resumes on every page or
        // stream event, and at the next deadline.
        let startDate = Date.now
        let deadline = startDate.addingTimeInterval(Double(Floats.responseTimeoutSeconds))
        let inFlightDeadline = startDate.addingTimeInterval(Double(Floats.inFlightResponseTimeoutSeconds))
        let streamStartDeadline = startDate.addingTimeInterval(Double(Floats.streamStartTimeoutSeconds))
        var probedRefreshCount = events.refreshCount
        var probedSequence = -1

        while Date.now < inFlightDeadline {
            if let lastStreamCompletionDate = events.lastStreamCompletionDate {
                if hasTurnSettled(since: lastStreamCompletionDate) {
                    log(
                        "The turn settled with \(events.streamCompletions.count) stream(s).",
                        level: .debug
                    )

                    return try await replyText(
                        from: events.streamCompletions,
                        since: transcript
                    )
                }
            } else if !events.hasStreamStarted {
                // The page is read only once it shows a complete reply,
                // or after a fallback refresh.
                if events.sequence != probedSequence,
                   isReplyShown(since: transcript) || events.refreshCount != probedRefreshCount {
                    probedRefreshCount = events.refreshCount
                    probedSequence = events.sequence
                    if let text = try await renderedReplyText(since: transcript) {
                        return text
                    }
                }

                if Date.now >= streamStartDeadline,
                   !isReplyShown(since: transcript),
                   !isPageStreaming {
                    await logDiagnostics("Neither a conversation stream nor a reply appeared.")
                    throw .timedOut
                }
            }

            if Date.now >= deadline,
               !isPageStreaming {
                break
            }

            let sequence = events.sequence
            _ = try await events.wait(
                until: { [self] in events.sequence != sequence },
                deadline: nextReplyWakeDate(
                    deadline: deadline,
                    inFlightDeadline: inFlightDeadline,
                    streamStartDeadline: streamStartDeadline
                )
            )
        }

        await logDiagnostics("The reply did not complete in time.")
        throw .timedOut
    }

    func unsanitizedReplyText(
        from completion: ChatGPTStreamCompletion,
        since transcript: ChatGPTTranscriptState?
    ) async throws(LanguageModelError) -> (text: String, isLabeled: Bool)? {
        guard completion.fullText.isEmpty || completion.isFullTextIncomplete else {
            return (completion.fullText, completion.textSource == .fallbackMarkdown)
        }

        if let renderedText = try await completedRenderedText(
            messageID: completion.messageID,
            since: transcript
        ) {
            if completion.fullText.isEmpty {
                await logDiagnostics("The conversation stream yielded no text; the reply was read from the page.")
            }

            return (renderedText, true)
        }

        guard !completion.fullText.isEmpty else { return nil }

        await logDiagnostics("The reply's omitted content could not be read from the page.")
        return (completion.fullText, true)
    }
}

private extension String {
    // MARK: - Properties

    var endsWithSentencePunctuation: Bool {
        guard let last = trimmingTrailingWhitespace.last else { return false }
        return ".!?)]".contains(last)
    }

    var isCodeFence: Bool {
        let line = trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    var trimmingTrailingWhitespace: String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }

    // MARK: - Methods

    func isLabelOnlyOrPrecededByWhitespace(before suffix: String) -> Bool {
        guard count > suffix.count else { return true }
        return self[index(endIndex, offsetBy: -suffix.count - 1)].isWhitespace
    }

    /// Removes the run of source citations rendered at the end of any
    /// line – labels among `labels` and "+N" sources badges, each
    /// preceded by whitespace – when the run is the whole line or
    /// follows sentence-ending punctuation. Lines in fenced code
    /// blocks are kept as they are.
    func strippingCitationLabels(_ labels: [String]) -> String {
        guard !labels.isEmpty else { return self }

        let labels = labels.sorted { $0.count > $1.count }
        var isInCodeBlock = false
        return components(separatedBy: "\n").map { line in
            if line.isCodeFence {
                isInCodeBlock.toggle()
                return line
            }

            return isInCodeBlock ? line : line.strippingTrailingCitations(labels)
        }.joined(separator: "\n")
    }

    func strippingTrailingCitations(_ labels: [String]) -> String {
        var line = trimmingTrailingWhitespace
        var hasCitations = false

        while true {
            if let badgeRange = line.range(
                of: #"\s+\+\d+$"#,
                options: .regularExpression
            ) {
                line.removeSubrange(badgeRange)
                hasCitations = true
                continue
            }

            guard let label = labels.first(where: { line.hasSuffix($0) && line.isLabelOnlyOrPrecededByWhitespace(before: $0) }) else { break }
            line.removeLast(label.count)
            line = line.trimmingTrailingWhitespace
            hasCitations = true
        }

        guard hasCitations,
              line.isEmpty || line.endsWithSentencePunctuation else { return self }

        return line
    }
}
