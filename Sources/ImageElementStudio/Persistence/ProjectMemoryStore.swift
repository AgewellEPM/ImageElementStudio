import Foundation

@MainActor
final class ProjectMemoryStore {
    private var fileURL: URL
    private(set) var memory: ProjectMemory
    private(set) var projectID: String
    private(set) var projectName: String

    init(projectName: String = "Default Project") {
        let resolvedName = Self.cleanedProjectName(projectName)
        let resolvedID = Self.normalizedProjectID(from: resolvedName)

        self.projectName = resolvedName
        self.projectID = resolvedID
        self.fileURL = Self.fileURL(for: resolvedID)

        if let loaded = Self.load(from: fileURL) ?? Self.loadLegacyDefaultIfNeeded(for: resolvedID) {
            self.memory = Self.withProjectMetadata(loaded, projectID: resolvedID, projectName: resolvedName)
            AppLogger.info("Loaded existing project memory: \(resolvedName) (\(loaded.entries.count) entries)", category: .project)
            persist()
        } else {
            self.memory = Self.defaultMemory(projectID: resolvedID, projectName: resolvedName)
            AppLogger.info("Created new project memory: \(resolvedName)", category: .project)
            persist()
        }
    }

    func switchProject(to newProjectName: String) -> ProjectMemory {
        let resolvedName = Self.cleanedProjectName(newProjectName)
        let resolvedID = Self.normalizedProjectID(from: resolvedName)

        AppLogger.info("Switching project from '\(projectName)' to '\(resolvedName)'", category: .project)

        projectName = resolvedName
        projectID = resolvedID
        fileURL = Self.fileURL(for: resolvedID)

        if let loaded = Self.load(from: fileURL) {
            memory = Self.withProjectMetadata(loaded, projectID: resolvedID, projectName: resolvedName)
        } else {
            memory = Self.defaultMemory(projectID: resolvedID, projectName: resolvedName)
        }

        persist()
        return memory
    }

    func createFreshProject(named requestedName: String?) -> ProjectMemory {
        let base = Self.cleanedProjectName(requestedName ?? "")
        let resolvedBase = base == "Default Project" ? "Project" : base

        var candidateName = resolvedBase
        var attempt = 1

        while FileManager.default.fileExists(atPath: Self.fileURL(for: Self.normalizedProjectID(from: candidateName)).path) {
            attempt += 1
            candidateName = "\(resolvedBase) \(attempt)"
            if attempt > Constants.Memory.maxProjectNameAttempts {
                let suffix = Self.timestampSuffix()
                candidateName = "\(resolvedBase) \(suffix)"
                break
            }
        }

        let resolvedID = Self.normalizedProjectID(from: candidateName)

        projectName = candidateName
        projectID = resolvedID
        fileURL = Self.fileURL(for: resolvedID)
        memory = Self.defaultMemory(projectID: resolvedID, projectName: candidateName)

        persist()
        return memory
    }

    func clearMemory() -> ProjectMemory {
        memory = Self.defaultMemory(projectID: projectID, projectName: projectName)
        persist()
        return memory
    }

    func recordAnalysis(scope: ProductScopeSnapshot, imageName: String, artboard: Artboard?) -> ProjectMemory {
        let entry = ProjectMemoryEntry(
            id: UUID(),
            createdAt: Date(),
            imageName: imageName,
            appType: scope.appType,
            summary: scope.summary,
            capabilities: scope.keyCapabilities,
            openQuestions: scope.openQuestions,
            artboardName: artboard?.name,
            elementCount: artboard?.elements.count,
            snapshotReason: "analysis"
        )

        memory.workingHypothesis = scope.productIntent
        memory.latestSummary = scope.summary
        memory.productScope = mergedScope(existing: memory.productScope, incoming: scope.keyCapabilities)
        return append(entry: entry)
    }

    func recordUserIntent(_ message: String) -> ProjectMemory {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return memory }

