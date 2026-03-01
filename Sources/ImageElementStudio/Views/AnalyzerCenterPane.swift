import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CenterPreviewMode: String, CaseIterable, Identifiable {
    case emulator
    case design

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .emulator:
            return "App Emulator"
        case .design:
            return "Original Design"
        }
    }
}

struct AnalyzerCenterPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var isDropTargeted: Bool = false
    @State private var previewMode: CenterPreviewMode = .emulator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.chooseImage()
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                            .frame(minWidth: 96)
                    }

                    Button {
                        viewModel.analyzeCurrentImage()
                    } label: {
                        Label("Analyze", systemImage: "sparkles")
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedImage == nil || viewModel.isAnalyzing)

                    Button {
                        viewModel.clearImage()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .frame(minWidth: 84)
                    }
                    .disabled(viewModel.selectedImage == nil)

                    Picker("Target", selection: $viewModel.realTimeBuildTarget) {
                        ForEach(StudioViewModel.BuildTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)

                    Spacer(minLength: 8)

                    if viewModel.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.isGeneratingApp {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.codeGenerationStatusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        viewModel.generateAndBuildFromCurrentImage()
                    } label: {
                        Label("Generate App", systemImage: "wand.and.stars")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!viewModel.canGenerateApp)
                    .help("Generate a working app from the current design using AI")

                    Button {
                        viewModel.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings (API keys, generation quality)")
                }
                .controlSize(.regular)

                Picker("Preview Mode", selection: $previewMode) {
                    ForEach(CenterPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 250, idealWidth: 320, maxWidth: 360)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.shouldShowStrategyPanel {
                GroupBox("Product Strategist") {
                    StrategyPanelView(viewModel: viewModel)
                }
            }

            GroupBox(previewMode.title) {
                centerPreviewContent
            }
            .frame(minHeight: 360)
            .onDrop(
                of: [UTType.fileURL.identifier, UTType.image.identifier],
                isTargeted: $isDropTargeted
            ) { providers in
                let canLoadImage = providers.contains { provider in
                    provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                        || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                }

                guard canLoadImage else { return false }
                viewModel.handleDroppedProviders(providers)
                return true
            }

            HStack(spacing: 14) {
                Label("\(viewModel.textElementCount) text", systemImage: "text.alignleft")
                Label("\(viewModel.shapeElementCount) shapes", systemImage: "rectangle.on.rectangle")
                Label("\(viewModel.renderableElements.count) total", systemImage: "square.grid.3x3.fill")
                Spacer()
                Button("Copy JSON") {
                    viewModel.copyJSONToClipboard()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            GroupBox("AI Workspace Chat") {
                CenterWorkspaceChat(viewModel: viewModel)
                    .frame(minHeight: 240)
            }

            if viewModel.showBuildOutput {
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Label("Build Output", systemImage: "hammer.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.showBuildOutput = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Hide build output")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        BuildOutputView(coordinator: viewModel.buildPipelineCoordinator)
                            .frame(minHeight: 200, maxHeight: 300)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $viewModel.showSettingsSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        viewModel.showSettingsSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                SettingsView()
            }
        }
        .onAppear {
            viewModel.realTimeBuildEnabled = true
            viewModel.triggerRealtimeBuildNow()
        }
        .onChange(of: viewModel.realTimeBuildTarget) { _, _ in
            viewModel.realTimeBuildEnabled = true
            viewModel.triggerRealtimeBuildNow()
        }
    }

    @ViewBuilder
    private var centerPreviewContent: some View {
        let hasDesign = viewModel.selectedImage != nil
        let hasMappedLayout = viewModel.renderableElements.count > 1

        switch previewMode {
        case .design:
            if let image = viewModel.selectedImage {
                ImageOverlayCanvas(
                    image: image,
                    canvasSize: viewModel.activeCanvasSize,
                    elements: viewModel.renderableElements,
                    selectedElementIDs: viewModel.selectedElementIDs,
                    onSelect: { selectedID, additive in
                        viewModel.setSelectedElement(selectedID, additive: additive)
                    },
                    onMarqueeSelect: { selectedIDs, additive in
                        viewModel.selectElementsByMarquee(selectedIDs, additive: additive)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropImageEmptyState(isTargeted: isDropTargeted)
            }
        case .emulator:
            if hasDesign || hasMappedLayout {
                AppEmulatorCanvas(
                    artboard: viewModel.activeArtboard ?? Artboard.empty(),
                    selectedElementIDs: viewModel.selectedElementIDs,
                    tokens: viewModel.latestDesignTokens,
                    showGrid: viewModel.showLayoutGrid,
                    gridSize: viewModel.gridSize,
                    showAlignmentGuides: viewModel.showAlignmentGuides,
                    onSelect: { selectedID, additive in
                        viewModel.setSelectedElement(selectedID, additive: additive)
                    },
                    onMarqueeSelect: { selectedIDs, additive in
                        viewModel.selectElementsByMarquee(selectedIDs, additive: additive)
                    },
                    onResize: { handle, deltaX, deltaY in
                        viewModel.resizeSelectedElements(handle: handle, deltaX: deltaX, deltaY: deltaY)
                    },
                    onRotate: { degrees in
                        viewModel.rotateSelectedElements(by: degrees)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropImageEmptyState(isTargeted: isDropTargeted)
            }
        }
    }
}

struct CenterWorkspaceChat: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.builderMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: viewModel.builderMessages.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        scrollProxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(inputPlaceholder, text: $viewModel.builderDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.sendBuilderPrompt()
                    }

                Button("Send") {
                    viewModel.sendBuilderPrompt()
                }
                .disabled(viewModel.builderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear Chat") {
                    viewModel.clearBuilderConversation()
                }
            }
        }
    }

    private var inputPlaceholder: String {
        if viewModel.strategySession != nil, !((viewModel.strategySession?.isComplete) ?? false) {
            return "Answer strategist prompt or use commands: approve, skip, auto-run..."
        }
        return "Describe your app idea or command (example: idea: AI fitness coach app)..."
    }
}

struct StrategyPanelView: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var ideaDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Pipeline Mode", selection: pipelineBinding) {
                ForEach(PipelineMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.strategyStageLine)
                .font(.caption.weight(.semibold))
            ProgressView(value: viewModel.strategyStageProgress)

            if let session = viewModel.strategySession {
                if let question = viewModel.strategyActiveQuestion {
                    Text(question.prompt)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let options = question.options, !options.isEmpty {
                        Text("Options: \(options.joined(separator: " | "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Answer strategy question...", text: $viewModel.strategyAnswerDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.submitStrategyAnswer(viewModel.strategyAnswerDraft)
                        }
                } else if session.isComplete {
                    Text("All required strategy questions are complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.strategyControlHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Approve / Continue") {
                        viewModel.approveCurrentStage()
                    }
                    .disabled(session.isComplete)

                    Button("Skip") {
                        viewModel.skipStrategyQuestion()
                    }
                    .disabled(viewModel.strategyActiveQuestion == nil || session.isComplete)

                    Button("Auto-run") {
                        viewModel.autoRunStrategy()
                    }
                }
                .controlSize(.small)

                HStack(spacing: 8) {
                    Button("Finalize Spec") {
                        viewModel.finalizeStrategySpec()
                    }
                    Button("Generate Mockups") {
                        viewModel.finalizeAndGenerateMockups()
                    }
                }
                .controlSize(.small)
            } else {
                TextField("Describe your product idea to start strategy...", text: $ideaDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        startStrategy()
                    }

                HStack(spacing: 8) {
                    Button("Start Strategy") {
                        startStrategy()
                    }
                    Button("Auto-run") {
                        let cleaned = ideaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleaned.isEmpty else { return }
                        viewModel.setPipelineMode(.auto)
                        viewModel.startStrategyFromIdea(cleaned)
                        ideaDraft = ""
                    }
                    .disabled(ideaDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var pipelineBinding: Binding<PipelineMode> {
        Binding(
            get: { viewModel.pipelineMode },
            set: { viewModel.setPipelineMode($0) }
        )
    }

    private func startStrategy() {
        let cleaned = ideaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        viewModel.startStrategyFromIdea(cleaned)
        ideaDraft = ""
    }
}

struct DropImageEmptyState: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isTargeted ? "square.and.arrow.down.on.square.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(isTargeted ? .blue : .secondary)

            Text("No Design Loaded")
                .font(.title2.weight(.semibold))

            Text("Drag and drop a design file here, or click Upload Design.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("No mockup yet? Describe your app idea in AI Workspace Chat and send it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isTargeted ? Color.blue : Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [8, 6])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
