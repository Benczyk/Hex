//
//  AppleSpeechClient.swift
//  Hex
//
//  On-device transcription with Apple's `SpeechTranscriber` (macOS 26 `Speech` framework).
//  Nothing is bundled or downloaded by Hex: speech assets are installed by macOS
//  through `AssetInventory`.
//

import AVFoundation
import Foundation
import HexCore

#if compiler(>=6.2) && canImport(Speech)
import Speech
#endif

enum AppleSpeechError: LocalizedError {
  case requiresMacOS26
  case unsupportedLocale(String)
  case assetsUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .requiresMacOS26:
      return "Apple Speech requires macOS 26 or newer."
    case let .unsupportedLocale(identifier):
      return "Apple Speech does not support the language \(identifier) on this Mac."
    case let .assetsUnavailable(identifier):
      return "Apple Speech assets for \(identifier) could not be installed."
    }
  }
}

actor AppleSpeechClient {
  private let logger = HexLog.transcription
  private let modelsLogger = HexLog.models

  /// Whether this build and this macOS version can use `SpeechTranscriber`.
  nonisolated static var isSupported: Bool {
    #if compiler(>=6.2) && canImport(Speech)
    if #available(macOS 26, *) { return true }
    #endif
    return false
  }

  /// `true` when the speech assets for the locale resolved from `outputLanguage` are installed.
  func isInstalled(outputLanguage: String?) async -> Bool {
    #if compiler(>=6.2) && canImport(Speech)
    if #available(macOS 26, *) {
      let identifier = Self.localeIdentifier(outputLanguage)
      guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
        return false
      }
      let status = await AssetInventory.status(forModules: [Self.makeTranscriber(locale: locale)])
      return status == .installed
    }
    #endif
    return false
  }

  /// Installs the speech assets Hex needs (the selected language, or French + English for "Auto"),
  /// reporting combined progress like Hex's model downloads.
  func install(outputLanguage: String?, progress: @escaping (Progress) -> Void) async throws {
    #if compiler(>=6.2) && canImport(Speech)
    if #available(macOS 26, *) {
      let identifiers = AppleSpeechModel.localeIdentifiersToInstall(
        outputLanguage: outputLanguage,
        preferredLanguages: Locale.preferredLanguages
      )
      let primary = identifiers[0]
      let overall = Progress(totalUnitCount: 100)
      progress(overall)
      for (index, identifier) in identifiers.enumerated() {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
          // The selected language must be supported; extra "Auto" locales are best effort.
          if identifier == primary { throw AppleSpeechError.unsupportedLocale(identifier) }
          modelsLogger.notice("Apple Speech: skipping unsupported locale \(identifier)")
          continue
        }
        do {
          try await installAssets(for: locale) { fraction in
            let total = (Double(index) + fraction) / Double(identifiers.count)
            overall.completedUnitCount = Int64(total * 100)
            progress(overall)
          }
        } catch {
          if identifier == primary || error is CancellationError { throw error }
          modelsLogger.error("Apple Speech: optional locale \(identifier) failed to install: \(error.localizedDescription)")
        }
      }
      overall.completedUnitCount = 100
      progress(overall)
      return
    }
    #endif
    throw AppleSpeechError.requiresMacOS26
  }

  /// "Remove download": releases Hex's locale reservations so macOS may reclaim the assets.
  func releaseAssets(outputLanguage: String?) async {
    #if compiler(>=6.2) && canImport(Speech)
    if #available(macOS 26, *) {
      let identifiers = AppleSpeechModel.localeIdentifiersToInstall(
        outputLanguage: outputLanguage,
        preferredLanguages: Locale.preferredLanguages
      )
      for identifier in identifiers {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else { continue }
        let released = await AssetInventory.release(reservedLocale: locale)
        modelsLogger.info("Apple Speech: released \(identifier) reservation=\(released)")
      }
    }
    #endif
  }

  /// Transcribes the audio file Hex recorded, biasing recognition towards `contextualStrings`.
  func transcribe(
    url: URL,
    outputLanguage: String?,
    contextualStrings: [String],
    progress: @escaping (Progress) -> Void
  ) async throws -> String {
    #if compiler(>=6.2) && canImport(Speech)
    if #available(macOS 26, *) {
      let identifier = Self.localeIdentifier(outputLanguage)
      guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
        throw AppleSpeechError.unsupportedLocale(identifier)
      }

      // Assets can be missing if the language changed since the user installed the engine.
      let transcriber = Self.makeTranscriber(locale: locale)
      if await AssetInventory.status(forModules: [transcriber]) != .installed {
        logger.notice("Apple Speech assets missing for \(identifier); installing before transcription")
        try await installAssets(for: locale) { fraction in
          let p = Progress(totalUnitCount: 100)
          p.completedUnitCount = Int64(fraction * 100)
          progress(p)
        }
      }

      let analyzer = SpeechAnalyzer(modules: [transcriber])
      if !contextualStrings.isEmpty {
        var context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)
        logger.info("Apple Speech: set \(contextualStrings.count) contextual string(s)")
      }

      let audioFile = try AVAudioFile(forReading: url)

      // Start consuming results before feeding audio so nothing is missed.
      let collector = Task { () throws -> String in
        var text = ""
        for try await result in transcriber.results {
          text += String(result.text.characters)
        }
        return text
      }

      do {
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
          try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
          await analyzer.cancelAndFinishNow()
        }
      } catch {
        collector.cancel()
        throw error
      }

      let text = try await collector.value
      return text
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
    #endif
    throw AppleSpeechError.requiresMacOS26
  }

  // MARK: - Helpers

  private static func localeIdentifier(_ outputLanguage: String?) -> String {
    AppleSpeechModel.localeIdentifier(
      outputLanguage: outputLanguage,
      preferredLanguages: Locale.preferredLanguages
    )
  }

  #if compiler(>=6.2) && canImport(Speech)
  @available(macOS 26, *)
  private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    // Final results only: Hex transcribes a finished recording, not a live stream.
    SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
  }

  @available(macOS 26, *)
  private func installAssets(for locale: Locale, fraction: @escaping (Double) -> Void) async throws {
    let transcriber = Self.makeTranscriber(locale: locale)
    if await AssetInventory.status(forModules: [transcriber]) == .installed {
      fraction(1)
      return
    }
    guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
      // nil means nothing to install.
      fraction(1)
      return
    }
    modelsLogger.notice("Apple Speech: installing assets for \(locale.identifier)")
    // AssetInstallationRequest exposes a Foundation `Progress`; poll it like Parakeet's best-effort progress.
    let poller = Task {
      while !Task.isCancelled {
        fraction(request.progress.fractionCompleted)
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    defer { poller.cancel() }
    try await request.downloadAndInstall()
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw AppleSpeechError.assetsUnavailable(locale.identifier)
    }
    fraction(1)
    modelsLogger.notice("Apple Speech: assets installed for \(locale.identifier)")
  }
  #endif
}
