//
//  TextCleanupClient.swift
//  Hex
//
//  Optional cleanup of the final transcript with Apple's on-device language model
//  (macOS 26 `FoundationModels`). Off by default; any failure pastes the raw text.
//
//  The availability check and the `LanguageModelSession(model:instructions:)` +
//  `respond(to:)` flow are adapted from Handy:
//    repo:   https://github.com/cjpais/Handy
//    file:   src-tauri/swift/apple_intelligence.swift
//    commit: 0cb8ab21624cce2c3f95824494029aabbe6a110b
//    author: Chirag Agggarwal (GitHub: Schreezer); Handy is © 2025 CJ Pais
//    license: MIT
//  Hex's version drops the C bridge/semaphore and the @Generable structured output,
//  and adds a timeout so a slow model can never hold up pasting.
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

#if canImport(FoundationModels)
import FoundationModels
#endif

enum TextCleanupError: LocalizedError {
  case unavailable(String)
  case timedOut

  var errorDescription: String? {
    switch self {
    case let .unavailable(reason): return "Apple Intelligence is unavailable: \(reason)"
    case .timedOut: return "Apple Intelligence cleanup timed out"
    }
  }
}

@DependencyClient
struct TextCleanupClient {
  /// Whether Apple's on-device language model can be used right now.
  var isAvailable: @Sendable () -> Bool = { false }
  /// Runs `text` through the language model with `instructions`, failing after `timeout`.
  var cleanUp: @Sendable (_ text: String, _ instructions: String, _ timeout: Duration) async throws -> String
}

extension TextCleanupClient: DependencyKey {
  static var liveValue: Self {
    Self(
      isAvailable: { TextCleanupLive.availability() == nil },
      cleanUp: { text, instructions, timeout in
        try await TextCleanupLive.cleanUp(text: text, instructions: instructions, timeout: timeout)
      }
    )
  }
}

extension TextCleanupClient {
  /// `nil` when Apple's language model is usable, otherwise why not (for Settings copy).
  static var systemUnavailableReason: String? { TextCleanupLive.availability() }
}

extension DependencyValues {
  var textCleanup: TextCleanupClient {
    get { self[TextCleanupClient.self] }
    set { self[TextCleanupClient.self] = newValue }
  }
}

private enum TextCleanupLive {
  /// `nil` when available, otherwise a human-readable reason.
  static func availability() -> String? {
    #if canImport(FoundationModels)
    if #available(macOS 26, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return nil
      case let .unavailable(reason):
        return String(describing: reason)
      }
    }
    #endif
    return "requires macOS 26 or newer"
  }

  static func cleanUp(text: String, instructions: String, timeout: Duration) async throws -> String {
    if let reason = availability() {
      throw TextCleanupError.unavailable(reason)
    }
    #if canImport(FoundationModels)
    if #available(macOS 26, *) {
      return try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          // A fresh session per dictation: no transcript history leaks between pastes.
          let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
          let response = try await session.respond(to: text)
          return response.content
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw TextCleanupError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TextCleanupError.timedOut }
        return first
      }
    }
    #endif
    throw TextCleanupError.unavailable("requires macOS 26 or newer")
  }
}
