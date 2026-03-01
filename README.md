# ImageElementStudio

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange) ![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Tests 382](https://img.shields.io/badge/tests-382-brightgreen) ![Zero Dependencies](https://img.shields.io/badge/dependencies-0-green) ![License MIT](https://img.shields.io/badge/license-MIT-lightgrey)

A macOS SwiftUI application that transforms design screenshots and text-based ideas into production-ready code scaffolds for iOS, macOS, and web platforms. Upload a PNG, describe an app idea, or import a Figma file -- ImageElementStudio analyzes, infers semantics, generates blueprints, and exports runnable multi-platform code.

## Quick Start

```bash
# Build
swift build

# Run the app
swift run

# Run all 382 tests
swift test

# Build and test via Makefile
make all
```

### Open in Xcode

1. Open Xcode and choose **File > Open**.
2. Select the `ImageElementStudio` directory.
3. Run the `ImageElementStudio` scheme.

### API Key Setup

AI-powered code generation requires an Anthropic API key. Set it via the Settings view (menu bar) or environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
swift run
```

Optional OpenAI key enables enhanced semantic analysis:

```bash
export OPENAI_API_KEY="sk-..."
```

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for full configuration details.

## Features

### Design Analysis Pipeline
- **Vision OCR** and rectangle detection for UI element extraction
- **Semantic role mapping**: navigation, KPI, chart, table, CTA, heading, and 20+ roles
- **Product scope inference**: app type, intent, capabilities, roadmap
- **Blueprint inference**: controls, states, suggested artboards, mirror score

### Idea-to-App Generation
- Describe an app idea in chat or via menu command
- Strategy interview flow refines vision, users, features, and scope
- Auto-generates wireframe artboards with tokenized design elements
- No design file required

### Multi-Platform Build Export
- **iOS**: SwiftUI app with XcodeGen project configuration
- **macOS**: SwiftUI app with Swift Package Manager
- **Web**: HTML/CSS/JS with optional Node.js build
- Full-stack runs generate all three targets in a single timestamped bundle

### AI Code Generation
- Claude-powered multi-file app generation (Sonnet for speed, Opus for quality)
- Architecture planning, sequential file generation, and automatic validation
- Code validation: balanced braces, required imports, AI artifact detection
- Auto-fix loop: up to 3 AI-assisted attempts to resolve build errors

### Pro Editing
- Multi-select, marquee selection, alignment (6 directions), distribution
- Resize handles, rotation, snap-to-grid, keyboard shortcuts
- Component system with variant axes, state mapping, and instance overrides
- Design token editing with revision history and rollback

### Supported Imports
- **Raster**: PNG, JPG/JPEG, HEIC, TIFF, GIF (any format NSImage supports)
- **Vector**: PDF, AI, EPS, SVG (via QuickLook fallback)
- **Structured**: FIG/JSON with node geometry (imports layers as elements with style metadata)

## Enterprise Features

### Quality Gates
- CI-style quality gate combining smoke checks, design-code diffs, benchmarks, and review approval into a composite score (0-100)
- Configurable pass (85+), warning (65-84), and fail (<65) thresholds
- Blocking issue detection: smoke pass rate, high-impact drifts, unapproved reviews, overdue comments

### Build Quality Artifacts
- Deterministic manifest hashing (SHA256 via CryptoKit) for reproducible builds
- Smoke checks validating scaffold and full-app output integrity
- Design-code diff reports measuring drift between design intent and generated code
- `enterprise-readiness-report.json` with weighted checks, blockers, and recommended actions

### Benchmark System
- Pro editing benchmark runner measuring alignment, distribution, resize, rotation, and selection operations
- History tracking (up to 40 runs) with trend scoring (improving/stable/regressing)
- Median latency tracking and pass-rate trend charts
- Standalone `benchmark-trend-report.json` artifact on each build run

### Review and Collaboration
- Review comments with assignee, due date, and overdue highlighting
- Approval gate (pending/approved/changes-requested) blocking build export until approved
- Bulk resolve/clear actions
- Review gate integrated into quality score

### Interop and Export
- Full project package save/load (JSON)
- Interop export packages with design tokens, components, benchmarks, and review state
- Import loss reports quantifying fidelity loss from structured design imports
- `full-stack-summary.json` with per-target pass/fail and aggregate scores

## Architecture

Three-column SwiftUI layout driven by `StudioViewModel` coordinating 12+ domain services, 9 pipeline engines, and Xcode build toolchain integration. Services are stateless -- cross-service coordination flows through the ViewModel via Combine forwarding and callback closures.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full dependency graph and data flow.

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, service graph, data flow, key patterns |
| [CONFIGURATION.md](docs/CONFIGURATION.md) | Build requirements, API keys, file paths, pipeline modes |
| [STUDIO_WORKFLOW.md](docs/STUDIO_WORKFLOW.md) | Menu actions, project memory model, save/export behavior |
| [TESTING.md](docs/TESTING.md) | Test suite overview, patterns, coverage, how to add tests |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common errors and solutions |
| [SECURITY.md](docs/SECURITY.md) | API key storage, data handling, network security, sandboxing |

## Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS       | 14.0 (Sonoma) |
| Swift       | 6.2 |
| Xcode       | 16+ (for iOS build pipeline) |

Zero external dependencies -- uses only Apple system frameworks (SwiftUI, AppKit, Vision, Security, CryptoKit, UniformTypeIdentifiers, PDFKit, QuickLookThumbnailing).

## Project Structure

```
Sources/ImageElementStudio/
  |-- Models/          12 model files (canvas, analysis, build, tokens, etc.)
  |-- Services/        12 service files + scaffold generators
  |-- Pipeline/         9 engine files (analysis, semantic, blueprint, mockup)
  |-- AI/               7 files (Claude API, code generation, validation, prompts)
  |-- Xcode/            3 files (build pipeline, simulator, toolchain)
  |-- Persistence/      1 file (project memory store)
  |-- Views/           17 SwiftUI view files
  |-- StudioViewModel   7 files (core + 6 domain extensions)
  |-- Constants.swift   Centralized magic numbers

Tests/ImageElementStudioTests/
  |-- 22 test files    382 unit tests across 22 test suites
```

## License

MIT License. See [LICENSE](LICENSE) for details.
