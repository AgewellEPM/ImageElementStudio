import SwiftUI

// MARK: - DeploymentWizardView

/// A 5-step deployment wizard presented as a sheet.
/// Follows the same pattern as OnboardingView: step indicator capsules at top,
/// slide transitions between steps, back/next navigation at bottom.
struct DeploymentWizardView: View {
    @Binding var isPresented: Bool
    @ObservedObject var deploymentService: DeploymentService
    @ObservedObject var signingService: SigningService

    /// Project directory for build operations
    var projectDirectory: URL?
    /// Xcode scheme name for archiving
    var schemeName: String = ""

    @State private var saveToKeychain: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator bar (5 steps)
            stepIndicatorBar

            Divider()

            // Step content with slide transition
            Group {
                switch deploymentService.currentStep {
                case .chooseTarget:
                    targetSelectionStep
                case .configureSigning:
                    signingConfigStep
                case .appMetadata:
                    metadataConfigStep
                case .buildArchive:
                    buildArchiveStep
                case .submitExport:
                    submitExportStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
            .animation(.easeInOut(duration: 0.3), value: deploymentService.currentStep)

            Divider()

            // Navigation bar
            navigationBar
        }
        .frame(width: 700, height: 580)
        .preferredColorScheme(.dark)
    }

    // MARK: - Step Indicator Bar

