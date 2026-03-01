# Troubleshooting

Common issues and their solutions for ImageElementStudio.

## API Key Errors

### No Anthropic API key found

**Symptom**: Error message: `"No Anthropic API key found. Set it in Settings (stored in Keychain) or via ANTHROPIC_API_KEY environment variable."`

**Cause**: The `AnthropicService` could not resolve an API key from either the macOS Keychain or the `ANTHROPIC_API_KEY` environment variable.

**Solution**:
1. Open **ImageElementStudio > Settings** from the menu bar and enter your Anthropic API key. The key is stored in the macOS Keychain under service `com.imageelementstudio.apikeys`, account `anthropic-api-key`.
2. Alternatively, for development/CI, set the environment variable before launching:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   swift run
   ```

### Invalid or expired Anthropic API key

**Symptom**: Error message: `"HTTP 401: ..."` or `"HTTP 403: ..."` from the Claude API.

**Cause**: The stored API key is invalid, expired, or does not have the required permissions.

**Solution**:
1. Open Settings and re-enter a valid API key.
2. Verify your key at [console.anthropic.com](https://console.anthropic.com).
3. Ensure the key has access to the models used: `claude-sonnet-4-5-20250929` (fast mode) and `claude-opus-4-6` (quality mode).

### Rate limited by Anthropic API

**Symptom**: Error message: `"Rate limited. Retry after Ns."` or generation stalls temporarily.

**Cause**: Too many API requests in a short window. The `AnthropicService` handles HTTP 429 responses with automatic retry (up to 3 attempts with exponential backoff).

**Solution**:
- Wait and retry. The service retries automatically with delays of 2s, 4s, 8s.
- If the error persists after 3 retries, check your Anthropic usage limits.
- Reduce concurrent generation requests.

### Anthropic API overloaded

**Symptom**: Error message: `"Server error (HTTP 529)."` or generation fails after retries.

**Cause**: The Anthropic API is temporarily overloaded. The service retries with exponential backoff (2s, 4s, 8s).

**Solution**: Wait a few minutes and retry. This is a transient server-side condition.

### OpenAI API key not configured

**Symptom**: Semantic analysis completes but with `"Heuristic Semantic Engine"` only -- no remote AI enrichment.

**Cause**: No OpenAI API key is configured. The semantic pipeline falls back to local heuristic inference.

**Solution**: This is expected behavior when no OpenAI key is set. To enable remote semantic enrichment:
1. Open Settings and enter your OpenAI API key (stored under account `openai-api-key`).
2. Or set: `export OPENAI_API_KEY="sk-..."` before launching.

### OpenAI API errors during semantic analysis

**Symptom**: Error message: `"Status NNN: ..."` during semantic pipeline enrichment.

**Cause**: The OpenAI Vision API returned an HTTP error. Common codes:
- **401**: Invalid API key.
- **429**: Rate limited.
- **500/503**: Server error.

**Solution**:
1. Verify your OpenAI API key is valid.
2. The pipeline falls back to heuristic-only analysis when the remote engine fails -- the analysis will still complete.

---

## Build and Toolchain Errors

### Xcode not installed

**Symptom**: Build pipeline fails at "Verify Toolchain" step with: `"Xcode not installed"`.

**Cause**: `xcode-select -p` did not return a valid Xcode developer path.

**Solution**:
1. Install Xcode from the Mac App Store or Apple Developer downloads.
2. Run: `xcode-select --install` to install command-line tools.
3. Run: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` to set the active developer directory.

### Command line tools missing

**Symptom**: Build pipeline fails with: `"Command line tools missing"`.

**Cause**: `xcrun --find xcodebuild` returned empty, indicating the Xcode command-line tools are not installed or not properly linked.

**Solution**:
```bash
xcode-select --install
```

### XcodeGen not installed (iOS builds)

**Symptom**: Build pipeline fails with: `"XcodeGen not installed"` or `"xcodegen failed (exit N): ..."`.

**Cause**: XcodeGen is required for iOS target builds to generate `.xcodeproj` from `project.yml`. The `which xcodegen` check returned empty.

