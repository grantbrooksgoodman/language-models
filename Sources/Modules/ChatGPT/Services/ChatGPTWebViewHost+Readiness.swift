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
        let deadline = Date().addingTimeInterval(Double(Floats.challengeAutoResolutionTimeoutSeconds))

        while Date() < deadline {
            try await sleep(for: Floats.readinessPollIntervalSeconds)
            if let state = try? await probePageState(),
               !state.isChallengePresent {
                return
            }
        }

        guard LanguageModels.presentsChallenges else {
            throw .challengeRequired
        }

        try await presentChallenge()
    }

    func shouldReload(
        idleStartDate: Date?,
        nextReloadDate: Date
    ) -> Bool {
        if lastNavigationError != nil {
            return Date() >= nextReloadDate
        }

        guard let idleStartDate else { return false }
        return Date().timeIntervalSince(idleStartDate) >= Double(Floats.readinessReloadIntervalSeconds)
    }

    func throwIfOffline() throws(LanguageModelError) {
        guard let error = lastNavigationError as? URLError,
              [.dataNotAllowed, .internationalRoamingOff, .notConnectedToInternet].contains(error.code) else { return }

        throw .requestFailed(error.localizedDescription)
    }
}

private extension ChatGPTWebViewHost {
    // MARK: - Challenge Helpers

    func concealWebView(
        _ webView: StaticWebView,
        closeButton: UIButton
    ) {
        closeButton.removeFromSuperview()
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
    }

    func makeCloseButton() -> UIButton {
        // The button records its tap as its selected state.
        let closeButton = UIButton(
            type: .close,
            primaryAction: UIAction { action in
                (action.sender as? UIButton)?.isSelected = true
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

        let deadline = Date().addingTimeInterval(Double(Floats.challengePresentationTimeoutSeconds))
        while Date() < deadline,
              !closeButton.isSelected {
            if let state = try? await probePageState(),
               !state.isChallengePresent,
               state.isComposerPresent {
                return
            }

            try await sleep(for: Floats.readinessPollIntervalSeconds)
        }

        throw .challengeRequired
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
