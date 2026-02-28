import SwiftUI

struct SettingsView: View {
    @AppStorage("useAICodeGeneration") private var useAICodeGeneration: Bool = true
    @AppStorage("generationQuality") private var generationQualityRaw: String = AIGenerationQuality.fast.rawValue

    @State private var anthropicKey: String = ""
    @State private var openaiKey: String = ""
    @State private var anthropicKeySaved: Bool = false
    @State private var openaiKeySaved: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var generationQuality: Binding<AIGenerationQuality> {
        Binding(
            get: { AIGenerationQuality(rawValue: generationQualityRaw) ?? .fast },
            set: { generationQualityRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // Section: API Keys
            Section {
                apiKeyRow(
                    title: "Anthropic API Key",
                    key: $anthropicKey,
                    isSaved: anthropicKeySaved,
                    showKey: $showAnthropicKey,
                    onSave: { saveAnthropicKey() },
                    onDelete: { deleteAnthropicKey() }
                )

                apiKeyRow(
                    title: "OpenAI API Key (Optional)",
                    key: $openaiKey,
                    isSaved: openaiKeySaved,
                    showKey: $showOpenAIKey,
                    onSave: { saveOpenAIKey() },
                    onDelete: { deleteOpenAIKey() }
                )

                Text("OpenAI key is used for enhanced semantic analysis in the pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("API Keys")
            }

            // Section: Code Generation
            Section {
                Toggle("Use AI Code Generation", isOn: $useAICodeGeneration)
                    .toggleStyle(.switch)

                if !useAICodeGeneration {
                    Text("Template fallback will be used instead of AI generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Generation Quality", selection: generationQuality) {
                    ForEach(AIGenerationQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!useAICodeGeneration)

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Fast mode uses Claude Sonnet 4.5, Quality mode uses Claude Opus 4.6")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Code Generation")
            }

            // Status Messages
            if let errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            if let successMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(successMessage)
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
        .padding()
        .onAppear {
            loadExistingKeys()
        }
    }

    // MARK: - API Key Row Component

    @ViewBuilder
    private func apiKeyRow(
        title: String,
        key: Binding<String>,
        isSaved: Bool,
        showKey: Binding<Bool>,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                if isSaved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Key saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No key configured")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                if showKey.wrappedValue {
                    TextField("Enter API key", text: key)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter API key", text: key)
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: { showKey.wrappedValue.toggle() }) {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showKey.wrappedValue ? "Hide key" : "Show key")
            }

            HStack {
                Button("Save") {
                    onSave()
                }
                .disabled(key.wrappedValue.isEmpty)
                .buttonStyle(.borderedProminent)

                if isSaved {
                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Key Management

    private func loadExistingKeys() {
        anthropicKeySaved = KeychainService.retrieve(key: .anthropicAPIKey) != nil
        openaiKeySaved = KeychainService.retrieve(key: .openaiAPIKey) != nil

        // Show masked indicator if key exists
        if anthropicKeySaved {
            anthropicKey = ""
        }
        if openaiKeySaved {
            openaiKey = ""
        }
    }

    private func saveAnthropicKey() {
        clearMessages()

        do {
            try KeychainService.store(key: .anthropicAPIKey, value: anthropicKey)
            anthropicKeySaved = true
            anthropicKey = "" // Clear field after save
            successMessage = "Anthropic API key saved successfully"

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to save Anthropic API key: \(error.localizedDescription)"
        }
    }

    private func deleteAnthropicKey() {
        clearMessages()

        do {
            try KeychainService.delete(key: .anthropicAPIKey)
            anthropicKeySaved = false
            anthropicKey = ""
            successMessage = "Anthropic API key deleted successfully"

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to delete Anthropic API key: \(error.localizedDescription)"
        }
    }

    private func saveOpenAIKey() {
        clearMessages()

        do {
            try KeychainService.store(key: .openaiAPIKey, value: openaiKey)
            openaiKeySaved = true
            openaiKey = "" // Clear field after save
            successMessage = "OpenAI API key saved successfully"

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to save OpenAI API key: \(error.localizedDescription)"
        }
    }

    private func deleteOpenAIKey() {
        clearMessages()

        do {
            try KeychainService.delete(key: .openaiAPIKey)
            openaiKeySaved = false
            openaiKey = ""
            successMessage = "OpenAI API key deleted successfully"

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to delete OpenAI API key: \(error.localizedDescription)"
        }
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
