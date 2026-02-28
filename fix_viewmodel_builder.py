#!/usr/bin/env python3

import re

file_path = "Sources/ImageElementStudio/StudioViewModel.swift"

with open(file_path, 'r') as f:
    content = f.read()

# Fix the BuilderCommandContext construction
old_context = """        let context = ChatService.BuilderCommandContext(
            isAnalyzing: isAnalyzing,
            pipelineMode: pipelineMode,
            selectedImage: selectedImage,
            acceptedStrategySpec: acceptedStrategySpec,
            renderableElements: renderableElements,
            latestScope: latestScope,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            buildSteps: buildSteps
        )"""

new_context = """        let context = ChatService.BuilderCommandContext(
            isAnalyzing: isAnalyzing,
            pipelineMode: pipelineMode,
            selectedImage: selectedImage,
            acceptedStrategySpec: acceptedStrategySpec,
            renderableElements: renderableElements,
            latestScope: latestScope,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            projectName: projectName
        )"""

content = content.replace(old_context, new_context)

# Add buildStatusSummary parameter
old_params = """            distributionGap: distributionGap,
            tokenRevisions: tokenRevisions,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkStatusLine: benchmarkStatusLine,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            latestBlueprint: latestBlueprint
        )"""

new_params = """            distributionGap: distributionGap,
            tokenRevisions: tokenRevisions,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkStatusLine: benchmarkStatusLine,
            buildStatusSummary: buildSteps.map { step in
                let icon: String
                switch step.state {
                case .pending: icon = "[ ]"
                case .active: icon = "[~]"
                case .done: icon = "[x]"
                }
                return "\\(icon) \\(step.title): \\(step.detail)"
            }.joined(separator: " | "),
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            latestBlueprint: latestBlueprint
        )"""

content = content.replace(old_params, new_params)

with open(file_path, 'w') as f:
    f.write(content)

print("StudioViewModel sendBuilderPrompt fixed")