    private var stepIndicatorBar: some View {
        HStack(spacing: 6) {
            ForEach(DeploymentStep.allCases) { step in
                stepCapsule(for: step)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private func stepCapsule(for step: DeploymentStep) -> some View {
        let currentIndex = deploymentService.currentStep.rawValue
        let stepIndex = step.rawValue
        let isCompleted = stepIndex < currentIndex
        let isCurrent = stepIndex == currentIndex

        return HStack(spacing: 4) {
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            } else {
                Image(systemName: step.symbolName)
                    .font(.system(size: 10))
            }
            Text(step.title)
                .font(.caption2.weight(isCurrent ? .semibold : .regular))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(capsuleColor(isCompleted: isCompleted, isCurrent: isCurrent))
        )
        .foregroundStyle(capsuleForeground(isCompleted: isCompleted, isCurrent: isCurrent))
    }

    private func capsuleColor(isCompleted: Bool, isCurrent: Bool) -> Color {
        if isCompleted {
            return .green.opacity(0.2)
        } else if isCurrent {
            return Color.accentColor.opacity(0.2)
        }
        return Color.secondary.opacity(0.1)
    }

    private func capsuleForeground(isCompleted: Bool, isCurrent: Bool) -> Color {
        if isCompleted {
            return .green
        } else if isCurrent {
            return Color.accentColor
        }
        return .secondary
    }

    // MARK: - Step 1: Target Selection

    private var targetSelectionStep: some View {
        VStack(spacing: 20) {
            stepHeader(title: "Choose Deployment Target", subtitle: "Select how you want to distribute your app")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DeploymentTarget.allCases) { target in
                    targetCard(target)
                }
            }
            .padding(.horizontal, 32)

            if projectDirectory != nil {
                Button {
                    if let dir = projectDirectory {
                        deploymentService.openInXcode(projectDirectory: dir)
                    }
                } label: {
                    Label("Open in Xcode", systemImage: "hammer.fill")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private func targetCard(_ target: DeploymentTarget) -> some View {
        let isSelected = deploymentService.selectedTarget == target

        return Button {
            deploymentService.selectedTarget = target
        } label: {
            VStack(spacing: 10) {
                Image(systemName: target.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(target.displayName)
                    .font(.headline)

                Text(target.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(hex: "#1E2126", fallback: Color(nsColor: .controlBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Signing Configuration

    private var signingConfigStep: some View {
        VStack(spacing: 16) {
            stepHeader(title: "Configure Code Signing", subtitle: "Set up your code signing identity and team")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Detect identities button
                    HStack {
                        Button {
                            Task {
                                await signingService.detectSigningIdentities()
                            }
                        } label: {
                            Label(
                                signingService.isDetecting ? "Detecting..." : "Detect Identities",
                                systemImage: "magnifyingglass"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(signingService.isDetecting)

                        if signingService.isDetecting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }

                    // Detection error
                    if let error = signingService.detectionError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    // Detected identities list
                    if !signingService.availableIdentities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Available Identities")
                                .font(.subheadline.weight(.semibold))

                            ForEach(signingService.availableIdentities) { identity in
                                identityRow(identity)
                            }
                        }
                    }

                    Divider()

                    // Manual entry fields
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Signing Details")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Team ID")
                                .font(.caption.weight(.medium))
                            TextField("XXXXXXXXXX", text: $deploymentService.signingConfig.teamID)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signing Identity")
                                .font(.caption.weight(.medium))
                            TextField("Apple Development: Name (TEAMID)", text: $deploymentService.signingConfig.signingIdentity)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Save to Keychain
                    HStack {
                        Toggle("Save to Keychain", isOn: $saveToKeychain)
                            .toggleStyle(.checkbox)

                        if saveToKeychain {
                            Button("Save") {
                                signingService.saveSigningConfig(deploymentService.signingConfig)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!deploymentService.signingConfig.isValid)
                        }

                        Spacer()

                        // Status indicator
                        signingStatusBadge
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private func identityRow(_ identity: SigningService.SigningIdentityInfo) -> some View {
        let isSelected = deploymentService.signingConfig.signingIdentity == identity.name

        return Button {
            deploymentService.signingConfig.signingIdentity = identity.name
            deploymentService.signingConfig.teamID = identity.teamID
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        identityTypeBadge(identity.type)

                        if !identity.teamID.isEmpty {
                            Text("Team: \(identity.teamID)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func identityTypeBadge(_ type: SigningService.SigningIdentityInfo.IdentityType) -> some View {
        let label: String
        let color: Color

        switch type {
        case .development:
            label = "Development"
            color = .blue
        case .distribution:
            label = "Distribution"
            color = .purple
        case .developerID:
            label = "Developer ID"
            color = .orange
        case .unknown:
            label = "Unknown"
            color = .gray
        }

        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private var signingStatusBadge: some View {
        Group {
            if deploymentService.signingConfig.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Valid")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Incomplete")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Step 3: App Metadata

    private var metadataConfigStep: some View {
        VStack(spacing: 16) {
            stepHeader(title: "App Metadata", subtitle: "Configure your app's identity and versioning")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Display Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(.caption.weight(.medium))
                        TextField("My App", text: $deploymentService.appMetadata.displayName)
                            .textFieldStyle(.roundedBorder)
                        if deploymentService.appMetadata.displayName.isEmpty {
                            Text("Required")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    // Bundle ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle Identifier")
                            .font(.caption.weight(.medium))
                        TextField("com.example.myapp", text: $deploymentService.appMetadata.bundleID)
                            .textFieldStyle(.roundedBorder)
                        if deploymentService.appMetadata.bundleID.isEmpty {
                            Text("Required")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    HStack(spacing: 16) {
                        // Version
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version")
                                .font(.caption.weight(.medium))
                            TextField("1.0.0", text: $deploymentService.appMetadata.version)
                                .textFieldStyle(.roundedBorder)
                            if deploymentService.appMetadata.version.isEmpty {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }

                        // Build Number
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build Number")
                                .font(.caption.weight(.medium))
                            TextField("1", text: $deploymentService.appMetadata.buildNumber)
                                .textFieldStyle(.roundedBorder)
                            if deploymentService.appMetadata.buildNumber.isEmpty {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Minimum Deployment Target
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minimum Deployment Target")
                            .font(.caption.weight(.medium))
                        Picker("", selection: $deploymentService.appMetadata.minimumDeploymentTarget) {
                            Text("iOS 16.0").tag("16.0")
                            Text("iOS 17.0").tag("17.0")
                            Text("iOS 18.0").tag("18.0")
                        }
                        .pickerStyle(.segmented)
                    }

                    // Validation summary
                    if !deploymentService.appMetadata.isValid {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Fill in all required fields to continue.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    // MARK: - Step 4: Build & Archive

    private var buildArchiveStep: some View {
        VStack(spacing: 16) {
            stepHeader(title: "Build & Archive", subtitle: "Build your project and create an archive for deployment")

            if !deploymentService.isDeploying && deploymentService.deploymentResult == nil && deploymentService.deploymentError == nil {
                // Not started yet
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Ready to build")
                        .font(.title3.weight(.medium))

                    Text("This will archive your project using the configured signing identity and export settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button {
                        startBuild()
                    } label: {
                        Label("Start Build", systemImage: "play.fill")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(projectDirectory == nil)
                }

                Spacer()
            } else {
                // Build in progress, succeeded, or failed
                VStack(spacing: 12) {
                    DeploymentProgressView(deploymentService: deploymentService)

                    HStack {
                        if deploymentService.isDeploying {
                            Button("Cancel") {
                                // Reset the deployment state
                                deploymentService.isDeploying = false
                                deploymentService.deploymentError = "Build cancelled by user"
                            }
                            .buttonStyle(.bordered)
                        }

                        if deploymentService.deploymentError != nil && !deploymentService.isDeploying {
                            Button {
                                startBuild()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Spacer()

                        if deploymentService.deploymentResult?.succeeded == true {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Continue to deploy")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .padding(.top, 20)
    }

    private func startBuild() {
        guard let dir = projectDirectory else { return }
        Task {
            await deploymentService.runDeployment(
                projectDirectory: dir,
                scheme: schemeName
            )
        }
    }

    // MARK: - Step 5: Submit / Export

    private var submitExportStep: some View {
        VStack(spacing: 16) {
            stepHeader(title: submitStepTitle, subtitle: submitStepSubtitle)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // App Store Connect credentials (for App Store / TestFlight)
                    if deploymentService.selectedTarget.requiresAppStoreConnect {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Store Connect Credentials")
                                .font(.subheadline.weight(.semibold))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple ID")
                                    .font(.caption.weight(.medium))
                                TextField("your@email.com", text: $deploymentService.appleID)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("App-Specific Password")
                                    .font(.caption.weight(.medium))
                                SecureField("xxxx-xxxx-xxxx-xxxx", text: $deploymentService.appSpecificPassword)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                // Trigger upload / submission
                                startBuild()
                            } label: {
                                Label(
                                    deploymentService.selectedTarget == .appStore ? "Submit to App Store" : "Upload to TestFlight",
                                    systemImage: "paperplane.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(deploymentService.appleID.isEmpty || deploymentService.appSpecificPassword.isEmpty)
                        }
                    }

                    // Direct / Notarized status
                    if deploymentService.selectedTarget == .directNotarized {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notarization")
                                .font(.subheadline.weight(.semibold))

                            if let result = deploymentService.deploymentResult {
                                if result.succeeded {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                        Text(result.submissionID != nil ? "Notarized successfully" : "Exported successfully (not notarized)")
                                            .font(.callout)
                                    }

                                    if let submissionID = result.submissionID {
                                        Text("Submission ID: \(submissionID)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                        Text(result.errorMessage ?? "Notarization failed")
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                    }
                                }
                            } else {
                                Text("Build has not completed yet.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Output path display
                    if let result = deploymentService.deploymentResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Output")
                                .font(.subheadline.weight(.semibold))

                            HStack(spacing: 8) {
                                Image(systemName: "doc.zipper")
                                    .foregroundStyle(.secondary)
                                Text(result.outputPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }

                            Button {
                                deploymentService.revealInFinder(path: result.outputPath)
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        // Success / failure summary
                        resultSummary(result)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var submitStepTitle: String {
        switch deploymentService.selectedTarget {
        case .appStore:
            return "Submit to App Store"
        case .testFlight:
            return "Upload to TestFlight"
        case .adHoc:
            return "Export Ad Hoc Build"
        case .directNotarized:
            return "Export Notarized App"
        }
    }

    private var submitStepSubtitle: String {
        switch deploymentService.selectedTarget {
        case .appStore:
            return "Submit your build to App Store Connect for review"
        case .testFlight:
            return "Upload your build for TestFlight distribution"
        case .adHoc:
            return "Export an IPA for ad-hoc installation"
        case .directNotarized:
            return "Export a notarized app for direct distribution"
        }
    }

    @ViewBuilder
    private func resultSummary(_ result: DeploymentResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(result.succeeded ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.succeeded ? "Deployment Successful" : "Deployment Failed")
                        .font(.headline)

                    if let error = result.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Target: \(deploymentService.selectedTarget.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Format: \(deploymentService.selectedTarget.outputFormat)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            Button("Back") {
                deploymentService.goBack()
            }
            .buttonStyle(.bordered)
            .disabled(!deploymentService.canGoBack)

            Spacer()

            // Context-aware forward button
            if deploymentService.isTerminalStep {
                Button("Done") {
                    deploymentService.reset()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if deploymentService.currentStep == .buildArchive {
                if deploymentService.deploymentResult?.succeeded == true {
                    Button("Next") {
                        deploymentService.advanceStep()
                    }
                    .buttonStyle(.borderedProminent)
                } else if !deploymentService.isDeploying && deploymentService.deploymentResult == nil && deploymentService.deploymentError == nil {
                    Button {
                        startBuild()
                    } label: {
                        Label("Start Build", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectDirectory == nil)
                }
            } else {
                Button("Next") {
                    deploymentService.advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!deploymentService.canAdvance)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }

    // MARK: - Shared Components

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}
