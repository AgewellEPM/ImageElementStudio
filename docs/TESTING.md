# Testing

Test suite documentation for ImageElementStudio.

## Running Tests

### Command Line

```bash
# Run the full test suite (382 tests)
swift test

# Run via Makefile
make test

# Run a specific test file
swift test --filter CanvasServiceTests

# Run a specific test method
swift test --filter CanvasServiceTests/testAlignSelectedElementLeftSetsXToZero

# Clean before testing (if you hit stale build artifacts)
swift package clean && swift test
```

### Xcode

1. Open `/Users/luke/ImageElementStudio` in Xcode.
2. Select the `ImageElementStudio` scheme.
3. Press **Cmd+U** to run all tests.
4. Use the Test Navigator (Cmd+6) to run individual tests.

## Test Suite Overview

The test suite contains **382 unit tests** across **22 test files** in a single test target (`ImageElementStudioTests`).

| Test File                          | Tests | What It Covers                                              |
|------------------------------------|-------|-------------------------------------------------------------|
| `BuildExportServiceTests.swift`    | 25    | Slugification, unique strings, quality gate scoring, build confirmation, deterministic manifests |
| `BenchmarkServiceTests.swift`      | 24    | Status lines, history management, trend scoring, pass rate calculation, latency tracking |
| `ReviewServiceTests.swift`         | 23    | Comment CRUD, resolution toggling, approval states, review gate blocking, bulk operations, overdue detection |
| `DesignTokenServiceTests.swift`    | 23    | Token CRUD, revision history, rollback, global propagation, radius clamping |
| `CodeValidatorTests.swift`         | 22    | Code fence stripping, balanced brace detection, import checking, artifact detection, full validation pipeline |
| `CanvasServiceTests.swift`         | 21    | Element alignment, distribution, nudge, snap-to-grid, resize, rotation, component integrity |
| `ChatServiceTests.swift`           | 21    | Initial messages, chat history, builder commands, command parsing, project name handling |
| `AICodeGenerationModelsTests.swift`| 17    | JSON round-trip encoding, model IDs, generation quality enum, generation state transitions, file role enum, architecture plan decoding |
| `AppLoggerTests.swift`             | 6     | Subsystem reverse-DNS convention, category inventory guard, category raw values matching log filter strings |
| `ComponentServiceTests.swift`      | 16    | Component creation, variant axes, instance overrides, state mapping, element ID validation |
| `ScaffoldGeneratorTests.swift`     | 16    | iOS/macOS/Web scaffold generation, build manifest schema, smoke check generation, full-app output |
| `SelectionServiceTests.swift`      | 15    | Element selection, multi-select, marquee selection, deselection, selection state queries |
| `PromptBuilderTests.swift`         | 12    | System prompts, architecture planning prompts, file generation prompts, error fix prompts |
| `GeneratedProjectWriterTests.swift`| 11    | Directory creation, file writing, project.yml (iOS), Package.swift (macOS), app-spec.json, empty file handling |
| `StudioSnapshotTests.swift`        | 8     | Deterministic manifest snapshots, app spec snapshots, diff snapshots, review gate integration, quality gate integration, full-stack summary, enterprise readiness |

## Test Organization

### File Naming Convention

Test files follow the pattern `<ServiceOrClass>Tests.swift` and are located in:

```
Tests/ImageElementStudioTests/
  |-- AICodeGenerationModelsTests.swift
  |-- BenchmarkServiceTests.swift
  |-- BuildExportServiceTests.swift
  |-- CanvasServiceTests.swift
  |-- ChatServiceTests.swift
  |-- CodeValidatorTests.swift
  |-- ComponentServiceTests.swift
  |-- DesignTokenServiceTests.swift
  |-- GeneratedProjectWriterTests.swift
  |-- PromptBuilderTests.swift
  |-- ReviewServiceTests.swift
  |-- ScaffoldGeneratorTests.swift
  |-- SelectionServiceTests.swift
  |-- StudioSnapshotTests.swift
```

### Test Naming Convention

Test methods use the pattern `test<Method><Condition><ExpectedResult>`:

```swift
func testSlugifiedConvertsSpacesToDashes()
func testAlignSelectedElementLeftSetsXToZero()
func testQualityGateSummaryPassStatusAbove85()
func testWriteProjectThrowsForEmptyFileList()
func testBenchmarkStatusLineWhenNoReport()
```

## Test Patterns

### @MainActor Tests

Most service tests are marked `@MainActor` because the services use `@MainActor` isolation:

```swift
@MainActor
final class CanvasServiceTests: XCTestCase {
    func testAlignSelectedElementLeftSetsXToZero() {
        let service = CanvasService()
        // ...
    }
}
```

Services that are not `@MainActor`-bound (like `CodeValidator`, `AICodeGenerationModels`) use plain `XCTestCase`.

### Factory Helpers

Tests use private helper methods to construct test fixtures:

