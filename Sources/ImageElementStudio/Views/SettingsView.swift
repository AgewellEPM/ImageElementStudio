import SwiftUI

struct SettingsView: View {
    @AppStorage("useAICodeGeneration") private var useAICodeGeneration: Bool = true
    @AppStorage("generationQuality") private var generationQualityRaw: String = AIGenerationQuality.fast.rawValue

    @State private var anthropicKey: String = ""
    @State private var openaiKey: String = ""
    @State private var geminiKey: String = ""
    @State private var anthropicKeySaved: Bool = false
    @State private var openaiKeySaved: Bool = false
    @State private var geminiKeySaved: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var showGeminiKey: Bool = false
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

                apiKeyRow(
                    title: "Google Gemini API Key (Optional)",
                    key: $geminiKey,
                    isSaved: geminiKeySaved,
                    showKey: $showGeminiKey,
                    onSave: { saveGeminiKey() },
                    onDelete: { deleteGeminiKey() }
                )

                Text("OpenAI and Gemini keys are used as fallback providers for AI wireframe generation.")
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Paid Models (API key required)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Paid Model", selection: generationQuality) {
                        ForEach(AIGenerationQuality.paidCases) { q in
                            Text(q.title).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!useAICodeGeneration)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Free Local Models (Ollama)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        OllamaStatusBadge()
                    }

                    Picker("Free Model", selection: generationQuality) {
                        ForEach(AIGenerationQuality.freeCases) { q in
                            Text(q.title).tag(q)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(!useAICodeGeneration)
                }

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Paid: Claude Sonnet/Opus via API. Free: local models via Ollama (ollama.com) — no API key needed, runs on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("To use free models, install Ollama and pull a model:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install ollama && ollama pull qwen2.5-coder:7b")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
        .frame(width: 540, height: 680)
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
        geminiKeySaved = KeychainService.retrieve(key: .geminiAPIKey) != nil

        // Clear fields — the saved indicator communicates status
        if anthropicKeySaved { anthropicKey = "" }
        if openaiKeySaved { openaiKey = "" }
        if geminiKeySaved { geminiKey = "" }
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to delete OpenAI API key: \(error.localizedDescription)"
        }
    }

    private func saveGeminiKey() {
        clearMessages()

        do {
            try KeychainService.store(key: .geminiAPIKey, value: geminiKey)
            geminiKeySaved = true
            geminiKey = ""
            successMessage = "Google Gemini API key saved successfully"

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to save Google Gemini API key: \(error.localizedDescription)"
        }
    }

    private func deleteGeminiKey() {
        clearMessages()

        do {
            try KeychainService.delete(key: .geminiAPIKey)
            geminiKeySaved = false
            geminiKey = ""
            successMessage = "Google Gemini API key deleted successfully"

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        } catch {
            errorMessage = "Failed to delete Google Gemini API key: \(error.localizedDescription)"
        }
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - Ollama Status Badge

struct OllamaStatusBadge: View {
    @State private var isAvailable: Bool? = nil
    @State private var modelCount: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task {
            await checkOllama()
        }
    }

    private var statusColor: Color {
        switch isAvailable {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }

    private var statusText: String {
        switch isAvailable {
        case .some(true):
            return modelCount > 0 ? "\(modelCount) model\(modelCount == 1 ? "" : "s") ready" : "Running (no models)"
        case .some(false):
            return "Not running"
        case .none:
            return "Checking..."
        }
    }

    private func checkOllama() async {
        let service = OllamaService()
        let available = await service.isAvailable()
        isAvailable = available
        if available {
            let models = await service.listModels()
            modelCount = models.count
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
