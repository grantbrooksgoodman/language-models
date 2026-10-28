//
//  InFlightResponseCoordinator.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Deduplicates concurrent response requests: while a response for a
/// given prompt is in flight, subsequent requests for the same work
/// await the existing task instead of starting their own. Each caller
/// waits through its own continuation, so cancelling a caller resumes
/// only that caller with `.cancelled`. The task is cancelled once no
/// caller awaits it.
actor InFlightResponseCoordinator {
    // MARK: - Type Aliases

    typealias ResponseOperation = @Sendable () async throws(LanguageModelError) -> String

    private typealias ResponseContinuation = CheckedContinuation<ResponseResult, Never>
    private typealias ResponseResult = Result<String, LanguageModelError>

    // MARK: - Types

    private struct InFlightOperation {
        let id: UUID
        let task: Task<Void, Never>

        var waiters = [UUID: ResponseContinuation]()
    }

    // MARK: - Properties

    static let shared = InFlightResponseCoordinator()

    private var operations = [String: InFlightOperation]()

    // MARK: - Init

    private init() {}

    // MARK: - Methods

    func response(
        forKey key: String,
        operation: @escaping ResponseOperation
    ) async throws(LanguageModelError) -> String {
        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                addWaiter(
                    continuation,
                    id: waiterID,
                    forKey: key,
                    operation: operation
                )
            }
        } onCancel: {
            Task {
                await self.removeWaiter(
                    id: waiterID,
                    forKey: key
                )
            }
        }

        return try result.get()
    }

    // MARK: - Auxiliary

    private func addWaiter(
        _ continuation: ResponseContinuation,
        id: UUID,
        forKey key: String,
        operation: @escaping ResponseOperation
    ) {
        guard !Task.isCancelled else {
            return continuation.resume(returning: .failure(.cancelled))
        }

        if operations[key] == nil {
            operations[key] = makeOperation(
                forKey: key,
                running: operation
            )
        }

        operations[key]?.waiters[id] = continuation
    }

    private func finishOperation(
        id: UUID,
        forKey key: String,
        with result: ResponseResult
    ) {
        guard let operation = operations[key],
              operation.id == id else { return }

        operations[key] = nil
        for waiter in operation.waiters.values {
            waiter.resume(returning: result)
        }
    }

    private func makeOperation(
        forKey key: String,
        running operation: @escaping ResponseOperation
    ) -> InFlightOperation {
        let id = UUID()
        let task = Task {
            let result: ResponseResult
            do throws(LanguageModelError) {
                result = try await .success(operation())
            } catch {
                result = .failure(error)
            }

            finishOperation(
                id: id,
                forKey: key,
                with: result
            )
        }

        return .init(
            id: id,
            task: task
        )
    }

    private func removeWaiter(
        id: UUID,
        forKey key: String
    ) {
        guard var operation = operations[key],
              let waiter = operation.waiters.removeValue(forKey: id) else { return }

        waiter.resume(returning: .failure(.cancelled))

        guard operation.waiters.isEmpty else {
            operations[key] = operation
            return
        }

        operations[key] = nil
        operation.task.cancel()
    }
}
