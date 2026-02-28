#!/usr/bin/env python3

import re

file_path = "Sources/ImageElementStudio/StudioViewModel.swift"

with open(file_path, 'r') as f:
    content = f.read()

# 1. Replace @Published chat properties with forwarding computed properties
old_props = """    @Published var messages: [ChatMessage]
    @Published var draftMessage: String = ""
    @Published var builderMessages: [ChatMessage]
    @Published var builderDraft: String = ""
"""

new_props = """    // Chat properties forwarded to ChatService
    var messages: [ChatMessage] {
        get { chatService.messages }
        set { chatService.messages = newValue }
    }
    var draftMessage: String {
        get { chatService.draftMessage }
        set { chatService.draftMessage = newValue }
    }
    var builderMessages: [ChatMessage] {
        get { chatService.builderMessages }
        set { chatService.builderMessages = newValue }
    }
    var builderDraft: String {
        get { chatService.builderDraft }
        set { chatService.builderDraft = newValue }
    }
"""

content = content.replace(old_props.strip(), new_props.strip())

# 2. Add chatService declaration after other services
service_decls = """    let reviewService = ReviewService()
    let selectionService = SelectionService()
    let benchmarkService = BenchmarkService()
    let designTokenService = DesignTokenService()
    let canvasService = CanvasService()
    let componentService = ComponentService()"""

new_service_decls = """    let reviewService = ReviewService()
    let selectionService = SelectionService()
    let benchmarkService = BenchmarkService()
    let designTokenService = DesignTokenService()
    let canvasService = CanvasService()
    let componentService = ComponentService()
    let chatService: ChatService"""

content = content.replace(service_decls, new_service_decls)

# 3. Update init to initialize chatService and wire objectWillChange
# Find and replace the init section that initializes messages
old_init_messages = """        self.messages = Self.initialMessages(for: activeProjectName)
        self.builderMessages = Self.initialBuilderMessages(for: activeProjectName)"""

new_init_messages = """        self.chatService = ChatService(projectName: activeProjectName)"""

content = content.replace(old_init_messages, new_init_messages)

# 4. Add chatService objectWillChange sink after benchmarkService
old_sinks = """        benchmarkService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        designTokenService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)"""

new_sinks = """        benchmarkService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        chatService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        designTokenService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)"""

content = content.replace(old_sinks, new_sinks)

# 5. Replace sendMessage method
old_send_message = '''    func sendMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        draftMessage = ""
        memory = memoryStore.recordUserIntent(trimmed)

        let response = assistantReply(for: trimmed)
        messages.append(ChatMessage(role: .assistant, text: response))
    }'''

new_send_message = '''    func sendMessage() {
        let context = ChatService.ChatContext(
            projectName: projectName,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            pipelineMode: pipelineMode,
            latestScope: latestScope,
            memory: memory,
            benchmarkStatusLine: benchmarkStatusLine,
            componentInstances: componentInstances,
            componentSystemStatusLine: componentSystemStatusLine,
            latestBlueprint: latestBlueprint,
            enterpriseReadinessStatusLine: enterpriseReadinessStatusLine
        )

        chatService.sendMessage(context: context, memoryStore: memoryStore) { [weak self] updatedMemory in
            self?.memory = updatedMemory
        }
    }'''

content = content.replace(old_send_message, new_send_message)

# 6. Replace clearChatHistory
old_clear_chat = '''    func clearChatHistory() {
        messages = Self.initialMessages(for: projectName)
        if !memory.latestSummary.isEmpty {
            messages.append(
                ChatMessage(role: .assistant, text: "Memory context retained: \\(memory.latestSummary)")
            )
        }
        draftMessage = ""
    }'''

new_clear_chat = '''    func clearChatHistory() {
        chatService.clearChatHistory(projectName: projectName, memoryLatestSummary: memory.latestSummary)
    }'''

content = content.replace(old_clear_chat, new_clear_chat)

# 7. Replace clearBuilderConversation
old_clear_builder = '''    func clearBuilderConversation() {
        builderMessages = Self.initialBuilderMessages(for: projectName)
        builderDraft = ""
    }'''

new_clear_builder = '''    func clearBuilderConversation() {
        chatService.clearBuilderConversation(projectName: projectName)
    }'''

content = content.replace(old_clear_builder, new_clear_builder)

# Write the modified content
with open(file_path, 'w') as f:
    f.write(content)

print("StudioViewModel.swift updated successfully")
print("Next steps:")
print("1. Remove old chat methods (sendBuilderPrompt, assistantReply, runBuilderBuildCommand, etc.)")
print("2. Add forwarding sendBuilderPrompt method")
print("3. Remove initialMessages and initialBuilderMessages static methods")
