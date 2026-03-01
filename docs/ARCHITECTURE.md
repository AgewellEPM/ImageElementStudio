# Architecture

ImageElementStudio is a macOS SwiftUI application that transforms design screenshots (or text-based ideas) into production-ready code scaffolds for iOS, macOS, and web platforms.

## High-Level Architecture

```
ImageElementStudioApp (@main)
  |
  v
StudioViewModel (central coordinator, @MainActor)
  |
  +-- Services (domain-specific logic, each ObservableObject)
  |     |-- CanvasService          -- element manipulation, alignment, resize, artboard helpers
  |     |-- SelectionService       -- element and marquee selection state
  |     |-- ReviewService          -- design review comments, approval gate
  |     |-- BenchmarkService       -- pro-editing benchmark runner and trend scoring
  |     |-- DesignTokenService     -- design token editing, rollback, propagation
  |     |-- ComponentService       -- component specs, instances, variants, overrides
  |     |-- ChatService            -- user/builder chat, command parsing
  |     |-- StrategyService        -- product strategy interview flow
  |     |-- BuildExportService     -- build manifest, quality gate, full-stack export
  |     |-- ExportService          -- JSON/project package export
  |     |-- ProjectService         -- save/load project packages
  |     |-- ImageLoadingService    -- image/design file loading, drag-and-drop
  |     +-- ScaffoldGenerator      -- code scaffold generation (iOS, macOS, web)
  |
  +-- Pipeline (analysis and inference engines)
  |     |-- ImageAnalyzer          -- Vision OCR + rectangle detection
  |     |-- SemanticPipeline       -- orchestrates heuristic + remote + blueprint engines
  |     |-- HeuristicSemanticEngine -- local semantic role inference
  |     |-- OpenAISemanticEngine   -- remote AI semantic enrichment (OpenAI Vision)
  |     |-- BlueprintInferenceEngine -- control/state inference for build blueprints
  |     |-- MockupGenerator        -- design token + component mockup generation
  |     |-- ProductStrategistEngine -- strategy interview question generation
  |     |-- IdeaPlanner            -- text-to-wireframe generation
  |     +-- DesignAssetImporter    -- Figma/Sketch/SVG/AI file import
  |
  +-- AI (code generation)
  |     |-- CodeGenerationPipeline -- multi-file AI code generation orchestrator
  |     |-- AnthropicService       -- Claude API client
  |     |-- CodeValidator          -- Swift syntax validation
  |     |-- PromptBuilder          -- prompt construction from canvas state
  |     |-- GeneratedProjectWriter -- writes generated files to disk
  |     +-- KeychainService        -- API key storage and retrieval
  |
  +-- Xcode (build toolchain integration)
  |     |-- BuildPipelineCoordinator -- xcodegen + build + simulator launch
  |     |-- XcodeToolchainService    -- xcodebuild/swift build runner
  |     +-- SimulatorService         -- iOS simulator boot and app install
  |
  +-- Persistence
  |     +-- ProjectMemoryStore     -- project memory serialization to Application Support
  |
  +-- Views (SwiftUI view layer)
        |-- StudioRootView         -- top-level 3-column layout
        |-- ChatSidebarPane        -- left sidebar with chat and builder tabs
        |-- AnalyzerCenterPane     -- center pane with canvas and analysis
        |-- ArtboardSidebarPane    -- right sidebar with artboard/element inspector
        |-- CanvasViews            -- image overlay and emulator canvas
        |-- AppEmulatorElement     -- token-aware element rendering
        +-- [10+ panel views]      -- build quality, review, benchmark, etc.
```

## Service Dependency Graph

Services are owned by `StudioViewModel` and do not reference each other directly. Cross-service coordination flows through the ViewModel via Combine `objectWillChange` forwarding and callback closures.

