import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var imageLongEdge = MistralAISettings.defaultImageLongEdge
    @State private var imageQuality = MistralAISettings.defaultImageQuality
    @State private var errorMessage: String?

    private var keyStore: any MistralAPIKeyStoring {
        Dependencies.makeMistralAPIKeyStore()
    }

    private var aiSettingsStore: any MistralAISettingsStoring {
        Dependencies.makeMistralAISettingsStore()
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Mistral API Key") {
                SecureField("Paste key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .accessibilityIdentifier("ai-settings-key-field")

                Text("Leave blank to disable AI meal descriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Image Payload") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Long edge")
                        Spacer()
                        Text("\(imageLongEdge) px")
                            .foregroundStyle(.secondary)
                    }

                    Stepper(
                        value: $imageLongEdge,
                        in: MistralAISettings.minImageLongEdge...MistralAISettings.maxImageLongEdge,
                        step: MistralAISettings.imageLongEdgeStep
                    ) {
                        Text("Adjust long edge")
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("ai-settings-long-edge-stepper")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(imageQuality)")
                            .foregroundStyle(.secondary)
                    }

                    Stepper(
                        value: $imageQuality,
                        in: MistralAISettings.minImageQuality...MistralAISettings.maxImageQuality,
                        step: MistralAISettings.imageQualityStep
                    ) {
                        Text("Adjust quality")
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("ai-settings-quality-stepper")
                }

                Text("These settings affect only AI analysis uploads, not local photo storage or photo sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("ai-settings-save")
            }
        }
        .task {
            do {
                apiKey = try keyStore.apiKey() ?? ""
                let settings = aiSettingsStore.settings()
                imageLongEdge = settings.imageLongEdge
                imageQuality = settings.imageQuality
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Could Not Save AI Settings", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private func save() {
        do {
            try keyStore.setAPIKey(apiKey)
            aiSettingsStore.setSettings(
                MistralAISettings(
                    imageLongEdge: imageLongEdge,
                    imageQuality: imageQuality
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
