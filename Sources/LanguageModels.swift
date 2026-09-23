/// The configuration entry point for the language model system.
///
/// Use `LanguageModels` to register the delegates a
/// ``LanguageModelSession`` needs. Register a Gemini API key delegate
/// once, early in the app's lifecycle, to enable the Gemini provider:
///
/// ```swift
/// LanguageModels.registerGeminiAPIKeyDelegate(APIKeyProvider())
/// ```
public enum LanguageModels {
    // MARK: - Properties

    /// The registered Gemini API key delegate, or `nil` if none has
    /// been registered.
    @MainActor
    private(set) static var geminiAPIKeyDelegate: GeminiAPIKeyDelegate?

    // MARK: - Methods

    /// Registers the delegate that supplies the Gemini API key.
    ///
    /// Calling this method replaces any previously registered delegate.
    ///
    /// - Parameter delegate: The delegate that supplies the API key.
    @MainActor
    public static func registerGeminiAPIKeyDelegate(
        _ delegate: GeminiAPIKeyDelegate
    ) {
        geminiAPIKeyDelegate = delegate
    }
}
