import Foundation

/// Apple's on-device `SpeechTranscriber` (macOS 26 `Speech` framework), exposed
/// as a third transcription engine next to WhisperKit and Parakeet.
///
/// The model has no files of its own in Hex: the speech assets are managed by
/// macOS through `AssetInventory`. "Downloaded" means the assets for the
/// resolved locale are installed on this Mac.
public enum AppleSpeechModel {
	/// Identifier stored in `HexSettings.selectedModel` and listed in `models.json`.
	public static let identifier = "apple-speech-transcriber"

	public static func matches(_ name: String) -> Bool {
		name == identifier
	}

	/// Locales installed when the language setting is "Auto".
	public static let fallbackLocaleIdentifiers = ["fr_FR", "en_US"]

	/// The locale to transcribe with.
	///
	/// - An explicit Hex output language wins (`"fr"` → `fr_FR`, `"en"` → `en_US`,
	///   anything else is passed through and resolved by the Speech framework).
	/// - With "Auto", the first French or English language in the user's
	///   preferred languages decides; otherwise `en_US`.
	public static func localeIdentifier(
		outputLanguage: String?,
		preferredLanguages: [String]
	) -> String {
		if let language = normalized(outputLanguage) {
			return mapped(language)
		}
		for preferred in preferredLanguages {
			let language = languageCode(of: preferred)
			if language == "fr" { return "fr_FR" }
			if language == "en" { return "en_US" }
		}
		return "en_US"
	}

	/// Locales whose assets should be installed when the user "downloads" the
	/// Apple engine. With an explicit language only that locale is needed;
	/// with "Auto" both French and English are installed, preferred one first.
	public static func localeIdentifiersToInstall(
		outputLanguage: String?,
		preferredLanguages: [String]
	) -> [String] {
		let primary = localeIdentifier(outputLanguage: outputLanguage, preferredLanguages: preferredLanguages)
		guard normalized(outputLanguage) == nil else { return [primary] }
		return [primary] + fallbackLocaleIdentifiers.filter { $0 != primary }
	}

	private static func normalized(_ language: String?) -> String? {
		guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		return trimmed
	}

	private static func mapped(_ language: String) -> String {
		switch language.lowercased() {
		case "fr": return "fr_FR"
		case "en": return "en_US"
		default: return language
		}
	}

	private static func languageCode(of identifier: String) -> String {
		let separators = CharacterSet(charactersIn: "-_")
		return identifier.components(separatedBy: separators).first?.lowercased() ?? ""
	}
}
