#!/usr/bin/env python3

import re

file_path = "Sources/ImageElementStudio/Services/ChatService.swift"

with open(file_path, 'r') as f:
    content = f.read()

# 1. Remove buildSteps from BuilderCommandContext
old_context = """    /// Context for builder commands that need to trigger actions
    struct BuilderCommandContext {
        let isAnalyzing: Bool
        let pipelineMode: PipelineMode
        let selectedImage: NSImage?
        let acceptedStrategySpec: StrategySpec?
        let renderableElements: [CanvasElement]
        let latestScope: ProductScopeSnapshot?
        let strategySession: StrategySession?
        let strategyActiveQuestion: StrategyQuestion?
        let buildSteps: [BuildStep]
    }"""

new_context = """    /// Context for builder commands that need to trigger actions
    struct BuilderCommandContext {
        let isAnalyzing: Bool
        let pipelineMode: PipelineMode
        let selectedImage: NSImage?
        let acceptedStrategySpec: StrategySpec?
        let renderableElements: [CanvasElement]
        let latestScope: ProductScopeSnapshot?
        let strategySession: StrategySession?
        let strategyActiveQuestion: StrategyQuestion?
        let projectName: String
    }"""

content = content.replace(old_context, new_context)

# 2. Remove builderStatusSummary method and its uses
# Find and remove the method
pattern = r'    private func builderStatusSummary\(buildSteps: \[BuildStep\]\) -> String \{[\s\S]*?^\s{4}\}'
content = re.sub(pattern, '', content, flags=re.MULTILINE)

# 3. Replace usages of builderStatusSummary with a parameter
old_status_call = """        if normalized.contains("status") || normalized.contains("step") {
            builderMessages.append(ChatMessage(role: .assistant, text: builderStatusSummary(buildSteps: context.buildSteps)))
            return
        }"""

new_status_call = """        if normalized.contains("status") || normalized.contains("step") {
            builderMessages.append(ChatMessage(role: .assistant, text: buildStatusSummary))
            return
        }"""

content = content.replace(old_status_call, new_status_call)

# 4. Add buildStatusSummary parameter to sendBuilderPrompt
# Find the parameter list
old_param_section = """        distributionGap: CGFloat,
        tokenRevisions: [TokenRevision],
        latestBenchmarkReport: BenchmarkReport?,
        benchmarkStatusLine: String,
        latestEnterpriseReadinessReport: EnterpriseReadinessReport?,
        latestBlueprint: BuildBlueprint?
    ) {"""

new_param_section = """        distributionGap: CGFloat,
        tokenRevisions: [TokenRevision],
        latestBenchmarkReport: BenchmarkReport?,
        benchmarkStatusLine: String,
        buildStatusSummary: String,
        latestEnterpriseReadinessReport: EnterpriseReadinessReport?,
        latestBlueprint: BuildBlueprint?
    ) {"""

content = content.replace(old_param_section, new_param_section)

# 5. Fix context.strategySession?.projectName references
content = content.replace(
    "context.strategySession?.projectName ?? \"Unknown\"",
    "context.projectName"
)

# 6. Fix the ProjectMemory construction in fallback
old_memory_construct = """        let chatContext = ChatContext(
            projectName: context.projectName,
            strategySession: context.strategySession,
            strategyActiveQuestion: context.strategyActiveQuestion,
            pipelineMode: context.pipelineMode,
            latestScope: context.latestScope,
            memory: ProjectMemory(
                projectName: context.projectName,
                entries: [],
                strategySessions: context.strategySession.map { [$0] } ?? [],
                acceptedStrategySpecs: [],
                decisionLog: []
            ),"""

new_memory_construct = """        let chatContext = ChatContext(
            projectName: context.projectName,
            strategySession: context.strategySession,
            strategyActiveQuestion: context.strategyActiveQuestion,
            pipelineMode: context.pipelineMode,
            latestScope: context.latestScope,
            memory: ProjectMemory(
                createdAt: Date(),
                updatedAt: Date(),
                projectID: UUID().uuidString,
                projectName: context.projectName,
                workingHypothesis: "",
                latestSummary: "",
                productScope: [],
                entries: [],
                strategySessions: context.strategySession.map { [$0] } ?? [],
                acceptedStrategySpecs: [],
                decisionLog: []
            ),"""

content = content.replace(old_memory_construct, new_memory_construct)

# 7. Fix clear memory message
content = content.replace(
    'builderMessages.append(ChatMessage(role: .assistant, text: "Project memory cleared for \'\\(context.projectName)\'."))',
    'builderMessages.append(ChatMessage(role: .assistant, text: "Project memory cleared for \'\\(context.projectName)\'."))'
)

with open(file_path, 'w') as f:
    f.write(content)

print("ChatService.swift fixed successfully")
