//
//  ChatGPTScriptResources.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Loads the injected scripts from the package's `JavaScript` resource
/// directory, once each, composing them and substituting their
/// placeholders as `manifest.json` describes.
@MainActor
enum ChatGPTScriptResources {
    // MARK: - Constants Accessors

    private typealias Ints = Constants.Ints
    private typealias Strings = Constants.Strings

    // MARK: - Properties

    private static let directory = "JavaScript"
    private static let fileExtension = "js"
    private static let manifest = loadManifest()
    private static let manifestName = "manifest"
    private static let placeholderValues = [
        "bridgeMessageHandlerName": Strings.bridgeMessageHandlerName,
        "pageStatePushIntervalMilliseconds": String(Ints.pageStatePushIntervalMilliseconds),
    ]

    private static var cache = [String: String]()

    // MARK: - Methods

    static func arguments(for script: ChatGPTScript) -> [String] {
        manifest?.scripts[script.name]?.arguments ?? []
    }

    static func source(for script: ChatGPTScript) -> String? {
        if let cached = cache[script.name] {
            return cached
        }

        guard let source = compose(script.name) else { return nil }
        cache[script.name] = source
        return source
    }

    // MARK: - Auxiliary

    private static func compose(_ name: String) -> String? {
        guard let fragments = manifest?.compositions[name] else {
            return loadFile(name)
        }

        var sources = [String]()
        for fragment in fragments {
            guard let source = loadFile(fragment) else { return nil }
            sources.append(source)
        }

        return sources.joined(separator: "\n\n")
    }

    private static func loadFile(_ name: String) -> String? {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: directory
        ),
            let contents = try? String(
                contentsOf: url,
                encoding: .utf8
            ) else {
            reportMissingResource(named: "\(name).\(fileExtension)")
            return nil
        }

        return substitutingPlaceholders(in: contents)
    }

    private static func loadManifest() -> ChatGPTScriptManifest? {
        guard let url = Bundle.module.url(
            forResource: manifestName,
            withExtension: "json",
            subdirectory: directory
        ),
            let data = try? Data(contentsOf: url),
            let manifest = try? JSONDecoder().decode(
                ChatGPTScriptManifest.self,
                from: data
            ) else {
            reportMissingResource(named: "\(manifestName).json")
            return nil
        }

        return manifest
    }

    private static func reportMissingResource(named name: String) {
        assertionFailure("The script resource \(name) is missing or unreadable.")
        LoggingService.log(
            "The script resource \(name) is missing or unreadable.",
            level: .error,
            category: Strings.loggerCategory
        )
    }

    private static func substitutingPlaceholders(in source: String) -> String {
        var source = source
        for placeholder in manifest?.placeholders ?? [] {
            guard let value = placeholderValues[placeholder] else { continue }
            source = source.replacingOccurrences(
                of: "{{\(placeholder)}}",
                with: value
            )
        }

        return source
    }
}