```
StudioViewModel
  |
  |-- owns --> CanvasService
  |-- owns --> SelectionService
  |-- owns --> ReviewService
  |-- owns --> BenchmarkService
  |-- owns --> DesignTokenService
  |-- owns --> ComponentService
  |-- owns --> ChatService
  |-- owns --> StrategyService (depends on ProductStrategistEngine)
  |-- owns --> BuildExportService (depends on ScaffoldGenerator)
  |-- owns --> ExportService
  |-- owns --> ProjectService
  |-- owns --> ImageLoadingService
  |
  |-- owns --> ImageAnalyzer
  |-- owns --> SemanticPipeline (depends on HeuristicSemanticEngine,
  |               OpenAISemanticEngine, BlueprintInferenceEngine)
  |-- owns --> MockupGenerator
  |-- owns --> IdeaPlanner
  |-- owns --> DesignAssetImporter
  |
  |-- owns --> CodeGenerationPipeline (depends on AnthropicService, PromptBuilder,
  |               CodeValidator, GeneratedProjectWriter)
  |-- owns --> BuildPipelineCoordinator (depends on XcodeToolchainService, SimulatorService)
  |
  +-- owns --> ProjectMemoryStore
```

All service `objectWillChange` publishers are forwarded to the ViewModel's `objectWillChange` via Combine `.sink` subscriptions so that SwiftUI views update when any service state changes.

## Data Flow

### Image-Based Flow

```
User uploads PNG/JPG/PDF/AI/SVG/FIG
  |
  v
ImageLoadingService.loadDesignAsset()
  |-- (structured files) --> DesignAssetImporter.importAsset()
  |-- (image files) ------> NSImage loaded into selectedImage
  |
  v
ImageAnalyzer.analyze(cgImage:filename:)
  |-- VNRecognizeTextRequest (OCR)
  |-- VNDetectRectanglesRequest (shape detection)
  |-- Produces AnalysisDocument with artboard + elements
  |
  v
SemanticPipeline.enrich(document:imageData:)
  |-- HeuristicSemanticEngine.interpret() -- local role inference
  |-- OpenAISemanticEngine.interpret()    -- remote AI enrichment (optional)
  |-- BlueprintInferenceEngine.infer()    -- control/state mapping
  |-- Produces SemanticPipelineResult with scope + blueprint
  |
  v
StudioViewModel.applySemantic(result:)
  |-- Updates artboards, scope, blueprint
  |-- Records memory snapshot
  |-- Triggers realtime build setup
```

### Idea-Based Flow

```
User types app idea (e.g., "fitness tracker")
  |
  v
StrategyService.startStrategyFromIdea()
  |-- ProductStrategistEngine runs interview
  |-- Multiple Q&A stages: vision, users, features, scope
  |-- Produces StrategySpec
  |
  v
StrategyService.finalizeStrategySpec()
  |-- Produces ProductScopeSnapshot from spec
  |
  v
IdeaPlanner.plan(from:)
  |-- Generates artboards with wireframe elements
  |-- Infers blueprint controls and states
  |
  v
MockupGenerator.generate(from:strategySpec:preset:)
  |-- Applies design tokens (Apple HIG or Adobe Expressive)
  |-- Maps elements to component specs
  |-- Produces tokenized artboards + DesignTokenSet
```

### Build & Export Flow

```
StudioViewModel state (artboards + scope + blueprint + tokens + components)
  |
  v
BuildExportService.setupBuild(for:context:)
  |-- Computes deterministic hash
  |-- Generates build manifest JSON
  |-- ScaffoldGenerator writes platform scaffold code
  |-- ScaffoldGenerator writes full-app code
  |-- Runs smoke checks
  |-- Produces BuildQualityReport + QualityGateSummary
  |
  v (full-stack)
BuildExportService.generateFullStackBuild(context:)
  |-- Runs setupBuild for web, iOS, macOS
  |-- Computes FullStackBuildSummary
  |-- Computes EnterpriseReadinessReport
  |
  v (AI code generation)
CodeGenerationPipeline.generateApp(elements:artboards:...)
  |-- PromptBuilder constructs Claude prompt
  |-- AnthropicService sends to Claude API
  |-- CodeValidator validates generated Swift
  |-- GeneratedProjectWriter writes to disk
  |
  v
BuildPipelineCoordinator.runFullPipeline()
  |-- XcodeToolchainService runs xcodebuild or swift build
  |-- SimulatorService launches in iOS Simulator
```

## Key Patterns

### Context Structs

Services do not hold references to the ViewModel. Instead, context structs snapshot ViewModel state and are passed as parameters to service methods:

