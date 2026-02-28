#!/usr/bin/env python3

import re

file_path = "Sources/ImageElementStudio/StudioViewModel.swift"

with open(file_path, 'r') as f:
    content = f.read()

# Find and replace the entire sendBuilderPrompt method with a forwarding implementation
# First, let's find where it starts and ends

# Pattern to match the entire sendBuilderPrompt function
pattern = r'(    func sendBuilderPrompt\(\) \{[\s\S]*?^    \}(?=\n\n    func ))'

# Replacement forwarding method
replacement = '''    func sendBuilderPrompt() {
        let context = ChatService.BuilderCommandContext(
            isAnalyzing: isAnalyzing,
            pipelineMode: pipelineMode,
            selectedImage: selectedImage,
            acceptedStrategySpec: acceptedStrategySpec,
            renderableElements: renderableElements,
            latestScope: latestScope,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            buildSteps: buildSteps
        )

        chatService.sendBuilderPrompt(
            context: context,
            onSetPipelineMode: { [weak self] mode in self?.setPipelineMode(mode) },
            onGenerateFullStackBuild: { [weak self] in self?.generateFullStackBuild() },
            onRunBuilderBuildCommand: { [weak self] in
                guard let self else { return }
                self.messages.append(ChatMessage(role: .assistant, text: "Builder command received: build. Running analysis pipeline."))
                self.analyzeCurrentImage()
            },
            onRunBuilderAnalyzeCommand: { [weak self] in self?.analyzeCurrentImage() },
            onAddArtboard: { [weak self] in self?.addArtboard() },
            onGenerateStateArtboards: { [weak self] in self?.generateStateArtboardsFromLatestBlueprint() },
            onDistributeHorizontally: { [weak self] in self?.distributeSelectedElementsHorizontally() },
            onDistributeVertically: { [weak self] in self?.distributeSelectedElementsVertically() },
            onSpaceHorizontally: { [weak self] gap in self?.spaceSelectedElementsHorizontally(gap: gap) },
            onSpaceVertically: { [weak self] gap in self?.spaceSelectedElementsVertically(gap: gap) },
            onCreateComponent: { [weak self] in self?.createComponentFromSelection(named: nil) },
            onCreateComponentInstance: { [weak self] in self?.createComponentInstanceFromSelectedComponent() },
            onRunBenchmark: { [weak self] in self?.runProEditingBenchmark() },
            onAutoFixBenchmark: { [weak self] in self?.autoFixFailingBenchmarkStep() },
            onUpdateInstanceOverride: { [weak self] key, value in self?.updateSelectedInstanceOverride(key: key, value: value) },
            onApplyOverridesToAll: { [weak self] in self?.applySelectedInstanceOverridesToAll() },
            onRollbackTokenRevision: { [weak self] revisionID in
                guard let revisionID else { return }
                self?.rollbackTokenRevision(revisionID)
            },
            onExportInterop: { [weak self] in self?.exportInteropPackage() },
            onSetReviewApprovalState: { [weak self] state -> Bool in
                self?.setReviewApprovalState(state) ?? false
            },
            onDuplicateArtboard: { [weak self] in self?.duplicateActiveArtboard() },
            onExportJSON: { [weak self] in self?.exportJSON() },
            onSaveProject: { [weak self] in self?.saveProjectPackage() },
            onClearProjectMemory: { [weak self] in self?.clearProjectMemory() },
            onCreateNewProject: { [weak self] in self?.createNewProject(named: nil) },
            onStartStrategy: { [weak self] prompt in self?.startStrategyFromIdea(prompt) },
            onContinueStrategy: { [weak self] in self?.continueStrategy() },
            onFinalizeSpec: { [weak self] in self?.finalizeStrategySpec() },
            onGenerateMockups: { [weak self] in self?.finalizeAndGenerateMockups() },
            onApproveCurrentStage: { [weak self] in self?.approveCurrentStage() },
            onSkipQuestion: { [weak self] in self?.skipCurrentStrategyQuestion() },
            onAutoRunStrategy: { [weak self] in self?.autoRunStrategySession() },
            onSubmitStrategyAnswer: { [weak self] answer in self?.submitStrategyAnswer(answer) },
            distributionGap: distributionGap,
            tokenRevisions: tokenRevisions,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkStatusLine: benchmarkStatusLine,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            latestBlueprint: latestBlueprint
        )

        // Handle realtime build scheduling if needed
        let normalized = chatService.builderDraft.lowercased()
        if normalized.contains("realtime") {
            realTimeBuildEnabled = true
            scheduleRealtimeAnalysis(reason: "builder realtime command")
        }
    }'''

# Use multiline regex to find and replace
content_new = re.sub(pattern, replacement, content, flags=re.MULTILINE)

if content_new == content:
    print("WARNING: Could not find sendBuilderPrompt to replace!")
    print("Will try alternative approach...")
    # Try to find it manually
    start_idx = content.find("    func sendBuilderPrompt() {")
    if start_idx != -1:
        # Find the matching closing brace
        # Count braces to find the end
        brace_count = 0
        in_function = False
        end_idx = start_idx
        for i in range(start_idx, len(content)):
            if content[i] == '{':
                brace_count += 1
                in_function = True
            elif content[i] == '}':
                brace_count -= 1
                if in_function and brace_count == 0:
                    end_idx = i + 1
                    break

        if end_idx > start_idx:
            print(f"Found sendBuilderPrompt from {start_idx} to {end_idx}")
            # Find the next line break after end_idx
            while end_idx < len(content) and content[end_idx] != '\n':
                end_idx += 1
            content_new = content[:start_idx] + replacement + content[end_idx:]
        else:
            print("ERROR: Could not find end of sendBuilderPrompt")
            exit(1)
    else:
        print("ERROR: Could not find sendBuilderPrompt function")
        exit(1)

# Write back
with open(file_path, 'w') as f:
    f.write(content_new)

print("sendBuilderPrompt replaced successfully")
