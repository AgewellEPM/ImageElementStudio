# Configuration

## Build Requirements

| Requirement       | Minimum Version |
|-------------------|-----------------|
| macOS             | 14.0 (Sonoma)   |
| Swift             | 6.2             |
| Xcode             | 16+ (for AI code generation builds) |

The project is built with Swift Package Manager. No CocoaPods, Carthage, or external dependencies are required -- the only system frameworks used are AppKit, SwiftUI, Vision, CryptoKit, Security, and UniformTypeIdentifiers.

```bash
swift build          # Build the app
swift test           # Run the full test suite (382 tests)
swift run            # Launch the app from the command line
```

## API Key Setup

ImageElementStudio supports two AI providers. API keys are stored in the macOS Keychain and can be managed from the Settings view (menu bar: ImageElementStudio > Settings).

### Anthropic API Key (Required for AI Code Generation)

Used by `AnthropicService` for AI-powered code generation via the Claude API.

- **Models used**:
  - Fast mode: `claude-sonnet-4-5-20250929`
  - Quality mode: `claude-opus-4-6`
- **Required for**: "Generate App from Design" feature
- **Not required for**: image analysis, semantic pipeline, scaffold generation, build export

### OpenAI API Key (Optional)

Used by `OpenAISemanticEngine` for enhanced semantic analysis via the OpenAI Vision API.

- **Model used**: `gpt-4.1-mini`
- **Required for**: Remote AI semantic enrichment in the analysis pipeline
- **Fallback**: When no OpenAI key is configured, the pipeline uses local heuristic inference only (the `HeuristicSemanticEngine`)

### How Keys Are Resolved

`KeychainService.resolveAPIKey(for:)` resolves keys with this fallback chain:

1. **Keychain** (primary, persistent storage)
2. **Environment variable** (development/CI only, not persisted)

### Keychain Details

| Property        | Value                                 |
|-----------------|---------------------------------------|
| Service name    | `com.imageelementstudio.apikeys`      |
| Account (Anthropic) | `anthropic-api-key`              |
| Account (OpenAI)    | `openai-api-key`                 |
| Accessibility   | `kSecAttrAccessibleAfterFirstUnlock`  |

Keys can be stored, retrieved, and deleted programmatically via `KeychainService`:

```swift
// Store
try KeychainService.store(key: .anthropicAPIKey, value: "sk-ant-...")

// Retrieve
let key = KeychainService.retrieve(key: .anthropicAPIKey)

// Resolve (Keychain -> environment fallback)
let key = KeychainService.resolveAPIKey(for: .anthropicAPIKey)

// Delete
try KeychainService.delete(key: .anthropicAPIKey)
```

## Environment Variables

These environment variables are checked as fallbacks when no Keychain entry exists. They are intended for development and CI use only.

| Variable            | Purpose                              |
|---------------------|--------------------------------------|
| `ANTHROPIC_API_KEY` | Fallback Anthropic API key           |
| `OPENAI_API_KEY`    | Fallback OpenAI API key              |

## UserDefaults Keys

The app uses a small number of UserDefaults keys for lightweight preferences:

| Key                                         | Type     | Default            | Purpose                                      |
|---------------------------------------------|----------|--------------------|----------------------------------------------|
| `ImageElementStudio.ActiveProjectName`      | `String` | `"Default Project"` | Persists the active project name across launches |
| `generationQuality`                         | `String` | `"fast"`           | AI generation quality setting (`fast` or `quality`) |
| `useAICodeGeneration`                       | `Bool`   | `true`             | Whether to use AI code generation or template fallback |
| `KeychainService.migrationCompleted`        | `Bool`   | `false`            | One-time flag indicating API keys have been migrated from UserDefaults to Keychain |

### Legacy Keys (Migrated)

The following UserDefaults keys were used in older versions and are automatically migrated to the Keychain on first launch by `KeychainService.migrateKeysFromUserDefaultsIfNeeded()`:

| Legacy Key          | Migrated To                           |
|---------------------|---------------------------------------|
| `ANTHROPIC_API_KEY` | Keychain: `anthropic-api-key`         |
| `OPENAI_API_KEY`    | Keychain: `openai-api-key`            |

After migration, the legacy UserDefaults entries are removed.

## File System Paths

### Project Memory Storage

Project memory (snapshots, strategy sessions, decision logs) is persisted as JSON in Application Support:

```
~/Library/Application Support/ImageElementStudio/projects/<project-id>/project-memory.json
```

A legacy path is also checked for the default project:

```
~/Library/Application Support/ImageElementStudio/project-memory.json
```

### Build Output

Build artifacts (manifests, scaffolds, full-app code, quality reports) are written to the Documents directory:

```
~/Documents/ImageElementStudioBuilds/<project-slug>/<timestamp>-<target>/
~/Documents/ImageElementStudioBuilds/<project-slug>/realtime-<target>/
~/Documents/ImageElementStudioBuilds/<project-slug>/<timestamp>-full-stack/
```

### AI-Generated Projects

AI-generated app projects are written to:

```
~/Documents/ImageElementStudioApps/<app-name>/
```

## Pipeline Modes

The semantic analysis pipeline can operate in three modes, selectable via the builder chat or strategy interview:

| Mode     | Behavior                                                |
|----------|---------------------------------------------------------|
| `hybrid` | Local heuristic inference + remote AI enrichment (default) |
| `auto`   | Fully automated (set during auto-run strategy sessions) |
| `local`  | Local heuristic inference only, no remote API calls     |

## Design Style Presets

Two mockup style presets are available, affecting typography, radius, shadow, and motion tokens:

| Preset              | Typography Font Family     | Control Radius | Panel Radius |
|---------------------|---------------------------|----------------|--------------|
| `apple_hig`         | SF Pro (Rounded/Text/Display) | 10            | 14           |
| `adobe_expressive`  | Neue Haas Grotesk / Acumin Pro | 14          | 18           |

## Build Targets

Three build targets are supported for scaffold and full-app generation:

| Target  | Output Format            | Build System        |
|---------|-------------------------|---------------------|
| `ios`   | SwiftUI iOS app         | XcodeGen + xcodebuild |
| `macos` | SwiftUI macOS app       | Swift Package Manager |
| `web`   | HTML/CSS/JS web app     | Node.js (optional)  |

## Build Manifest Schema

The current build manifest schema version is **4** (defined in `Constants.BuildManifest.schemaVersion`). The manifest is written as `build-manifest.json` in each build output directory.
