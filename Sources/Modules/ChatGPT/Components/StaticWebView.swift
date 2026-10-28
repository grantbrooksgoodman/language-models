//
//  StaticWebView.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import ObjectiveC
import UIKit

@preconcurrency import WebKit

/// A web view that never takes keyboard focus.
///
/// WebKit's keyboard input is handled by the web view's private
/// content view, which becomes first responder when the page focuses
/// an editable element – including from script. The content view is
/// given a per-instance subclass that refuses first responder status,
/// so driving the page never resigns the host app's own first
/// responder.
final class StaticWebView: WKWebView {
    // MARK: - Constants Accessors

    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private static let contentViewClassNamePrefix = "WKContentView"
    private static let refusingClassNamePrefix = "LanguageModels_NonFirstResponder_"

    private var hasRefusedContentViewFirstResponder = false

    // MARK: - Init

    override init(
        frame: CGRect,
        configuration: WKWebViewConfiguration
    ) {
        super.init(
            frame: frame,
            configuration: configuration
        )

        refuseContentViewFirstResponder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Overrides

    override var canBecomeFirstResponder: Bool {
        false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refuseContentViewFirstResponder()
    }

    // MARK: - Auxiliary

    private func logMissingContentView() {
        LoggingService.log(
            "No \(Self.contentViewClassNamePrefix) content view was found; its first responder status was not refused.",
            level: .error,
            category: Strings.loggerCategory
        )
    }

    private func refuseContentViewFirstResponder() {
        guard !hasRefusedContentViewFirstResponder else { return }

        guard let contentView = scrollView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).hasPrefix(Self.contentViewClassNamePrefix)
        }) else {
            return logMissingContentView()
        }

        let originalClass: AnyClass = type(of: contentView)
        let refusingClassName = Self.refusingClassNamePrefix + NSStringFromClass(originalClass)

        let refusingClass: AnyClass
        if let existingClass = NSClassFromString(refusingClassName) {
            refusingClass = existingClass
        } else {
            guard let createdClass = objc_allocateClassPair(
                originalClass,
                refusingClassName,
                0
            ) else { return }

            let canBecomeFirstResponder: @convention(block) (AnyObject) -> Bool = { _ in false }
            class_addMethod(
                createdClass,
                #selector(getter: UIResponder.canBecomeFirstResponder),
                imp_implementationWithBlock(canBecomeFirstResponder),
                "B@:"
            )

            objc_registerClassPair(createdClass)
            refusingClass = createdClass
        }

        object_setClass(
            contentView,
            refusingClass
        )

        hasRefusedContentViewFirstResponder = true
    }
}
