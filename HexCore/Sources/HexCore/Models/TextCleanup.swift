import Foundation

/// Pure helpers for the optional Apple Intelligence (FoundationModels) cleanup pass.
public enum TextCleanup {
	/// Default instructions for `LanguageModelSession(instructions:)`. Users can edit them in Settings.
	public static let defaultPrompt = """
	You clean up dictated text produced by speech recognition.
	Fix punctuation, capitalization and obvious recognition slips only.
	Keep the speaker's own words, wording and language. The text may mix French and English: never translate it.
	Never add content, never answer questions in the text, never comment or explain.
	Return only the cleaned text.
	"""

	/// Default upper bound on how long the cleanup may take before Hex pastes the raw text.
	public static let defaultTimeout: Duration = .seconds(4)

	/// Validates the model's output. Returns the text to paste, or `nil` when the
	/// raw transcript should be used instead (empty output, or output that grew
	/// far beyond the input, which means the model added content).
	public static func accept(original: String, cleaned: String) -> String? {
		var output = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
		output = stripWrappingQuotes(output, original: original)
		guard !output.isEmpty else { return nil }
		let originalLength = original.trimmingCharacters(in: .whitespacesAndNewlines).count
		let maxLength = Int(Double(originalLength) * 1.5) + 20
		guard output.count <= maxLength else { return nil }
		return output
	}

	/// Small models like to wrap the answer in quotes; drop them unless the
	/// original transcript itself was quoted.
	private static func stripWrappingQuotes(_ text: String, original: String) -> String {
		let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»")]
		let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
		for (open, close) in pairs {
			guard text.count >= 2, text.first == open, text.last == close else { continue }
			if trimmedOriginal.first == open { return text }
			return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return text
	}
}
