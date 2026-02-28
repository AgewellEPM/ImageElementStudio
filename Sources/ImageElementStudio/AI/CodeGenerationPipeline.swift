import Foundation

@MainActor
final class CodeGenerationPipeline: ObservableObject {

    // MARK: - Published State

    @Published var state: AIGenerationState = .idle
    @Published var currentFileName: String?
    @Published var generatedFiles: [GeneratedFileEntry] = []
    @Published var streamingContent: String = ""
    @Published var progress: Double = 0
    @Published var errorMessage: String?

    // MARK: - Private

    private let anthropic = AnthropicService()
    private var currentTask: Task<[GeneratedFileEntry], Never>?
    private let maxFixAttempts = 2

    // MARK: - Generate App

    /// Full generation pipeline: plan architecture -> generate files -> validate -> fix
    func generateApp(
        elements: [CanvasElement],
        artboards: [Artboard],
        tokens: DesignTokenSet?,
        components: [ComponentSpec],
        blueprint: BuildBlueprint?,
        target: StudioViewModel.BuildTarget,
        appName: String,
        quality: AIGenerationQuality,
        screenshotData: Data? = nil
    ) async -> [GeneratedFileEntry] {
        // Reset state
        state = .planningArchitecture(progress: "Starting...")
        currentFileName = nil
        generatedFiles = []
        streamingContent = ""
        progress = 0
        errorMessage = nil

        let task = Task<[GeneratedFileEntry], Never> { @MainActor in
            await self.runPipeline(
                elements: elements,
                artboards: artboards,
                tokens: tokens,
                components: components,
                blueprint: blueprint,
                target: target,
                appName: appName,
                quality: quality,
                screenshotData: screenshotData
            )
        }
        currentTask = task
        return await task.value
    }

