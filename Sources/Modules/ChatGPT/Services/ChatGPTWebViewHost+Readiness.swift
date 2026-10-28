//
//  ChatGPTWebViewHost+Readiness.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation
import UIKit

extension ChatGPTWebViewHost {
    // MARK: - Constants Accessors

    private typealias Floats = Constants.CGFloats
    private typealias Ints = Constants.Ints
    private typealias Strings = Constants.Strings

    // MARK: - Methods

    func isNavigationCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return switch error.domain {
        case NSURLErrorDomain: error.code == NSURLErrorCancelled
        case Strings.webKitErrorDomain: error.code == Ints.frameLoadInterruptedErrorCode
        default: false
        }
    }

    /// The challenge is given time to clear on its own before it is
    /// presented for the user to solve, when presenting is enabled.
    func resolveChallenge() async throws(LanguageModelError) {
        let hasCleared = try await events.wait(
            until: { [self] in events.pageState?.isChallengePresent == false },
            deadline: Date.now.addingTimeInterval(Double(Floats.challengeAutoResolutionTimeoutSeconds))
        )

        guard !hasCleared else {
            return log("The challenge cleared on its own.")
        }

        guard LanguageModels.presentsChallenges else {
            log(
                "The challenge did not clear, and presenting is off.",
                level: .error
            )

            throw .challengeRequired
        }

        log("Presenting the challenge.")
        try await presentChallenge()
    }

    /// Whether the page is reloaded now: it is when its navigation
    /// failed, or when it has finished loading and sat idle – with no
    /// change, nothing streaming, and no challenge – for the full
    /// reload interval.
    func shouldReload() -> Bool {
        guard lastNavigationError == nil else { return true }

        guard !isLoading,
              events.pageState?.isStreaming != true,
              events.pageState?.isChallengePresent != true else { return false }

        return Date.now.timeIntervalSince(events.lastEventDate) >= Double(Floats.readinessReloadIntervalSeconds)
    }

    func throwIfOffline() throws(LanguageModelError) {
        guard let error = lastNavigationError as? URLError,
              [.dataNotAllowed, .internationalRoamingOff, .notConnectedToInternet].contains(error.code) else { return }

        log(
            "The device is offline: \(error.localizedDescription)",
            level: .error
        )

        throw .requestFailed(error.localizedDescription)
    }
}

private extension ChatGPTWebViewHost {
    func concealWebView(
        _ webView: StaticWebView,
        closeButton: UIButton
    ) {
        closeButton.removeFromSuperview()
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
    }

    func makeCloseButton() -> UIButton {
        // The button records its tap as its selected state, and wakes
        // the wait on it.
        let closeButton = UIButton(
            type: .close,
            primaryAction: UIAction { [weak self] action in
                (action.sender as? UIButton)?.isSelected = true
                self?.events.notify()
            }
        )

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        return closeButton
    }

    func presentChallenge() async throws(LanguageModelError) {
        guard let webView,
              let window = UIApplication.shared.mainWindow else {
            throw .challengeRequired
        }

        let closeButton = makeCloseButton()
        revealWebView(
            webView,
            in: window,
            closeButton: closeButton
        )

        defer {
            concealWebView(
                webView,
                closeButton: closeButton
            )
        }

        let hasCleared = try await events.wait(
            until: { [self] in
                guard !closeButton.isSelected,
                      let state = events.pageState else { return closeButton.isSelected }
                return !state.isChallengePresent && state.isComposerPresent
            },
            deadline: Date.now.addingTimeInterval(Double(Floats.challengePresentationTimeoutSeconds))
        )

        guard hasCleared,
              !closeButton.isSelected else {
            log(
                closeButton.isSelected ? "The challenge was closed by the user." : "The challenge was not solved in time.",
                level: .error
            )

            throw .challengeRequired
        }

        log("The challenge was solved.")
    }

    func revealWebView(
        _ webView: StaticWebView,
        in window: UIWindow,
        closeButton: UIButton
    ) {
        webView.frame = window.bounds
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        window.bringSubviewToFront(webView)

        webView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: webView.safeAreaLayoutGuide.topAnchor,
                constant: Floats.challengeCloseButtonInset
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: webView.safeAreaLayoutGuide.trailingAnchor,
                constant: -Floats.challengeCloseButtonInset
            ),
        ])
    }
}
