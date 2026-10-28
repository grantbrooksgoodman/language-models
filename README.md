# LanguageModels

A framework for sending prompts to a large language model and receiving its reply behind a single, provider-agnostic API.

LanguageModels supports two backends: **Gemini**, called directly through its HTTP API, and **ChatGPT**, driven through the real ChatGPT web app inside a hidden web view. A [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) created without a provider uses Gemini for its low latency and automatically falls back to ChatGPT if the Gemini request fails, then keeps the conversation on whichever provider replied; you can also target either backend explicitly.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Started](#getting-started)
  - [Register a Gemini API Key](#register-a-gemini-api-key)
  - [Send a Prompt](#send-a-prompt)
  - [Choose a Provider](#choose-a-provider)
  - [Continue or Reset a Conversation](#continue-or-reset-a-conversation)
  - [Prewarm](#prewarm)
- [Providers](#providers)
- [Configuration](#configuration)
  - [GeminiConfig](#geminiconfig)
  - [GeminiModel](#geminimodel)
- [Errors](#errors)
- [Concurrency](#concurrency)

---

## Overview

| Type | Description |
| --- | --- |
| [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) | A conversation with a language model. Send a prompt and await the reply. |
| [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift) | Selects the backend a session uses: ChatGPT or Gemini. |
| [`LanguageModelError`](Sources/Modules/Common/Models/LanguageModelError.swift) | An error thrown while producing a reply. |
| [`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift) | Configures a Gemini request: the model and an optional system message. |
| [`GeminiModel`](Sources/Modules/Gemini/Models/Public/GeminiModel.swift) | The Gemini model that answers the prompt. |
| [`GeminiAPIKeyDelegate`](Sources/Modules/Common/Protocols/Public/GeminiAPIKeyDelegate.swift) | Supplies the Gemini API key. |
| [`LanguageModels`](Sources/LanguageModels.swift) | The configuration entry point; register the Gemini API key delegate here. |

---

## Requirements

| Platform | Minimum Version |
| --- | --- |
| iOS | 18.0 |

LanguageModels has no external dependencies.

---

## Installation

LanguageModels is distributed as a Swift package. Add it to your project using [Swift Package Manager](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/).

---

## Getting Started

### Register a Gemini API Key

The Gemini backend authenticates each request with an API key. Supply one by conforming a type to [`GeminiAPIKeyDelegate`](Sources/Modules/Common/Protocols/Public/GeminiAPIKeyDelegate.swift) and registering it through [`LanguageModels`](Sources/LanguageModels.swift), once, early in your app's lifecycle:

```swift
import LanguageModels

struct APIKeyProvider: GeminiAPIKeyDelegate {
    let apiKey = "YOUR_GEMINI_API_KEY"
}

LanguageModels.registerGeminiAPIKeyDelegate(APIKeyProvider())
```

The ChatGPT backend requires no API key, so you may skip this step if you only use ChatGPT. Note that the default session (below) falls back to ChatGPT, so it still works before a key is registered.

### Send a Prompt

Create a [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) and call `response(to:)`. With no provider specified, the first turn of a conversation tries Gemini, then ChatGPT:

```swift
import LanguageModels

let session = LanguageModelSession()

do {
    let reply = try await session.response(to: "Echo BANANA and nothing else.")
    print(reply) // BANANA
} catch {
    print(error.localizedDescription)
}
```

The prompt must not be empty after trimming whitespace; otherwise the call throws [`LanguageModelError`](Sources/Modules/Common/Models/LanguageModelError.swift)`.invalidPrompt`. The call runs once the session's earlier calls have finished.

### Choose a Provider

Pass a [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift) to target one backend, with no fallback. Either backend keeps the conversation's context across turns:

```swift
// Gemini only, steered by a system message.
let gemini = LanguageModelSession(
    .gemini(config: .init(systemMessage: "Answer in one word."))
)

// ChatGPT only.
let chatGPT = LanguageModelSession(.chatGPT)
```

### Continue or Reset a Conversation

A session is a conversation: each call to `response(to:)` continues from the previous turns, so the model retains context. For a session created with `LanguageModelSession()`, the provider that replies to the first turn answers every later turn of the conversation, with no fallback.

```swift
let session = LanguageModelSession()

_ = try await session.response(to: "My name is Grant.")
let reply = try await session.response(to: "What's my name?") // Grant
```

Call `startNewConversation()` to discard the context and begin fresh. For a session created with `LanguageModelSession()`, the next turn tries Gemini, then ChatGPT, again:

```swift
try await session.startNewConversation()
```

### Prewarm

Call `prewarm()` once a prompt is imminent to reduce the latency of the first reply. This loads the ChatGPT web view and caches its assets ahead of time (it is a no-op for Gemini). It is safe to call repeatedly and never throws:

```swift
let session = LanguageModelSession()
session.prewarm()
```

---

## Providers

A session routes each prompt to one or both of the following backends, selected by [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift):

| Provider | How it works | API key | Notes |
| --- | --- | --- | --- |
| `.gemini(config:)` | Calls the Gemini HTTP API directly. | Required | Low latency. Configure it with [`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift). |
| `.chatGPT` | Drives the ChatGPT web app in a hidden web view. | Not required | No account needed. Higher latency, and best-effort: it may surface a verification challenge. A reply that ChatGPT delivers as several messages is returned as one, with its messages separated by blank lines. |

When you construct a session with `LanguageModelSession()`, the first turn of a conversation tries `.gemini(config:)` (with a default configuration) and falls back to `.chatGPT`. The provider that replies to the first turn answers every later turn of the conversation, with no fallback. If that provider fails, the call throws, and the next turn goes to the same provider. If it throws `conversationLost`, the next turn starts over with Gemini. When you construct a session with an explicit provider, only that provider is used – there is no fallback.

Each session is backed by its own resources, so multiple sessions run independently and concurrently. ChatGPT-backed sessions share a single browser session (cookies and cache). Once a session prewarms or sends a prompt to ChatGPT, it holds a hidden web view until it is released.

---

## Configuration

### GeminiConfig

[`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift) configures a Gemini request. Both parameters have defaults:

```swift
// Defaults: the flash25 model, no system message.
let config = GeminiConfig()

// A specific model and a system message sent alongside every prompt.
let config = GeminiConfig(
    model: .flash20,
    systemMessage: "You are a terse assistant."
)

let session = LanguageModelSession(.gemini(config: config))
```

The `systemMessage`, when provided, steers the model's response and is sent alongside the user prompt passed to `response(to:)`.

### GeminiModel

[`GeminiModel`](Sources/Modules/Gemini/Models/Public/GeminiModel.swift) selects which model answers the prompt.

| Case | Model |
| --- | --- |
| `flash20` | `gemini-2.0-flash` |
| `flash25` | `gemini-2.5-flash` (default) |

---

## Errors

`response(to:)` and `startNewConversation()` throw [`LanguageModelError`](Sources/Modules/Common/Models/LanguageModelError.swift), which conforms to `LocalizedError` and provides a human-readable description for each case:

| Case | Description |
| --- | --- |
| `cancelled` | The task that called the method was cancelled. |
| `challengeRequired` | A human-verification challenge must be resolved before ChatGPT can respond. |
| `conversationLost` | The provider can no longer continue the current conversation. |
| `emptyResponse` | The model returned an empty reply, or no reply arrived in time. |
| `invalidPrompt` | The prompt was empty after trimming whitespace. |
| `javaScriptEvaluationFailed` | Evaluating JavaScript in the ChatGPT web view failed. |
| `missingAPIKey` | No Gemini API key has been registered. |
| `pageStateUnavailable` | ChatGPT's page state could not be read. |
| `requestFailed` | The Gemini network request failed. |
| `sessionNotReady` | The ChatGPT session did not become ready in time. |
| `submissionFailed` | The prompt could not be submitted to ChatGPT. |

On the first turn of a session created with `LanguageModelSession()`, an error is thrown only if *every* provider fails; the error reflects the last provider tried. On later turns, the error comes from the conversation's provider. If the task that called the method is cancelled, the call throws `cancelled` without trying another provider. A call that is cancelled while waiting its turn throws `cancelled` before it runs.

In debug builds, the ChatGPT provider logs diagnostic details through the unified logging system – subsystem `LanguageModels`, category `ChatGPT` – whenever a prompt fails to send or the reply can't be read from ChatGPT's conversation stream. The details describe the page's state and its recent network responses; they never include the prompt or the reply.

---

## Concurrency

LanguageModels adopts Swift 6 strict concurrency.

- [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) is main-actor isolated. Create it and call its methods from the main actor. Its work runs asynchronously, so it does not block the main thread.
- A session's calls run one at a time, in the order they were made. A call that is cancelled while waiting its turn throws `cancelled` before it runs. `prewarm()` runs at once rather than waiting for the calls before it.
- Sessions are independent and may run concurrently. Once a session prewarms or sends a prompt to ChatGPT, it holds a hidden web view until it is released.
- `LanguageModels.responses(to:using:)` answers each prompt in its own session, up to ten at a time, or two at a time with `.chatGPT`, because each of those sessions holds a hidden web view.
- [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift), [`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift), and [`GeminiModel`](Sources/Modules/Gemini/Models/Public/GeminiModel.swift) are `Sendable` values.
- [`GeminiAPIKeyDelegate`](Sources/Modules/Common/Protocols/Public/GeminiAPIKeyDelegate.swift) conforming types must be `Sendable`. Register the delegate from the main actor.

---

&copy; NEOTechnica Corporation. All rights reserved.