**Solution**:
```bash
brew install xcodegen
```

### iOS Simulator SDK not available

**Symptom**: Build pipeline fails with: `"iOS Simulator SDK not available"`.

**Cause**: No `iphonesimulator` SDK was found in `xcodebuild -showsdks` output.

**Solution**:
1. Open Xcode > Settings > Platforms and download the iOS Simulator runtime.
2. Or install via command line: `xcodebuild -downloadPlatform iOS`

### No available iOS simulators found

**Symptom**: Build pipeline fails at "Select Simulator" with: `"No available iOS simulators found"`.

**Cause**: `xcrun simctl list devices available` returned no iOS simulator devices.

**Solution**:
1. Open Xcode > Window > Devices and Simulators and create a simulator.
2. Or: `xcrun simctl create "iPhone 16" "com.apple.CoreSimulator.SimDeviceType.iPhone-16" "com.apple.CoreSimulator.SimRuntime.iOS-18-2"`

### Failed to boot simulator

**Symptom**: Build pipeline fails with: `"Failed to boot simulator: <name>"`.

**Cause**: `xcrun simctl boot` returned a non-zero, non-149 exit code. Exit code 149 (already booted) is handled gracefully.

**Solution**:
1. Try booting manually: `xcrun simctl boot <UDID>`
2. If the device is corrupt, delete and recreate it: `xcrun simctl delete <UDID>`

### Build failed with compile errors

**Symptom**: Build pipeline fails at "Build Project" with error count and first error message.

**Cause**: The generated code has Swift compilation errors. The pipeline supports automatic error fixing with up to 3 AI-assisted fix attempts.

**Solution**:
- If using AI code generation, the pipeline automatically attempts to fix errors (up to 3 times).
- Review the build output in the Build Output panel for specific error details.
- For scaffold-only builds (non-AI), check that the generated code matches your target SDK version.

### swift build fails

**Symptom**: `swift build` or `make build` fails with compilation errors.

**Cause**: Missing prerequisites or incompatible Swift version.

**Solution**:
1. Verify Swift version: `swift --version` (requires Swift 6.2+).
2. Verify macOS version: requires macOS 14.0 (Sonoma) or later.
3. Clean and rebuild: `swift package clean && swift build`

---

## File Import Errors

### Unsupported design file format

**Symptom**: Error message: `"Unsupported design file format. Try PNG/JPG/PDF/AI/SVG/FIG/JSON or export from design tool as image/PDF."`

**Cause**: The `DesignAssetImporter` could not load the file as a raster image, PDF-like vector, structured design (FIG/JSON), or QuickLook thumbnail.

**Solution**:
1. Export your design from Figma, Sketch, or Illustrator as PNG, PDF, or SVG.
2. Supported raster formats: PNG, JPG/JPEG, HEIC, TIFF, GIF (any format `NSImage` can read).
3. Supported vector formats: PDF, AI, EPS, SVG.
4. Supported structured formats: FIG (Figma JSON export), JSON with node geometry.

### Could not read the selected design file

**Symptom**: Error message: `"Could not read the selected design file."`

**Cause**: The file exists but could not be parsed as any supported format. The QuickLook fallback also failed.

**Solution**:
1. Verify the file is not corrupted by opening it in its native application.
2. Try re-exporting at a smaller size or different format.

### Could not derive a preview image

**Symptom**: Error message: `"Could not derive a preview image from the imported design file."`

**Cause**: The importer parsed the file structure but could not produce an `NSImage` preview.

**Solution**: Export the design as a raster image (PNG/JPG) for the best import experience.

### Could not decode dropped image data

**Symptom**: Error message: `"Could not decode dropped image data."`

**Cause**: Image data received via drag-and-drop could not be decoded by `NSImage(data:)`.

**Solution**:
1. Try dragging a different format (PNG or JPG recommended).
2. Try using the Upload menu command instead of drag-and-drop.

### Structured file contains no parseable design nodes

**Symptom**: Error message: `"Structured file contains no parseable design nodes."`

**Cause**: A FIG or JSON file was recognized but contained no nodes with valid geometry (x, y, width, height > 1).

