import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CenterPreviewMode: String, CaseIterable, Identifiable {
    case emulator
    case design
    case wireframe
    case hiFiWireframe

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .emulator:
            return "App Emulator"
        case .design:
            return "Original Design"
        case .wireframe:
            return "Wireframe"
        case .hiFiWireframe:
            return "Hi-Fi Wireframe"
        }
    }
}

struct AnalyzerCenterPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var isDropTargeted: Bool = false
    @State private var previewMode: CenterPreviewMode = .emulator
    @State private var chatHeight: CGFloat = 160
    @GestureState private var chatDragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Top Toolbar
            topToolbar
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider().opacity(0.3)

            // MARK: - Zoom Navigator Bar
            zoomNavigatorBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            // MARK: - Canvas Preview (dominant area)
            canvasArea
                .layoutPriority(1)

            // MARK: - Draggable Splitter
            chatSplitterHandle

            // MARK: - AI Chat (resizable)
            aiChatSection
                .frame(height: viewModel.isChatCollapsed ? nil : max(60, chatHeight - chatDragOffset))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // MARK: - Build Output (conditional)
            if viewModel.showBuildOutput {
                buildOutputSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $viewModel.showDeploymentWizard) {
            DeploymentWizardView(
                isPresented: $viewModel.showDeploymentWizard,
                deploymentService: viewModel.deploymentService,
                signingService: viewModel.signingService,
                projectDirectory: viewModel.lastRealtimeBuildPath.flatMap { URL(fileURLWithPath: $0) },
                schemeName: viewModel.projectName
            )
            .frame(minWidth: 680, minHeight: 560)
        }
        #if !APP_STORE
        .popover(isPresented: $viewModel.showSelfTestPanel, arrowEdge: .bottom) {
            SelfTestPanelView(viewModel: viewModel, testService: viewModel.selfTestService)
                .frame(width: 360, height: 500)
        }
        #endif
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

    // MARK: - Top Toolbar

    @ViewBuilder
    private var topToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    viewModel.chooseImage()
                } label: {
                    Label("Upload", systemImage: "square.and.arrow.up")
                }

                Button {
                    viewModel.analyzeCurrentImage()
                } label: {
                    Label("Analyze", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedImage == nil || viewModel.isAnalyzing)

                Button {
                    viewModel.clearImage()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(viewModel.selectedImage == nil)

                Picker("Target", selection: $viewModel.realTimeBuildTarget) {
                    ForEach(StudioViewModel.BuildTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Spacer(minLength: 4)

                if viewModel.isAnalyzing {
                    ProgressView().controlSize(.small)
                    Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                }

                if viewModel.isGeneratingApp {
                    ProgressView().controlSize(.small)
                    Text(viewModel.codeGenerationStatusLine)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                Button {
                    viewModel.generateAndBuildFromCurrentImage()
                } label: {
                    Label("Generate App", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!viewModel.canGenerateApp)

                if let estimate = viewModel.tokenCostService.lastEstimate {
                    if estimate.quality.isFree {
                        Text("FREE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                            .help("Free local model: \(estimate.model) — no API cost")
                    } else {
                        Text("~$\(estimate.estimatedCost, specifier: "%.2f")")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .help("Estimated cost: $\(estimate.estimatedCost, specifier: "%.2f") for \(estimate.estimatedCalls) API calls")
                    }
                }

                Button {
                    viewModel.showDeploymentWizard = true
                } label: {
                    Label("Deploy", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!viewModel.canExportBuildArtifacts)

                #if !APP_STORE
                Button {
                    viewModel.showSelfTestPanel.toggle()
                } label: {
                    Label("Test", systemImage: "testtube.2")
                }
                .buttonStyle(.bordered)
                .tint(viewModel.selfTestService.isServerRunning ? .green : .secondary)
                #endif

                Button {
                    viewModel.showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
            .controlSize(.small)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Zoom Navigator Bar

    @ViewBuilder
    private var zoomNavigatorBar: some View {
        HStack(spacing: 8) {
            // Preview mode picker
            Picker("Preview", selection: $previewMode) {
                ForEach(CenterPreviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            if previewMode == .emulator {
                DevicePickerView(catalogService: viewModel.deviceCatalogService)
            }

            Spacer(minLength: 4)

            // Zoom controls
            HStack(spacing: 4) {
                Button { viewModel.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(viewModel.canvasZoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                Button { viewModel.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Button { viewModel.zoomToFit() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Fit to window")
            }
        }
    }

    // MARK: - Canvas Area

    @ViewBuilder
    private var canvasArea: some View {
        VStack(spacing: 0) {
            // Artboard name bar
            if let artboard = viewModel.activeArtboard {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(artboard.name)
                        .font(.caption.weight(.semibold))
                    Text("\(artboard.width)x\(artboard.height)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(artboard.elements.count) elements")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
            }

            // Strategy panel
            if viewModel.shouldShowStrategyPanel {
                GroupBox("Product Strategist") {
                    StrategyPanelView(viewModel: viewModel)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            // Canvas content — keyed to artboard ID so SwiftUI re-renders on artboard switch
            centerPreviewContent
                .id(viewModel.selectedArtboardID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
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
    }

    // MARK: - Preview Content

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
                .scaleEffect(viewModel.canvasZoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropImageEmptyState(isTargeted: isDropTargeted)
            }
        case .emulator:
            if hasDesign || hasMappedLayout {
                DeviceFrameView(
                    device: viewModel.deviceCatalogService.selectedDevice,
                    orientation: viewModel.deviceCatalogService.orientation,
                    showFrame: viewModel.deviceCatalogService.showDeviceFrame,
                    showSafeAreas: viewModel.deviceCatalogService.showSafeAreas
                ) {
                    AppEmulatorCanvas(
                        artboard: viewModel.activeArtboard ?? Artboard.empty(),
                        selectedElementIDs: viewModel.selectedElementIDs,
                        tokens: viewModel.latestDesignTokens,
                        showGrid: viewModel.showLayoutGrid,
                        gridSize: viewModel.gridSize,
                        showAlignmentGuides: viewModel.showAlignmentGuides,
                        deviceSpec: viewModel.deviceCatalogService.selectedDevice,
                        deviceOrientation: viewModel.deviceCatalogService.orientation,
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
                }
                .scaleEffect(viewModel.canvasZoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropImageEmptyState(isTargeted: isDropTargeted)
            }
        case .wireframe:
            VStack(spacing: 0) {
                wireframeToolbar
                WireframeCanvasView(
                    artboard: viewModel.activeArtboard ?? Artboard.empty(),
                    selectedElementIDs: viewModel.selectedElementIDs,
                    onSelect: { selectedID, additive in
                        viewModel.setSelectedElement(selectedID, additive: additive)
                    },
                    onMarqueeSelect: { selectedIDs, additive in
                        viewModel.selectElementsByMarquee(selectedIDs, additive: additive)
                    }
                )
                .scaleEffect(viewModel.canvasZoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .hiFiWireframe:
            VStack(spacing: 0) {
                wireframeToolbar
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
                .scaleEffect(viewModel.canvasZoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Wireframe Toolbar

    @ViewBuilder
    private var wireframeToolbar: some View {
        HStack(spacing: 10) {
            let quality: WireframeQuality = previewMode == .wireframe ? .loFi : .hiFi
            let label = quality == .loFi ? "Generate Lo-Fi Wireframe" : "Generate Hi-Fi Wireframe"

            Button {
                viewModel.generateAIWireframe(quality: quality)
            } label: {
                Label(label, systemImage: "wand.and.sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(quality == .loFi ? .gray : .purple)
            .disabled(viewModel.wireframeService.isGenerating)
            .controlSize(.small)

            if viewModel.wireframeService.isGenerating {
                ProgressView().controlSize(.small)
                Text(viewModel.wireframeService.generationProgress)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            if let error = viewModel.wireframeService.generationError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - Draggable Splitter Handle

    @ViewBuilder
    private var chatSplitterHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
        }
        .frame(height: 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($chatDragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let newHeight = chatHeight - value.translation.height
                    chatHeight = min(max(newHeight, 60), 500)
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.isChatCollapsed.toggle()
            }
        }
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - AI Chat Section (compact, collapsible)

    @ViewBuilder
    private var aiChatSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with collapse toggle
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.isChatCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isChatCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.bold))
                        Text("AI Chat")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if !viewModel.builderMessages.isEmpty {
                    Text("\(viewModel.builderMessages.count) messages")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !viewModel.isChatCollapsed {
                    Button("Clear") { viewModel.clearBuilderConversation() }
                        .controlSize(.mini)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)

            if !viewModel.isChatCollapsed {
                CenterWorkspaceChat(viewModel: viewModel)
                    .frame(minHeight: 120, maxHeight: 200)
            }
        }
    }

    // MARK: - Build Output Section

    @ViewBuilder
    private var buildOutputSection: some View {
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
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                BuildOutputView(coordinator: viewModel.buildPipelineCoordinator)
                    .frame(minHeight: 150, maxHeight: 220)
            }
        }
    }
}

// MARK: - AI Chat View

struct CenterWorkspaceChat: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.builderMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(6)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: viewModel.builderMessages.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        scrollProxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(inputPlaceholder, text: $viewModel.builderDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { viewModel.sendBuilderPrompt() }

                Button("Send") { viewModel.sendBuilderPrompt() }
                    .controlSize(.small)
                    .disabled(viewModel.builderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

// MARK: - Strategy Panel

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

// MARK: - Drop Empty State

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

            Text("No mockup yet? Describe your app idea in AI Chat and send it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#1A1D23", fallback: Color(nsColor: .windowBackgroundColor)).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isTargeted ? Color.blue : Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [8, 6])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