    /// Cancels the current generation task.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .failed("Cancelled by user")
        errorMessage = "Generation cancelled."
    }

    // MARK: - Pipeline Implementation

    private func runPipeline(
        elements: [CanvasElement],
        artboards: [Artboard],
        tokens: DesignTokenSet?,
        components: [ComponentSpec],
        blueprint: BuildBlueprint?,
        target: StudioViewModel.BuildTarget,
        appName: String,
        quality: AIGenerationQuality,
        screenshotData: Data?
    ) async -> [GeneratedFileEntry] {

        // -----------------------------------------------------------
        // Step 1: Architecture Planning
        // -----------------------------------------------------------

        state = .planningArchitecture(progress: "Building architecture plan...")
        streamingContent = ""

        let architecturePrompt = PromptBuilder.architecturePlanningPrompt(
            elements: elements,
            artboards: artboards,
            tokens: tokens,
            components: components,
            blueprint: blueprint,
            target: target,
            appName: appName
        )

        let systemPrompt = PromptBuilder.systemPrompt(target: target)

        // Build messages, optionally including a screenshot
        var userContent: [AnthropicService.ContentBlock] = []
        if let screenshotData {
            let base64 = screenshotData.base64EncodedString()
            userContent.append(.image(mediaType: "image/png", base64Data: base64))
        }
        userContent.append(.text(architecturePrompt))

        let planningMessages = [
            AnthropicService.Message(role: .user, content: userContent)
        ]

        let planResponseText: String
        do {
            planResponseText = try await anthropic.streamMessage(
                system: systemPrompt,
                messages: planningMessages,
                model: quality,
                maxTokens: 8192,
                temperature: 0.3,
                onChunk: { [weak self] chunk in
                    self?.streamingContent += chunk
                }
            )
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            return []
        }

        // Check cancellation
        if Task.isCancelled {
            state = .failed("Cancelled")
            return []
        }

        // Parse architecture plan JSON
        let filePlan: [FilePlanEntry]
        do {
            filePlan = try parseArchitecturePlan(planResponseText)
        } catch {
            state = .failed("Failed to parse architecture plan: \(error.localizedDescription)")
            errorMessage = "Failed to parse architecture plan: \(error.localizedDescription)"
            return []
        }

        if filePlan.isEmpty {
            state = .failed("Architecture plan produced no files")
            errorMessage = "Architecture plan produced no files."
            return []
        }

        // -----------------------------------------------------------
        // Step 2: Sequential File Generation
        // -----------------------------------------------------------

        let totalFiles = filePlan.count

        for (index, plan) in filePlan.enumerated() {
            if Task.isCancelled {
                state = .failed("Cancelled")
                return []
            }

            currentFileName = plan.name
            progress = Double(index) / Double(totalFiles)
            state = .generatingFile(
                name: plan.name,
                index: index,
                total: totalFiles,
                streamedText: ""
            )
            streamingContent = ""

            // Build previous file signatures for context
            let signatures = buildPreviousFileSignatures(from: generatedFiles)

            let filePrompt = PromptBuilder.fileGenerationPrompt(
                filePlan: plan,
                architecturePlan: planResponseText,
                previousFileSignatures: signatures,
                target: target
            )

            let fileMessages = [AnthropicService.Message.user(filePrompt)]

            let fileContent: String
            do {
                fileContent = try await anthropic.streamMessage(
                    system: systemPrompt,
                    messages: fileMessages,
                    model: quality,
                    maxTokens: 8192,
                    temperature: 0.2,
                    onChunk: { [weak self] chunk in
                        self?.streamingContent += chunk
                        self?.state = .generatingFile(
                            name: plan.name,
                            index: index,
                            total: totalFiles,
                            streamedText: self?.streamingContent ?? ""
                        )
                    }
                )
            } catch {
                state = .failed("Failed generating \(plan.name): \(error.localizedDescription)")
                errorMessage = "Failed generating \(plan.name): \(error.localizedDescription)"
                return []
            }

            if Task.isCancelled {
                state = .failed("Cancelled")
                return []
            }

            let entry = GeneratedFileEntry(
                name: plan.name,
                relativePath: plan.relativePath,
                content: fileContent,
                role: plan.role
            )
            generatedFiles.append(entry)
        }

        progress = 1.0

        // -----------------------------------------------------------
        // Step 3: Validation & Auto-Fix
        // -----------------------------------------------------------

        for fileIndex in generatedFiles.indices {
            if Task.isCancelled {
                state = .failed("Cancelled")
                return []
            }

            let entry = generatedFiles[fileIndex]
            state = .validating(name: entry.name)
            streamingContent = ""

            let validation = CodeValidator.validate(entry: entry)

            // Always apply cleaned content (strips code fences)
            generatedFiles[fileIndex].content = validation.cleanedContent

            // If there are errors, attempt auto-fix
            if !validation.isValid {
                let errorMessages = validation.errors
                    .filter { $0.severity == .error }
                    .map(\.message)

                var fixedContent = validation.cleanedContent
                var fixAttempt = 0
                var isFixed = false

                while fixAttempt < maxFixAttempts && !isFixed {
                    fixAttempt += 1

                    if Task.isCancelled {
                        state = .failed("Cancelled")
                        return []
                    }

                    state = .fixing(name: entry.name, attempt: fixAttempt)
                    streamingContent = ""

                    let fixPrompt = PromptBuilder.buildErrorFixPrompt(
                        fileContent: fixedContent,
                        fileName: entry.name,
                        errors: errorMessages,
                        target: target
                    )

                    let fixMessages = [AnthropicService.Message.user(fixPrompt)]

                    do {
                        let fixResponse = try await anthropic.streamMessage(
                            system: systemPrompt,
                            messages: fixMessages,
                            model: quality,
                            maxTokens: 8192,
                            temperature: 0.1,
                            onChunk: { [weak self] chunk in
                                self?.streamingContent += chunk
                            }
                        )

                        let cleaned = CodeValidator.stripCodeFences(fixResponse)

                        // Re-validate the fixed content
                        let fixEntry = GeneratedFileEntry(
                            name: entry.name,
                            relativePath: entry.relativePath,
                            content: cleaned,
                            role: entry.role
                        )
                        let revalidation = CodeValidator.validate(entry: fixEntry)

                        fixedContent = revalidation.cleanedContent
                        isFixed = revalidation.isValid
                    } catch {
                        // If the fix call fails, keep the current content and stop trying
                        break
                    }
                }

                generatedFiles[fileIndex].content = fixedContent
            }
        }

        // -----------------------------------------------------------
        // Step 4: Complete
        // -----------------------------------------------------------

        state = .complete(outputPath: appName)
        streamingContent = ""
        currentFileName = nil
        return generatedFiles
    }

    // MARK: - Architecture Plan Parsing

    /// Parses the architecture plan JSON from Claude's response into FilePlanEntry values.
    private func parseArchitecturePlan(_ responseText: String) throws -> [FilePlanEntry] {
        // Try to extract JSON from the response. Claude might wrap it in markdown fences
        // or include surrounding text.
        let jsonString = extractJSON(from: responseText)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw PipelineError.jsonParsing("Could not convert response to UTF-8 data")
        }

        let decoder = JSONDecoder()
        let plan: ArchitecturePlanResponse
        do {
            plan = try decoder.decode(ArchitecturePlanResponse.self, from: jsonData)
        } catch {
            throw PipelineError.jsonParsing("JSON decode failed: \(error.localizedDescription)")
        }

        return plan.files.map { spec in
            FilePlanEntry(
                name: spec.name,
                relativePath: spec.relativePath,
                role: FileRole(rawValue: spec.role) ?? .unknown,
                description: spec.description,
                keyTypes: spec.keyTypes ?? [],
                dependencies: spec.dependencies ?? []
            )
        }
    }

    /// Extracts the first JSON object from a string that may contain surrounding text or
    /// markdown code fences.
    private func extractJSON(from text: String) -> String {
        // Strip markdown JSON code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` or ``` ... ```
        if cleaned.hasPrefix("```") {
            // Remove the opening fence line
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
        }
        if cleaned.hasSuffix("```") {
            // Remove the closing fence
            if let lastFenceRange = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<lastFenceRange.lowerBound])
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it starts with '{', it's likely the JSON object already
        if cleaned.hasPrefix("{") {
            return cleaned
        }

        // Try to find the outermost { ... } block
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }

        // Return as-is and let the caller handle the error
        return cleaned
    }

    // MARK: - Previous File Signatures

    /// Extracts a "signature" from each already-generated file: the first 20 non-empty lines.
    /// This gives Claude context about types and functions without overwhelming the prompt.
    private func buildPreviousFileSignatures(from files: [GeneratedFileEntry]) -> [String] {
        files.map { file in
            let lines = file.content.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(20)

            return "// --- \(file.name) ---\n" + lines.joined(separator: "\n")
        }
    }

    // MARK: - Errors

    private enum PipelineError: LocalizedError {
        case jsonParsing(String)

        var errorDescription: String? {
            switch self {
            case .jsonParsing(let detail):
                return "Architecture plan parsing error: \(detail)"
            }
        }
    }
}