**Solution**: Ensure the JSON file contains Figma-compatible node structures with `absoluteBoundingBox`, `frame`, or `bounds` keys.

---

## Project Save/Load Errors

### Could not save project package

**Symptom**: Error message: `"Could not save project package: <detail>"`.

**Cause**: JSON encoding failed or the file could not be written to the chosen destination.

**Solution**:
1. Ensure you have write permissions to the destination directory.
2. Check available disk space.
3. Try saving to a different location (e.g., Desktop or Documents).

### Could not write JSON

**Symptom**: Error message: `"Could not write JSON: <detail>"`.

**Cause**: The export JSON operation failed during file write.

**Solution**: Same as project save -- check permissions and disk space.

### JSON export failed

**Symptom**: Error message: `"JSON export failed: <detail>"`.

**Cause**: The `JSONEncoder` failed to encode the document. This is rare and typically indicates a programming error in model conformances.

**Solution**: File a bug report with the full error message.

### Project memory decode failure

**Symptom**: Console log: `"[ProjectMemoryStore] Failed to decode project memory at <path>: <detail>"`.

**Cause**: The project memory JSON file at `~/Library/Application Support/ImageElementStudio/projects/<id>/project-memory.json` is corrupted or was written by an incompatible version.

**Solution**:
1. The app creates a fresh default memory when decoding fails -- no data loss for in-progress work.
2. To reset: use the **Clear Project Memory** menu command.
3. If the problem persists, delete the project directory: `rm -rf ~/Library/Application\ Support/ImageElementStudio/projects/<id>/`

---

## Keychain Errors

### Keychain store failed with status N

**Symptom**: Error message: `"Keychain store failed with status <N>."`

**Cause**: `SecItemAdd` returned a non-success OSStatus. Common codes:
- **-25299** (`errSecDuplicateItem`): An entry already exists. The service normally deletes before adding, so this is unexpected.
- **-25293** (`errSecAuthFailed`): The keychain is locked or access was denied.

**Solution**:
1. Open **Keychain Access.app** and verify the `com.imageelementstudio.apikeys` entries.
2. If the keychain is locked, unlock it.
3. If running in a sandboxed environment, ensure keychain access entitlements are configured.

### Keychain delete failed with status N

**Symptom**: Error message: `"Keychain delete failed with status <N>."`

**Cause**: `SecItemDelete` returned a non-success status other than `errSecItemNotFound` (-25300). Item-not-found is handled gracefully.

**Solution**: Open Keychain Access and manually remove the entry for `com.imageelementstudio.apikeys`.

### Failed to encode API key data

**Symptom**: Error message: `"Failed to encode API key data."`

**Cause**: The API key string could not be converted to UTF-8 `Data`. This should never happen with normal text input.

**Solution**: Verify the API key contains only ASCII characters and try again.

---

## Network Errors

### Network request timeout

**Symptom**: The operation hangs and then throws a `URLError` with code `.timedOut`.

**Cause**: The Anthropic or OpenAI API did not respond within the `URLSession` default timeout.

**Solution**:
1. Check your internet connection.
2. Check the API provider's status page.
3. Retry the operation.

### Streaming error

**Symptom**: Error message: `"Streaming error: <message>"`.

**Cause**: The SSE (Server-Sent Events) stream from the Claude API returned an error event, or the stream terminated unexpectedly.

**Solution**:
1. Retry the generation.
2. If the error mentions token limits, try a simpler design or reduce the number of elements.

### Max retries exceeded

**Symptom**: Error message: `"Streaming error: Max retries exceeded"`.

**Cause**: All 3 retry attempts for the API call were exhausted due to rate limiting or server overload.

**Solution**: Wait a few minutes and try again. Consider upgrading your API plan if rate limits are consistently hit.

---

## AI Code Generation Errors

### Architecture plan produced no files

**Symptom**: Error message: `"Architecture plan produced no files."`.

**Cause**: The Claude API returned an architecture plan response that could not be parsed into any file entries.

**Solution**:
1. Retry the generation -- AI responses can vary.
2. Ensure your design has at least one artboard with elements.
3. Try switching between Fast (Sonnet) and Quality (Opus) generation modes.

