//
//  ChatGPTPageEventService.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Holds the latest page state and the current turn's stream events,
/// and lets the host wait for a condition that an event may satisfy.
/// Every event resumes the waiters, which re-check their conditions;
/// a waiter that sees no event for the fallback interval asks for an
/// on-demand page-state refresh.
@MainActor
final class ChatGPTPageEventService {
    // MARK: - Constants Accessors

    private typealias Floats = Constants.CGFloats

    // MARK: - Types

    private enum WakeReason {
        case cancelled
        case event
        case timeout
    }

    // MARK: - Properties

    /// The on-demand page-state probe used when no event arrives
    /// within the fallback interval.
    var refresh: (@MainActor () async -> ChatGPTPageState?)?

    private(set) var hasStreamStarted = false

    private(set) var isTurnInterrupted = false

    private(set) var lastEventDate = Date.now

    private(set) var lastStreamCompletionDate: Date?

    private(set) var openStreamCount = 0

    private(set) var pageState: ChatGPTPageState?

    /// The number of fallback refreshes, so a waiter can tell that one
    /// happened since it last looked.
    private(set) var refreshCount = 0

    /// The number of events, so a waiter can tell that something
    /// changed since it last looked.
    private(set) var sequence = 0

    private(set) var streamCompletions = [ChatGPTStreamCompletion]()

    private(set) var turnGeneration = 0

    private var waiters = [UUID: CheckedContinuation<WakeReason, Never>]()

    // MARK: - Methods

    func beginTurn() {
        turnGeneration += 1
        isTurnInterrupted = false
        resetStreamState()
    }

    func endTurn() {
        isTurnInterrupted = false
    }

    func interruptTurn() {
        isTurnInterrupted = true
        notify()
    }

    /// Resumes every waiter so it re-checks its condition.
    func notify() {
        lastEventDate = Date.now
        sequence += 1
        for id in waiters.keys {
            resume(
                id,
                with: .event
            )
        }
    }

    /// Records the message, or returns `false` for a stream message of
    /// another turn, which is ignored.
    func receive(_ message: ChatGPTBridgeMessage) -> Bool {
        switch message {
        case let .completed(completion):
            guard completion.generation == turnGeneration else { return false }
            hasStreamStarted = true
            lastStreamCompletionDate = Date.now
            openStreamCount = max(
                0,
                openStreamCount - 1
            )

            streamCompletions.append(completion)

        case let .pageState(state):
            pageState = state

        case let .started(generation):
            guard generation == turnGeneration else { return false }
            hasStreamStarted = true
            openStreamCount += 1
        }

        notify()
        return true
    }

    /// Records a page state read on demand.
    func record(pageState: ChatGPTPageState) {
        self.pageState = pageState
        notify()
    }

    func resetStreamState() {
        hasStreamStarted = false
        lastStreamCompletionDate = nil
        openStreamCount = 0
        streamCompletions = []
        notify()
    }

    /// Returns `true` once `condition` holds, and `false` once the
    /// deadline passes. Throws `cancelled` when the task is cancelled
    /// and `interrupted` when the turn is interrupted.
    func wait(
        until condition: () -> Bool,
        deadline: Date
    ) async throws(LanguageModelError) -> Bool {
        while true {
            guard !isTurnInterrupted else {
                throw .interrupted
            }

            guard !Task.isCancelled else {
                throw .cancelled
            }

            if condition() {
                return true
            }

            guard Date.now < deadline else { return false }

            let refreshDate = lastEventDate.addingTimeInterval(Double(Floats.fallbackRefreshIntervalSeconds))
            let wakeDate = min(
                deadline,
                refreshDate
            )

            switch await sleepUntilEvent(or: wakeDate) {
            case .cancelled:
                throw .cancelled

            case .event:
                continue

            case .timeout:
                if Date.now >= refreshDate {
                    await refreshPageState()
                }
            }
        }
    }

    /// Waits as ``wait(until:deadline:)`` does, throwing `timeoutError`
    /// once the deadline passes.
    func wait(
        until condition: () -> Bool,
        deadline: Date,
        timeoutError: LanguageModelError
    ) async throws(LanguageModelError) {
        guard try await wait(
            until: condition,
            deadline: deadline
        ) else {
            throw timeoutError
        }
    }

    // MARK: - Auxiliary

    private func refreshPageState() async {
        refreshCount += 1
        guard let state = await refresh?() else {
            return notify()
        }

        record(pageState: state)
    }

    private func resume(
        _ id: UUID,
        with reason: WakeReason
    ) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: reason)
    }

    private func sleepUntilEvent(or wakeDate: Date) async -> WakeReason {
        let id = UUID()
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(
                0,
                wakeDate.timeIntervalSinceNow
            )))

            self?.resume(
                id,
                with: .timeout
            )
        }

        defer { timer.cancel() }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume(
                    id,
                    with: .cancelled
                )
            }
        }
    }
}
