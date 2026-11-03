import Testing
@testable import HexCore

struct AppleSpeechLocaleTests {
	@Test
	func explicitFrenchAndEnglishMapToInstalledLocales() {
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: "fr", preferredLanguages: ["en-US"]) == "fr_FR")
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: "en", preferredLanguages: ["fr-FR"]) == "en_US")
	}

	@Test
	func otherExplicitLanguagesPassThrough() {
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: "de", preferredLanguages: ["fr-FR"]) == "de")
	}

	@Test
	func autoUsesFirstFrenchOrEnglishPreferredLanguage() {
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: nil, preferredLanguages: ["fr-CA", "en-US"]) == "fr_FR")
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: "", preferredLanguages: ["de-DE", "en-GB", "fr-FR"]) == "en_US")
	}

	@Test
	func autoWithoutFrenchOrEnglishFallsBackToEnglish() {
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: nil, preferredLanguages: ["ja-JP"]) == "en_US")
		#expect(AppleSpeechModel.localeIdentifier(outputLanguage: nil, preferredLanguages: []) == "en_US")
	}

	@Test
	func autoInstallsBothFallbackLocalesPreferredFirst() {
		#expect(
			AppleSpeechModel.localeIdentifiersToInstall(outputLanguage: nil, preferredLanguages: ["en-US"]) == ["en_US", "fr_FR"]
		)
		#expect(
			AppleSpeechModel.localeIdentifiersToInstall(outputLanguage: nil, preferredLanguages: ["fr-FR"]) == ["fr_FR", "en_US"]
		)
	}

	@Test
	func explicitLanguageInstallsOnlyThatLocale() {
		#expect(AppleSpeechModel.localeIdentifiersToInstall(outputLanguage: "fr", preferredLanguages: ["en-US"]) == ["fr_FR"])
	}

	@Test
	func identifierMatching() {
		#expect(AppleSpeechModel.matches("apple-speech-transcriber"))
		#expect(!AppleSpeechModel.matches("parakeet-tdt-0.6b-v3-coreml"))
	}
}

struct ContextualStringsBuilderTests {
	@Test
	func usesEnabledReplacementsOnly() {
		let remappings = [
			WordRemapping(match: "hex code", replacement: "Hex"),
			WordRemapping(isEnabled: false, match: "cloud", replacement: "Claude"),
			WordRemapping(match: "swift you eye", replacement: "SwiftUI"),
		]
		#expect(ContextualStringsBuilder.build(from: remappings) == ["Hex", "SwiftUI"])
	}

	@Test
	func skipsPunctuationAndEscapeSequenceReplacements() {
		let remappings = [
			WordRemapping(match: "comma", replacement: ","),
			WordRemapping(match: "new line", replacement: "\\n"),
			WordRemapping(match: "blank", replacement: "   "),
			WordRemapping(match: "tcha", replacement: "TCA"),
		]
		#expect(ContextualStringsBuilder.build(from: remappings) == ["TCA"])
	}

	@Test
	func trimsCollapsesWhitespaceAndDeduplicatesCaseInsensitively() {
		let remappings = [
			WordRemapping(match: "a", replacement: "  Composable   Architecture "),
			WordRemapping(match: "b", replacement: "composable architecture"),
			WordRemapping(match: "c", replacement: "Kubernetes"),
		]
		#expect(ContextualStringsBuilder.build(from: remappings) == ["Composable Architecture", "Kubernetes"])
	}

	@Test
	func keepsAccentedWords() {
		let remappings = [WordRemapping(match: "theatre", replacement: "théâtre")]
		#expect(ContextualStringsBuilder.build(from: remappings) == ["théâtre"])
	}

	@Test
	func respectsLimit() {
		let remappings = (0..<10).map { WordRemapping(match: "m\($0)", replacement: "Word\($0)") }
		#expect(ContextualStringsBuilder.build(from: remappings, limit: 3) == ["Word0", "Word1", "Word2"])
		#expect(ContextualStringsBuilder.build(from: remappings, limit: 0).isEmpty)
	}
}

struct TextCleanupTests {
	@Test
	func acceptsReasonableCleanup() {
		#expect(TextCleanup.accept(original: "bonjour je suis là", cleaned: " Bonjour, je suis là.\n") == "Bonjour, je suis là.")
	}

	@Test
	func rejectsEmptyOutput() {
		#expect(TextCleanup.accept(original: "hello", cleaned: "  \n") == nil)
	}

	@Test
	func rejectsOutputThatAddsContent() {
		let original = "send the report"
		let cleaned = "Send the report. Here is a draft of the report you asked for, with an introduction and three sections."
		#expect(TextCleanup.accept(original: original, cleaned: cleaned) == nil)
	}

	@Test
	func stripsWrappingQuotesAddedByTheModel() {
		#expect(TextCleanup.accept(original: "on se voit demain", cleaned: "\"On se voit demain.\"") == "On se voit demain.")
		#expect(TextCleanup.accept(original: "on se voit demain", cleaned: "« On se voit demain. »") == "On se voit demain.")
	}

	@Test
	func keepsQuotesWhenOriginalWasQuoted() {
		#expect(TextCleanup.accept(original: "\"hello\"", cleaned: "\"Hello.\"") == "\"Hello.\"")
	}

	@Test
	func defaultPromptMentionsTheKeyRules() {
		#expect(TextCleanup.defaultPrompt.contains("Never add content"))
		#expect(TextCleanup.defaultPrompt.contains("French and English"))
	}
}
