import Foundation

/// Builds the "expected words" list handed to Apple's speech recognizer
/// (`AnalysisContext.contextualStrings[.general]`) from the user's word remappings.
///
/// The *replacement* side of a remapping is the word the user wants to see, so
/// that is what we bias recognition towards. The existing text replacement
/// still runs afterwards; this only makes the right word more likely in the
/// first place.
public enum ContextualStringsBuilder {
	/// Keep the list short: the recognizer treats these as hints, and a huge
	/// list dilutes them.
	public static let defaultLimit = 100

	public static func build(
		from remappings: [WordRemapping],
		limit: Int = ContextualStringsBuilder.defaultLimit
	) -> [String] {
		guard limit > 0 else { return [] }
		var seen = Set<String>()
		var result: [String] = []
		for remapping in remappings where remapping.isEnabled {
			// Replacements using escape sequences (`\n`, `\t`…) are commands, not words.
			guard !remapping.replacement.contains("\\") else { continue }
			let candidate = remapping.replacement
				.components(separatedBy: .whitespacesAndNewlines)
				.filter { !$0.isEmpty }
				.joined(separator: " ")
			// Skip punctuation-only replacements such as "comma" → ",".
			guard candidate.rangeOfCharacter(from: .letters) != nil else { continue }
			let key = candidate.lowercased()
			guard seen.insert(key).inserted else { continue }
			result.append(candidate)
			if result.count == limit { break }
		}
		return result
	}
}
