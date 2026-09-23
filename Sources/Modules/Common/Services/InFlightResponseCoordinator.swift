//
//  InFlightResponseCoordinator.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Deduplicates concurrent response requests: while a response for a given
/// prompt is in flight, subsequent requests for the same work await the
/// existing task instead of starting their own.
actor InFlightResponseCoordinator {
    // MARK: - Properties

    static let shared = InFlightResponseCoordinator()

    private var inFlightTasks = [String: Task<String, any Error>]()

    // MARK: - Init

    private init() {}

    // MARK: - Task Coordination

    func task(
        forKey key: String,
        operation: @escaping @Sendable () async throws -> String
    ) -> Task<String, any Error> {
        if let inFlightTask = inFlightTasks[key] { return inFlightTask }

        let responseTask = Task { try await operation() }
        inFlightTasks[key] = responseTask

        Task {
            _ = try? await responseTask.value
            clearTask(forKey: key)
        }

        return responseTask
    }

    // MARK: - Auxiliary

    private func clearTask(forKey key: String) {
        inFlightTasks[key] = nil
    }
}
