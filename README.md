# LanguageModels

A framework for sending prompts to a large language model and receiving its reply behind a single, provider-agnostic API.

LanguageModels supports two backends: **Gemini**, called through its API, and **ChatGPT**, which needs neither an API key nor an account. A [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) created without a provider uses Gemini for its low latency and automatically falls back to ChatGPT if the Gemini request fails, then keeps the conversation on whichever provider replied; you can also target either backend explicitly.

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
  - [Challenge Presentation](#challenge-presentation)
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

Call `prewarm()` once a prompt is imminent to reduce the latency of the first reply. This prepares the ChatGPT provider ahead of time (Gemini needs no preparation). It is safe to call repeatedly and never throws:

```swift
let session = LanguageModelSession()
session.prewarm()
```

---

## Providers

A session routes each prompt to one or both of the following backends, selected by [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift):

| Provider | API key | Notes |
| --- | --- | --- |
| `.gemini(config:)` | Required | Low latency. Configure it with [`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift). |
| `.chatGPT` | Not required | No account needed. Higher latency, and it may surface a verification challenge. A reply that ChatGPT delivers as several messages is returned as one, with its messages separated by blank lines. |

When you construct a session with `LanguageModelSession()`, the first turn of a conversation tries `.gemini(config:)` (with a default configuration) and falls back to `.chatGPT`. The provider that replies to the first turn answers every later turn of the conversation, with no fallback. If that provider fails, the call throws, and the next turn goes to the same provider. If it throws `conversationLost`, the next turn starts over with Gemini. When you construct a session with an explicit provider, only that provider is used – there is no fallback.

Each session is backed by its own resources, so multiple sessions run independently and concurrently. ChatGPT-backed sessions share one set of site data. A session that has used ChatGPT holds the resources ChatGPT needs until the session is released.

---

## Configuration

### GeminiConfig

[`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift) configures a Gemini request. Both parameters have defaults:

```swift
// Defaults: the flash38 model, no system message.
let config = GeminiConfig()

// A specific model and a system message sent alongside every prompt.
let config = GeminiConfig(
    model: .flash25,
    systemMessage: "You are a terse assistant."
)

let session = LanguageModelSession(.gemini(config: config))
```

The `systemMessage`, when provided, steers the model's response and is sent alongside the user prompt passed to `response(to:)`.

### GeminiModel

[`GeminiModel`](Sources/Modules/Gemini/Models/Public/GeminiModel.swift) selects which model answers the prompt.

| Case | Model |
| --- | --- |
| `flash25` | `gemini-2.5-flash` |
| `flash38` | `gemini-3.8-flash` (default) |

### Challenge Presentation

ChatGPT may show a human-verification challenge. A challenge that does not clear on its own within fifteen seconds makes a session method throw `challengeRequired`. Set `LanguageModels.presentsChallenges` to `true` to instead present the challenge over your app's key window, with a close button, for up to two minutes:

```swift
LanguageModels.presentsChallenges = true
```

The default is `false`. The challenge covers your app's interface while it is shown, and the call that triggered it waits until the challenge clears, the close button is tapped, or two minutes pass. Presenting requires a key window; without one, the call throws `challengeRequired`. Tapping the close button also throws it.

---

## Errors

`response(to:)`, `startNewConversation()`, and `LanguageModels.responses(to:using:)` throw [`LanguageModelError`](Sources/Modules/Common/Models/LanguageModelError.swift), which conforms to `LocalizedError` and provides a human-readable description for each case:

| Case | Description |
| --- | --- |
| `cancelled` | The task that called the method was cancelled. |
| `challengeRequired` | A human-verification challenge must be resolved before ChatGPT can respond. Set `LanguageModels.presentsChallenges` to `true` to show the challenge so you can solve it. |
| `conversationLost` | The provider can no longer continue the current conversation. ChatGPT throws this error when its conversation is lost and cannot be restored. The next turn starts a fresh conversation. |
| `emptyResponse` | The model returned an empty reply. |
| `interrupted` | The reply was interrupted before it finished. The app's background execution time expired, or ChatGPT's session was terminated during the turn. |
| `invalidPrompt` | The prompt was empty after trimming whitespace. |
| `javaScriptEvaluationFailed` | A step of the ChatGPT request could not run. |
| `missingAPIKey` | No Gemini API key has been registered. |
| `pageStateUnavailable` | ChatGPT's state could not be read. |
| `requestFailed` | The network request failed. For ChatGPT, it could not be reached – for example, because the device is offline. |
| `sessionNotReady` | The ChatGPT session did not become ready in time. |
| `submissionFailed` | The prompt could not be submitted to ChatGPT. |
| `timedOut` | A deadline passed while waiting for a reply. |

On the first turn of a session created with `LanguageModelSession()`, an error is thrown only if *every* provider fails; the error reflects the last provider tried. On later turns, the error comes from the conversation's provider. If the task that called the method is cancelled, the call throws `cancelled` without trying another provider. A call that is cancelled while waiting its turn throws `cancelled` before it runs.

In debug builds, the ChatGPT provider logs diagnostic details through the unified logging system – subsystem `LanguageModels`, category `ChatGPT` – whenever a prompt fails to send or the reply can't be read. The details describe ChatGPT's state and its recent responses; they never include the prompt or the reply.

---

## Concurrency

LanguageModels adopts Swift 6 strict concurrency.

- [`LanguageModelSession`](Sources/Modules/Common/Models/LanguageModelSession.swift) is main-actor isolated. Create it and call its methods from the main actor. Its work runs asynchronously, so it does not block the main thread.
- The session requests background execution time while a reply is in progress, and throws `interrupted` if that time expires.
- A session's calls run one at a time, in the order they were made. A call that is cancelled while waiting its turn throws `cancelled` before it runs. `prewarm()` runs at once rather than waiting for the calls before it.
- Sessions are independent and may run concurrently. A session that has used ChatGPT holds the resources ChatGPT needs until the session is released.
- `LanguageModels.responses(to:using:)` answers each prompt in its own session, up to ten at a time, or two at a time with `.chatGPT`, because ChatGPT-backed sessions are resource-intensive. Duplicate prompts – within a batch or across concurrent calls – share a single in-flight request, and collapse to one entry in the returned dictionary. If any prompt fails, the whole batch fails, and its other prompts are cancelled. If the task that called the method is cancelled, the call throws `cancelled`, and each in-flight request that no other call is waiting on stops. Cancelling a call does not cancel a request that another concurrent call is still waiting on. That request continues for the other call.
- [`LanguageModelProvider`](Sources/Modules/Common/Models/LanguageModelProvider.swift), [`GeminiConfig`](Sources/Modules/Gemini/Models/Public/GeminiConfig.swift), and [`GeminiModel`](Sources/Modules/Gemini/Models/Public/GeminiModel.swift) are `Sendable` values.
- [`GeminiAPIKeyDelegate`](Sources/Modules/Common/Protocols/Public/GeminiAPIKeyDelegate.swift) conforming types must be `Sendable`. Register the delegate from the main actor.

---

&copy; NEOTechnica Corporation. All rights reserved.
