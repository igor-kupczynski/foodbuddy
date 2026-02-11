import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var errorMessage: String?

    private var keyStore: any MistralAPIKeyStoring {
        Dependencies.makeMistralAPIKeyStore()
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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Could Not Save API Key", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private func save() {
        do {
            try keyStore.setAPIKey(apiKey)
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