- `BenchmarkContext` -- snapshot for benchmark operations
- `BuildExportService.BuildContext` -- snapshot for build/export operations
- `ChatService.ChatContext` -- snapshot for chat response generation
- `ChatService.BuilderCommandContext` -- snapshot for builder command parsing
- `CanvasService.BuildStepContext` -- snapshot for build step computation

Each context struct has a convenience `init(from vm: StudioViewModel)` that captures a [weak vm] snapshot.

### Combine Forwarding

Every service that is `ObservableObject` has its `objectWillChange` forwarded to the ViewModel:

```swift
reviewService.objectWillChange
    .sink { [weak self] in self?.objectWillChange.send() }
    .store(in: &cancellables)
```

This allows views bound to the ViewModel to react to changes in any sub-service without the views knowing about the services.

### Callback-Based Mutations

Services that need to trigger side effects (e.g., appending chat messages, updating memory) receive closures from the ViewModel rather than referencing it directly:

```swift
strategyService.onAppendBuilderMessage = { [weak self] msg in
    self?.builderMessages.append(msg)
}
```

### Extension Splitting

The `StudioViewModel` is split across multiple files by domain:

| File                                  | Responsibility                                     |
|---------------------------------------|---------------------------------------------------|
| `StudioViewModel.swift`              | Properties, computed properties, init              |
| `StudioViewModel+Canvas.swift`       | Image loading, element selection, canvas editing   |
| `StudioViewModel+Build.swift`        | Strategy-driven build, full-stack, AI generation   |
| `StudioViewModel+Chat.swift`         | Chat send/builder prompt delegation                |
| `StudioViewModel+Internal.swift`     | Artboard helpers, JSON preview, state reset        |
| `StudioViewModel+ProjectIO.swift`    | Project management, save/load, export              |
| `StudioViewModel+ServiceDelegation.swift` | Thin forwarding to services                   |

### Constants

Magic numbers are centralized in `Constants.swift` using a caseless `enum Constants` with nested domain enums (e.g., `Constants.Benchmark.maxHistoryEntries`, `Constants.QualityGate.passScoreThreshold`).

## File Organization

```
Sources/ImageElementStudio/
  |-- ImageElementStudioApp.swift           -- @main app entry point
  |-- StudioViewModel.swift                 -- central ViewModel
  |-- StudioViewModel+*.swift               -- ViewModel extensions by domain
  |-- Constants.swift                       -- centralized magic numbers
  |
  |-- Models/
  |     |-- AnalysisModels.swift            -- AnalysisDocument, ProductScopeSnapshot
  |     |-- BenchmarkModels.swift           -- BenchmarkRunReport, trend types
  |     |-- BuildModels.swift               -- BuildBlueprint, quality gate types
  |     |-- CanvasModels.swift              -- Artboard, CanvasElement, ElementFrame
  |     |-- ChatModels.swift                -- ChatMessage
  |     |-- DesignTokenModels.swift         -- DesignTokenSet, TokenRevision
  |     |-- GeneratedAppModels.swift        -- GeneratedAppSpec, transitions
  |     |-- InteropModels.swift             -- InteropExportPackage, ImportLossReport
  |     |-- ProjectModels.swift             -- ProjectMemory, ProjectMemoryEntry
  |     |-- ReviewModels.swift              -- DesignReviewComment, approval state
  |     +-- StrategyModels.swift            -- StrategySession, StrategySpec, stages
  |
  |-- Services/
  |     |-- [12 service files]              -- domain-specific business logic
  |     |-- ScaffoldGenerator.swift         -- shared scaffold utilities
  |     +-- ScaffoldGenerator+*.swift       -- platform-specific scaffold (iOS, macOS, Web)
  |
  |-- Pipeline/
  |     +-- [9 engine files]               -- analysis, semantic, blueprint, mockup
  |
  |-- AI/
  |     +-- [7 files]                      -- Claude API, code generation, prompts
  |
  |-- Persistence/
  |     +-- ProjectMemoryStore.swift       -- JSON persistence to Application Support
  |
  |-- Xcode/
  |     +-- [3 files]                      -- build pipeline, simulator, toolchain
  |
  +-- Views/
        +-- [17 view files]               -- SwiftUI views and panels

Tests/ImageElementStudioTests/
  +-- [22 test files]                     -- 382 unit tests across 22 test suites
```