### Failed to parse architecture plan

**Symptom**: Error message: `"Failed to parse architecture plan: JSON decode failed: <detail>"`.

**Cause**: Claude's response did not contain valid JSON matching the expected `ArchitecturePlanResponse` schema.

**Solution**:
1. Retry the generation.
2. Try the Quality (Opus) mode for more reliable JSON formatting.

### Failed generating <filename>

**Symptom**: Error message: `"Failed generating ContentView.swift: <error>"`.

**Cause**: An API error occurred during individual file generation within the pipeline.

**Solution**: The error detail will indicate whether it was a network issue, rate limit, or API error. Address the underlying cause and retry.

### Generation cancelled

**Symptom**: Error message: `"Generation cancelled."` and state shows `"Cancelled by user"`.

**Cause**: The user pressed the cancel button during AI code generation.

**Solution**: This is expected behavior. Restart generation when ready.

---

## Build Export / Quality Gate Issues

### Interop export blocked

**Symptom**: Error message: `"Interop export blocked. <reason>"`.

**Cause**: The review gate is blocking export. The review approval state must be `approved` and all review comments must be resolved.

**Solution**:
1. Resolve all open review comments.
2. Set the review approval state to **Approved**.
3. The `reviewGateBlockReason` in the error message will specify exactly what is needed (e.g., `"Approval must be set to Approved."` or `"All review comments must be resolved."`).

### Quality gate score is low

**Symptom**: Quality gate status shows `fail` (below 65) or `warning` (between 65 and 85).

**Cause**: The composite quality score is below the pass threshold (85). The score is computed from:
- Smoke-check pass rate (30 points max)
- Full-app pass rate (15 points max)
- Design/code diff health (20 points max)
- Benchmark pass rate (20 points max)
- Review gate status (15 points max)
- Overdue comment penalty (up to -10 points)

**Solution**: Address the blocking issues listed in the quality gate summary. Common actions:
- Fix failing smoke checks (pass rate must be >= 90%).
- Resolve high-impact design/code drifts (impact score >= 0.7).
- Approve the review gate.
- Run benchmarks and fix any regressions.

---

## Memory / Performance

### Large project memory file

**Symptom**: App feels sluggish after many analysis iterations.

**Cause**: Project memory retains up to 80 snapshots, 24 strategy sessions, and 80 decision log entries (bounded by `Constants.Memory`). For very active projects, the JSON file can grow.

**Solution**:
1. Use **Clear Project Memory** from the menu to reset memory for the active project.
2. Create a new project via the **New** menu for a fresh workspace.

### Image analysis is slow

**Symptom**: OCR and rectangle detection take longer than expected.

**Cause**: Very large or high-resolution images increase Vision framework processing time.

**Solution**:
1. Resize the image before importing (2400px max dimension is recommended).
2. Export from your design tool at 1x resolution rather than 2x/3x.

---

## Miscellaneous

### Failed to launch process

**Symptom**: Console message: `"Failed to launch process: <detail>"`.

**Cause**: A shell command (xcodebuild, simctl, xcodegen) could not be launched. This typically means `/bin/zsh` is not available or the system is severely constrained.

**Solution**: Ensure `/bin/zsh` exists and is executable. This is standard on macOS.

### simctl install/launch failed

**Symptom**: Build pipeline fails at "Install App" or "Launch App" with `"simctl install failed"` or `"simctl launch failed for <bundleID>"`.

**Cause**: The simulator may have crashed, the `.app` bundle may be corrupt, or the bundle ID does not match.

**Solution**:
1. Check the simulator is running: `xcrun simctl list devices booted`.
2. Verify the bundle ID matches the generated project configuration.
3. Try shutting down and rebooting the simulator.

### Could not find built .app product path

**Symptom**: Build pipeline fails at "Install App" with `"Could not find built .app product path"`.

**Cause**: The build succeeded but the output parser could not locate the `.app` bundle in the build output.

**Solution**: Check the build output logs for the actual product path. This can happen if the build configuration or scheme name does not match expectations.
