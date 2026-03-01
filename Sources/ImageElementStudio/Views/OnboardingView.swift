import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var anthropicKey = ""
    @State private var openaiKey = ""
    @State private var keySaveError: String?
    @State private var keySaved = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)

            Spacer()

            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    apiKeyStep
                case 2:
                    tourStep
                default:
                    EmptyView()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button(currentStep == 1 ? (anthropicKey.isEmpty && !keySaved ? "Skip for Now" : "Next") : "Next") {
                        if currentStep == 1 && !anthropicKey.isEmpty && !keySaved {
                            saveKeys()
                        }
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 600, height: 460)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [Color(red: 0.23, green: 0.46, blue: 0.94),
                             Color(red: 0.10, green: 0.23, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Welcome to Image Element Studio")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Analyze design screenshots and generate production-ready\niOS, macOS, and web applications powered by AI.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: API Key Setup

    private var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Connect Your AI")
                .font(.title)
                .fontWeight(.bold)

            Text("Enter your Anthropic API key to enable AI-powered analysis and code generation.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API Key")
                        .font(.headline)
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI API Key (Optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("sk-...", text: $openaiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if keySaved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Keys saved securely to Keychain")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if let error = keySaveError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: 400)

            if !anthropicKey.isEmpty && !keySaved {
                Button("Save Keys") {
                    saveKeys()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 3: Feature Tour

    private var tourStep: some View {
        VStack(spacing: 24) {
            Text("What You Can Do")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "photo.badge.magnifyingglass",
                    color: .blue,
                    title: "Upload & Analyze",
                    description: "Drop any design screenshot and get instant element detection with semantic labels."
                )

                featureRow(
                    icon: "brain",
                    color: .purple,
                    title: "AI-Powered Strategy",
                    description: "Describe your app idea and get a guided strategy session with wireframes and specs."
                )

                featureRow(
                    icon: "hammer.fill",
                    color: .orange,
                    title: "Generate Production Code",
                    description: "Build complete iOS, macOS, or web apps from your designs with one click."
                )
            }
            .frame(maxWidth: 420)

            Text("You can always configure API keys in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Key Management

    private func saveKeys() {
        keySaveError = nil

        do {
            if !anthropicKey.isEmpty {
                try KeychainService.store(key: .anthropicAPIKey, value: anthropicKey)
            }
            if !openaiKey.isEmpty {
                try KeychainService.store(key: .openaiAPIKey, value: openaiKey)
            }
            keySaved = true
            anthropicKey = ""
            openaiKey = ""
        } catch {
            keySaveError = error.localizedDescription
        }
    }
}
