import SwiftUI

struct ChatSidebarPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var showBuildPopup: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Progress")
                .font(.title3.weight(.semibold))
            Text("Left panel tracks steps and build notes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Build Steps") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.buildSteps) { step in
                        BuildStepRow(step: step)
                    }
                }
            }

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
        .frame(minWidth: 270, idealWidth: 290, maxWidth: 320)
        .background(.thinMaterial)
        .sheet(isPresented: $showBuildPopup) {
            BuildProjectPopupView(viewModel: viewModel)
        }
    }
}

struct BuildStepRow: View {
    let step: StudioViewModel.BuildStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var indicatorColor: Color {
        switch step.state {
        case .pending:
            return .gray
        case .active:
            return .orange
        case .done:
            return .green
        }
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
