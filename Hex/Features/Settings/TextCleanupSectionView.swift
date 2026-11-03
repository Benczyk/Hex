import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

/// Optional Apple Intelligence (FoundationModels) cleanup of the final transcript.
struct TextCleanupSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			Label {
				Toggle(
					"Clean up text with Apple Intelligence",
					isOn: Binding(
						get: { store.hexSettings.textCleanupEnabled },
						set: { store.send(.setTextCleanupEnabled($0)) }
					)
				)
				Text("Runs the transcript through Apple's on-device language model to fix punctuation and obvious slips. If the model is unavailable, fails or takes more than a few seconds, the raw text is pasted.")
					.settingsCaption()
				if let reason = TextCleanupClient.systemUnavailableReason {
					Text("Not available on this Mac right now (\(reason)).")
						.font(.caption)
						.foregroundStyle(.orange)
				}
			} icon: {
				Image(systemName: "wand.and.stars")
			}

			if store.hexSettings.textCleanupEnabled {
				VStack(alignment: .leading, spacing: 6) {
					Text("Instructions")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					TextEditor(
						text: Binding(
							get: { store.hexSettings.textCleanupPrompt },
							set: { store.send(.setTextCleanupPrompt($0)) }
						)
					)
					.font(.callout)
					.frame(minHeight: 110)
					.scrollContentBackground(.hidden)
					.padding(6)
					.background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
					HStack {
						Spacer()
						Button("Reset to Default") {
							store.send(.resetTextCleanupPrompt)
						}
						.controlSize(.small)
						.disabled(store.hexSettings.textCleanupPrompt == TextCleanup.defaultPrompt)
					}
				}
			}
		} header: {
			Text("Text Cleanup")
		}
		.enableInjection()
	}
}
