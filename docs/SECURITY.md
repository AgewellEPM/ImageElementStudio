# Security

Security posture and data handling practices for ImageElementStudio.

## API Key Storage

### macOS Keychain (Primary)

API keys are stored in the macOS Keychain using the Security framework (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`).

| Property          | Value                                    |
|-------------------|------------------------------------------|
| Service name      | `com.imageelementstudio.apikeys`         |
| Accessibility     | `kSecAttrAccessibleAfterFirstUnlock`     |
| Anthropic account | `anthropic-api-key`                      |
| OpenAI account    | `openai-api-key`                         |

Keys are accessible after the first device unlock and persist across app launches. The `kSecAttrAccessibleAfterFirstUnlock` setting means keys are available after the user logs in but not while the device is locked at the login screen.

### Environment Variable Fallback (Development/CI)

When no Keychain entry exists, `KeychainService.resolveAPIKey(for:)` checks environment variables as a fallback:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`

Environment variables are not persisted and are intended only for development and CI environments. They are never written to disk by the application.

### Legacy Migration

Older versions stored API keys in `UserDefaults` (plaintext on disk). The `migrateKeysFromUserDefaultsIfNeeded()` method runs once at launch to move any existing keys from `UserDefaults` to the Keychain, then deletes the `UserDefaults` entries. A `KeychainService.migrationCompleted` flag in `UserDefaults` prevents repeated migration attempts.

### Recommendations

- **Never commit API keys** to source control.
- Use the Keychain for production deployments.
- Use environment variables only in CI/CD pipelines where Keychain access is not available.

## Data Handling

### What is stored locally

| Data                     | Location                                                                | Format    |
|--------------------------|-------------------------------------------------------------------------|-----------|
| API keys                 | macOS Keychain                                                          | Encrypted |
| Project memory           | `~/Library/Application Support/ImageElementStudio/projects/<id>/`       | JSON      |
| Build artifacts          | `~/Documents/ImageElementStudioBuilds/<slug>/`                          | Files     |
| AI-generated projects    | `~/Documents/ImageElementStudioApps/<name>/`                            | Files     |
| User preferences         | `UserDefaults` (5 keys: project name, generation quality, AI toggle, migration flag, onboarding flag) | Plist     |

Project memory files contain:
- Analysis snapshots (app type, scope summaries, element counts)
- Strategy sessions and decision logs
- Working hypothesis and product scope
- No raw image data is stored in memory files

### What is sent to external APIs

**Anthropic Claude API** (`https://api.anthropic.com/v1/messages`):
- System prompts containing app architecture instructions
- User prompts containing element descriptions, artboard data, design tokens, component specs, and blueprint data
- Optionally: base64-encoded screenshot images (PNG) for multimodal code generation
- API key sent via `x-api-key` header

**OpenAI Vision API** (`https://api.openai.com/v1/chat/completions`):
- System prompt for UI analysis
- Serialized element data (name, kind, frame coordinates, first 90 chars of text) -- up to 140 elements
- Base64-encoded JPEG preview of the design screenshot (resized to max 1400px, 78% quality)
- API key sent via `Authorization: Bearer` header

### What is NOT sent to external APIs

- Raw project files (FIG, AI, Sketch, PSD files)
- Full-resolution original images (images are downscaled before sending)
- Keychain data or other API keys
- File system paths or user account information
- Project memory history or decision logs

## Network Security

### HTTPS

All external API communication uses HTTPS:
- Anthropic: `https://api.anthropic.com/v1/messages`
- OpenAI: `https://api.openai.com/v1/chat/completions`

Connections use the system `URLSession` with default TLS configuration (TLS 1.2+ as enforced by App Transport Security).

### Certificate Pinning

Certificate pinning is **not currently implemented**. The app relies on the macOS system trust store for certificate validation. This means:
- The app trusts any certificate trusted by the system.
- A compromised system CA could theoretically intercept API traffic.
- For enterprise deployments requiring cert pinning, a custom `URLSessionDelegate` with pinned certificates would need to be added to `AnthropicService` and `OpenAISemanticEngine`.

### Retry and Error Handling

The `AnthropicService` includes retry logic for transient failures:
- HTTP 429 (rate limited): retries with `Retry-After` header or 2s/4s/8s backoff
- HTTP 529 (overloaded): retries with exponential backoff (2s, 4s, 8s)
- Maximum 3 retry attempts before surfacing the error

Error responses from APIs are parsed for display but not logged to disk.

## Input Validation

### Currently Validated

- **API key encoding**: `KeychainService.store()` validates UTF-8 encoding before Keychain storage.
- **API key format**: `KeychainService.store()` calls `InputValidator.isAPIKeyFormatValid()` before storing any key. This checks length (20-256 characters), rejects control characters, and validates against known provider prefixes (`sk-`, `sk-ant-`, `sk-proj-`, `xai-`, `ollama-`). Keys without a known prefix are accepted only if they consist entirely of alphanumeric characters, hyphens, and underscores. Invalid keys are rejected with a `KeychainError.invalidKeyFormat` error before reaching the Keychain.
- **File path traversal**: `InputValidator.isPathSafe()` rejects paths containing traversal patterns (`../`, `..\`), null bytes, control characters, and paths targeting sensitive system directories (`/etc/`, `/var/`, `/usr/`, `/bin/`, `/sbin/`, `/System/`, `/Library/`, `/private/`). This check is enforced in `ImageLoadingService` (file import), `ExportService` (project and interop package export, 2 call sites), and `ProjectService` (project save). A companion `InputValidator.sanitizePath()` method is available for stripping dangerous components rather than rejecting outright.
- **Project name validation**: `StudioViewModel+ProjectIO` calls `InputValidator.sanitizeProjectName()` and `InputValidator.isProjectNameValid()` when setting or creating projects. Names are restricted to letters, digits, spaces, hyphens, underscores, periods, and parentheses, capped at 128 characters, and names consisting entirely of dots/dashes/spaces are rejected.
- **File import formats**: `DesignAssetImporter` validates file extensions and attempts multiple import strategies (raster, vector, structured, QuickLook) before rejecting unsupported formats.
- **Structured import depth**: The structured design parser limits tree traversal to depth 40 to prevent stack overflow from deeply nested or recursive JSON.
- **Structured import node count**: A maximum of 450 nodes are imported from structured design files.
- **Element serialization for API**: Element text content is truncated to 90 characters and element count is capped at 140 before sending to the OpenAI API.
- **Image resize for API**: Images are downscaled to a maximum dimension of 1400px before base64 encoding for API transmission.
- **Code generation validation**: `CodeValidator` checks generated code for balanced braces, required imports, non-empty content, and AI artifacts (placeholder comments, leftover markdown fences).
- **Bundle ID sanitization**: `GeneratedProjectWriter` strips non-alphanumeric characters from app names when generating bundle IDs and product names.
- **Project ID slugification**: `ProjectMemoryStore` normalizes project names to lowercase alphanumeric slugs, capped at 48 characters.

### Not Currently Validated

- **Image file size limits**: There is no explicit file size check before import. Very large files may cause memory pressure.
- **JSON response size**: API responses are not size-limited before parsing. The SSE parser caps error body collection at 4096 bytes. (Note: `InputValidator.isJSONSafe()` exists with a 10 MB default limit and structural checks, but is not yet called from production code.)
- **User input in chat**: Chat messages are passed directly to service methods without sanitization. This is low-risk since they are displayed in SwiftUI `Text` views (which do not interpret HTML) and sent to AI APIs as plain text.

## File System Access

### Read Locations

- User-selected files via `NSOpenPanel` (any location the user chooses)
- `~/Library/Application Support/ImageElementStudio/` (project memory)

### Write Locations

- `~/Library/Application Support/ImageElementStudio/projects/<id>/` (project memory JSON)
- `~/Documents/ImageElementStudioBuilds/<slug>/` (build artifacts, scaffolds, full-app code)
- `~/Documents/ImageElementStudioApps/<name>/` (AI-generated projects)
- User-selected locations via `NSSavePanel` (project packages, JSON exports, interop packages)
- `NSTemporaryDirectory()` (simulator screenshots, temporary build files)

### Process Execution

The `XcodeToolchainService`, `SimulatorService`, and `BuildPipelineCoordinator` execute shell commands via `Process` with `/bin/zsh -lc`. Commands executed include:
- `xcode-select -p`
- `xcodebuild -version`, `xcodebuild -showsdks`, `xcodebuild -project ...`
- `xcrun --find xcodebuild`
- `xcrun simctl list devices`, `xcrun simctl boot`, `xcrun simctl install`, `xcrun simctl launch`
- `which xcodegen`, `xcodegen generate`
- `swift build`
- `open -a Simulator`

Shell arguments containing file paths are escaped using single-quote wrapping with internal quote escaping to prevent injection.

## Sandboxing

ImageElementStudio currently runs as a **non-sandboxed** macOS application. This is required because:

1. **Shell process execution**: The build pipeline launches `xcodebuild`, `simctl`, `xcodegen`, and `swift build` via `Process`, which is not permitted in sandboxed apps.
2. **Arbitrary file system access**: Build output is written to `~/Documents/` and project memory to `~/Library/Application Support/` without user-granted bookmarks.
3. **Simulator interaction**: Booting, installing, and launching apps in the iOS Simulator requires full system access.

### Implications

- The app has full read/write access to the file system (subject to standard Unix permissions).
- The app can execute arbitrary processes.
- Users should be aware that the app is not sandboxed when evaluating its trust profile.

### Future Considerations

For enterprise distribution:
- Consider App Sandbox with temporary exceptions (`com.apple.security.temporary-exception.*`) for essential operations.
- Move build pipeline execution to a sandboxed helper tool or XPC service.
- Use security-scoped bookmarks for user-selected file locations.

## Known Security Limitations

1. **No certificate pinning**: API traffic relies on system trust store only.
2. **No file size limits on import**: Large files could cause memory pressure.
3. **Non-sandboxed execution**: The app has unrestricted file system and process access.
4. **Shell command execution**: Build tools are invoked via shell; compromised PATH could theoretically redirect commands.
5. **No audit logging**: API calls, file writes, and process executions are not logged to an audit trail.
6. **Plaintext project data**: Project memory, build artifacts, and generated code are stored as unencrypted JSON and source files on disk.
7. **API keys in memory**: API keys are held in memory as `String` values during the app's lifetime. They are not securely zeroed after use.

## Dependency Surface

ImageElementStudio uses **zero external dependencies**. All frameworks are Apple system frameworks:

| Framework                  | Purpose                           |
|----------------------------|-----------------------------------|
| SwiftUI / AppKit           | UI rendering                      |
| Foundation                 | Core utilities, JSON, networking  |
| Vision                     | OCR and rectangle detection       |
| Security                   | Keychain access                   |
| CryptoKit                  | Deterministic hashing (SHA256)    |
| UniformTypeIdentifiers     | File type identification          |
| PDFKit                     | PDF rendering                     |
| QuickLookThumbnailing      | Fallback file preview             |

This eliminates supply-chain risk from third-party packages.