```swift
private func makeService() -> ReviewService {
    ReviewService()
}

private func makeElement(id: UUID, x: Double, y: Double, width: Double = 100, height: Double = 50) -> CanvasElement {
    CanvasElement(
        id: id, name: "Element", kind: .shape,
        frame: ElementFrame(x: x, y: y, width: width, height: height),
        confidence: 0.9, content: nil, tags: [],
        semanticRole: .unknown, semanticReason: "test"
    )
}
```

### Deterministic UUIDs

Tests use fixed UUIDs for reproducibility:

```swift
private let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000600")!
private let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
```

### Temporary Directories

Tests that write to disk use temporary directories with cleanup:

```swift
final class GeneratedProjectWriterTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratedProjectWriterTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }
}
```

### Snapshot Testing Pattern

`StudioSnapshotTests` uses a "golden snapshot" pattern where a fully-configured `StudioViewModel` is compared against expected deterministic values:

```swift
func testManifestSnapshotMatchesExpectedFixture() {
    let viewModel = makeSnapshotViewModel()
    let snapshot = viewModel.deterministicManifestSnapshot(for: .ios)
    XCTAssertEqual(snapshot, StudioViewModel.DeterministicManifestSnapshot(
        schemaVersion: 4,
        target: "ios",
        // ... all expected fields
    ))
}
```

### Inout Parameter Testing

Canvas and component tests pass artboard arrays as `inout` parameters to verify mutations:

```swift
func testAlignSelectedElementLeftSetsXToZero() {
    let service = makeService()
    var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 200, y: 100)])]

    service.alignSelectedElementLeft(
        artboards: &artboards,
        activeArtboardIndex: 0,
        selectedElementIDs: [idA]
    )

    XCTAssertEqual(artboards[0].elements[0].frame.x, 0)
}
```

## What Is Covered

### Well-Covered Areas

- **Canvas operations**: Alignment (6 directions), distribution (H/V), nudge, snap-to-grid, resize (all handles), rotation
- **Build export**: Slugification, quality gate scoring with all signal combinations, deterministic manifests, build confirmation lines
- **Code validation**: Brace balancing (including string/comment awareness), import checking, artifact detection, fence stripping
- **Review system**: Full CRUD lifecycle, approval states, review gate blocking logic, overdue detection, bulk operations
- **Benchmark system**: History management, trend scoring (improving/stable/regressing), pass rate, latency tracking, auto-fix
- **Design tokens**: Token CRUD, revision history with rollback, global propagation, radius value clamping
- **Components**: Creation, variant axes, instance overrides, state mapping, orphan cleanup
- **Chat service**: Message initialization, history management, builder command parsing
- **Project writer**: All three target types (iOS/macOS/Web), directory structure, file contents, error cases
- **Prompt builder**: System prompts, architecture prompts, file generation prompts
- **Selection service**: Single/multi/marquee selection, deselection
- **AI models**: Model ID mapping, quality enum, state machine transitions
- **Integration snapshots**: End-to-end manifest, app-spec, diff, quality gate, review gate, enterprise readiness

### Not Currently Covered

- **ImageAnalyzer**: Vision framework OCR and rectangle detection (requires image fixtures)
- **SemanticPipeline**: Orchestration of heuristic + remote + blueprint engines
- **HeuristicSemanticEngine**: Local semantic role inference
- **OpenAISemanticEngine**: Remote API calls (would require mocking)
- **AnthropicService**: API client (actor isolation, would require mocking)
- **DesignAssetImporter**: File import pipeline (requires fixture files)
- **ImageLoadingService**: NSOpenPanel interaction, drag-and-drop
- **ProjectMemoryStore**: Persistence to disk (tested indirectly via snapshot tests)
- **XcodeToolchainService**: Shell command execution
- **SimulatorService**: Simulator management
- **BuildPipelineCoordinator**: Multi-step build pipeline
- **StudioViewModel**: Most ViewModel methods (tested indirectly via service tests and snapshot tests)
- **Views**: SwiftUI views are not unit-tested

## How to Add New Tests

### 1. Create a Test File

Add a new file in `Tests/ImageElementStudioTests/` following the naming convention:

```swift
import XCTest
@testable import ImageElementStudio

@MainActor  // Add if the class under test is @MainActor
final class MyServiceTests: XCTestCase {

    private func makeService() -> MyService {
        MyService()
    }

    func testSomeBehavior() {
        let service = makeService()
        // Arrange, Act, Assert
    }
}
```

### 2. Use @testable import

All test files use `@testable import ImageElementStudio` to access internal types.

### 3. Follow Existing Patterns

- Use `makeService()` factory methods for the class under test.
- Use `makeElement()`, `makeArtboard()`, etc. factory methods for test fixtures.
- Use deterministic UUIDs (`UUID(uuidString: "00000000-...")!`) for reproducibility.
- Use temporary directories with `setUp()`/`tearDown()` for file system tests.
- Name tests descriptively: `test<Method><Scenario><Expected>`.

### 4. Run and Verify

```bash
# Run just your new test file
swift test --filter MyServiceTests

# Run the full suite to check for regressions
swift test
```

### 5. CI Integration

Tests run automatically in GitHub Actions CI on every push and pull request. The CI workflow runs `swift test` on macOS with the same Swift toolchain version used for development. Ensure all tests pass before merging.
