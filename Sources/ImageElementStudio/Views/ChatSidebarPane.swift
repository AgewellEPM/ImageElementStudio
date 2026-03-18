import SwiftUI

struct ChatSidebarPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var showBuildPopup: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Project Progress")
                    .font(.title3.weight(.semibold))
            }
            Text("Build steps and project notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            BuildStepsProgressView(steps: viewModel.buildSteps)

            HStack {
                Text("Project Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Notes") {
                    viewModel.clearChatHistory()
                }
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                    }
                }
            }

            Button {
                showBuildPopup = true
            } label: {
                Label("Build Project", systemImage: "hammer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showBuildPopup) {
            BuildProjectPopupView(viewModel: viewModel)
        }
    }
}

/// Shows only completed steps (green checkmarks) + the current active step.
/// Pending steps below the active one are hidden until reached.
struct BuildStepsProgressView: View {
    let steps: [StudioViewModel.BuildStep]

    /// Steps to display: all .done + the first .active or first .pending (the "current" step).
    private var visibleSteps: [StudioViewModel.BuildStep] {
        var result: [StudioViewModel.BuildStep] = []
        var foundCurrent = false
        for step in steps {
            switch step.state {
            case .done:
                result.append(step)
            case .active:
                result.append(step)
                foundCurrent = true
            case .pending:
                if !foundCurrent {
                    // Show the first pending step as the "next up"
                    result.append(step)
                    foundCurrent = true
                }
            }
            if foundCurrent && step.state != .done { break }
        }
        return result
    }

    private var completedCount: Int {
        steps.filter { $0.state == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedCount)/\(steps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(completedCount), total: Double(steps.count))
                .tint(.green)

            ForEach(visibleSteps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        switch step.state {
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .active:
                            ProgressView()
                                .controlSize(.mini)
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(step.state == .done ? .secondary : .primary)
                        if step.state != .done {
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BuildProjectPopupView: View {
    @ObservedObject var viewModel: StudioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTarget: StudioViewModel.BuildTarget = .ios

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build Project")
                .font(.title3.weight(.semibold))

            Text("Confirm a target and setup package. The app will use everything currently on screen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(StudioViewModel.BuildTarget.allCases) { target in
                    Button {
                        selectedTarget = target
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: target.symbolName)
                                .font(.title2.weight(.semibold))
                            Text(target.title)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTarget == target ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedTarget == target ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            GroupBox("Confirmation") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.buildConfirmationLines(for: selectedTarget).enumerated()), id: \.offset) { item in
                        Text("\u{2022} \(item.element)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.reviewGateStatusLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.canExportBuildArtifacts ? .green : .orange)
                    Text(viewModel.fullStackStatusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.enterpriseReadinessStatusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Generate Full Stack") {
                    viewModel.generateFullStackBuild()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSettingUpBuild || !viewModel.canExportBuildArtifacts)
                Button("Confirm & Setup") {
                    viewModel.setupProjectBuild(for: selectedTarget)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSettingUpBuild || !viewModel.canExportBuildArtifacts)
            }
        }
        .padding(16)
        .frame(width: 620)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(roleColor.opacity(0.9))
            Text(message.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(roleColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private var roleColor: Color {
        switch message.role {
        case .system:
            return .gray
        case .user:
            return .blue
        case .assistant:
            return .green
        }
    }
}