        memory.updatedAt = Date()
        if memory.workingHypothesis.isEmpty {
            memory.workingHypothesis = normalized
        } else if !memory.workingHypothesis.localizedCaseInsensitiveContains(normalized) {
            memory.workingHypothesis = "\(memory.workingHypothesis) | \(normalized)"
        }
        memory.latestSummary = "User intent updated: \(normalized)"
        memory.projectID = projectID
        memory.projectName = projectName

        persist()
        return memory
    }

    func recordArtboardSnapshot(
        artboard: Artboard,
        reason: String,
        imageName: String?,
        scope: ProductScopeSnapshot?
    ) -> ProjectMemory {
        let summary = "Artboard '\(artboard.name)' captured via \(reason) with \(artboard.elements.count) elements."
        let entry = ProjectMemoryEntry(
            id: UUID(),
            createdAt: Date(),
            imageName: imageName ?? "unknown-image",
            appType: scope?.appType ?? "Unclassified Project",
            summary: summary,
            capabilities: scope?.keyCapabilities ?? [],
            openQuestions: scope?.openQuestions ?? [],
            artboardName: artboard.name,
            elementCount: artboard.elements.count,
            snapshotReason: reason
        )

        if let scope {
            memory.productScope = mergedScope(existing: memory.productScope, incoming: scope.keyCapabilities)
            if !scope.productIntent.isEmpty {
                memory.workingHypothesis = scope.productIntent
            }
        }
        memory.latestSummary = summary

        return append(entry: entry)
    }

    func recordStrategySession(_ session: StrategySession) -> ProjectMemory {
        if let existingIndex = memory.strategySessions.firstIndex(where: { $0.id == session.id }) {
            memory.strategySessions[existingIndex] = session
        } else {
            memory.strategySessions.append(session)
            if memory.strategySessions.count > Constants.Memory.maxStrategySessions {
                memory.strategySessions.removeFirst(memory.strategySessions.count - Constants.Memory.maxStrategySessions)
            }
        }

        memory.updatedAt = Date()
        memory.projectID = projectID
        memory.projectName = projectName
        persist()
        return memory
    }

    func recordAcceptedStrategySpec(_ spec: StrategySpec) -> ProjectMemory {
        if let existingIndex = memory.acceptedStrategySpecs.firstIndex(where: { $0.id == spec.id }) {
            memory.acceptedStrategySpecs[existingIndex] = spec
        } else {
            memory.acceptedStrategySpecs.append(spec)
            if memory.acceptedStrategySpecs.count > Constants.Memory.maxAcceptedStrategySpecs {
                memory.acceptedStrategySpecs.removeFirst(memory.acceptedStrategySpecs.count - Constants.Memory.maxAcceptedStrategySpecs)
            }
        }

        memory.workingHypothesis = spec.vision
        memory.latestSummary = "Accepted strategy spec: \(spec.summary)"
        memory.productScope = mergedScope(existing: memory.productScope, incoming: spec.mustHaveFeatures)
        memory.updatedAt = Date()
        memory.projectID = projectID
        memory.projectName = projectName
        persist()
        return memory
    }

    func recordDecisionLog(message: String, stage: StrategyStage?, confidence: Double?) -> ProjectMemory {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return memory }

        memory.decisionLog.append(
            StrategyDecisionLogEntry(
                id: UUID(),
                createdAt: Date(),
                message: cleaned,
                stage: stage,
                confidence: confidence
            )
        )
        if memory.decisionLog.count > Constants.Memory.maxDecisionLogEntries {
            memory.decisionLog.removeFirst(memory.decisionLog.count - Constants.Memory.maxDecisionLogEntries)
        }

        memory.updatedAt = Date()
        memory.projectID = projectID
        memory.projectName = projectName
        persist()
        return memory
    }

    private func append(entry: ProjectMemoryEntry) -> ProjectMemory {
        if let last = memory.entries.last, shouldCoalesce(last: last, next: entry) {
            var updatedLast = last
            updatedLast.createdAt = entry.createdAt
            updatedLast.summary = entry.summary
            updatedLast.capabilities = entry.capabilities
            updatedLast.openQuestions = entry.openQuestions
            updatedLast.appType = entry.appType
            updatedLast.imageName = entry.imageName
            updatedLast.artboardName = entry.artboardName
            updatedLast.elementCount = entry.elementCount
            updatedLast.snapshotReason = entry.snapshotReason
            memory.entries[memory.entries.count - 1] = updatedLast

            memory.updatedAt = Date()
            memory.projectID = projectID
            memory.projectName = projectName
            persist()
            return memory
        }

        memory.entries.append(entry)
        if memory.entries.count > Constants.Memory.maxEntries {
            memory.entries.removeFirst(memory.entries.count - Constants.Memory.maxEntries)
        }

        memory.updatedAt = Date()
        memory.projectID = projectID
        memory.projectName = projectName

        persist()
        return memory
    }

    private func shouldCoalesce(last: ProjectMemoryEntry, next: ProjectMemoryEntry) -> Bool {
        guard last.appType == next.appType,
              last.imageName == next.imageName,
              last.artboardName == next.artboardName,
              last.elementCount == next.elementCount,
              last.snapshotReason == next.snapshotReason,
              normalized(last.summary) == normalized(next.summary) else {
            return false
        }

        let interval = abs(last.createdAt.timeIntervalSince(next.createdAt))
        return interval < Constants.Memory.coalesceInterval
    }

    private func mergedScope(existing: [String], incoming: [String]) -> [String] {
        var ordered = existing
        for item in incoming {
            if !ordered.contains(item) {
                ordered.append(item)
            }
        }
        return Array(ordered.prefix(Constants.Memory.maxMergedScopeCapabilities))
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(memory)
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            AppLogger.debug("Project memory persisted (\(data.count) bytes)", category: .project)
        } catch {
            // Non-fatal: memory still exists in-process.
            AppLogger.warning("Failed to persist project memory: \(error.localizedDescription)", category: .project)
        }
    }

    private static func load(from url: URL) -> ProjectMemory? {
        // Best-effort load: file may not exist yet (first launch), so nil is expected.
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ProjectMemory.self, from: data)
        } catch {
            // Log decoding failures so corrupt files are not silently ignored.
            AppLogger.error("Failed to decode project memory at \(url.path): \(error.localizedDescription)", category: .project)
            return nil
        }
    }

    private static func defaultMemory(projectID: String, projectName: String) -> ProjectMemory {
        let now = Date()
        return ProjectMemory(
            createdAt: now,
            updatedAt: now,
            projectID: projectID,
            projectName: projectName,
            workingHypothesis: "",
            latestSummary: "",
            productScope: [],
            entries: []
        )
    }

    private static func fileURL(for projectID: String) -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport
            .appendingPathComponent("ImageElementStudio", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("project-memory.json", isDirectory: false)
    }

    private static func legacyDefaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport
            .appendingPathComponent("ImageElementStudio", isDirectory: true)
            .appendingPathComponent("project-memory.json", isDirectory: false)
    }

    private static func loadLegacyDefaultIfNeeded(for projectID: String) -> ProjectMemory? {
        guard projectID == "default-project" else { return nil }
        return load(from: legacyDefaultFileURL())
    }

    private static func cleanedProjectName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default Project" : trimmed
    }

    private static func normalizedProjectID(from projectName: String) -> String {
        let lowercase = projectName.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var slug = ""
        var previousWasDash = false

        for scalar in lowercase.unicodeScalars {
            if allowed.contains(Character(scalar)) {
                slug.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                slug.append("-")
                previousWasDash = true
            }
        }

        while slug.hasPrefix("-") {
            slug.removeFirst()
        }
        while slug.hasSuffix("-") {
            slug.removeLast()
        }

        if slug.isEmpty {
            return "default-project"
        }
        return String(slug.prefix(Constants.Memory.maxProjectIDLength))
    }

    private static func withProjectMetadata(_ memory: ProjectMemory, projectID: String, projectName: String) -> ProjectMemory {
        var copy = memory
        copy.projectID = projectID
        copy.projectName = projectName
        return copy
    }

    private static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
