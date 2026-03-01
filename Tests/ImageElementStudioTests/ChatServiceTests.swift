import XCTest
@testable import ImageElementStudio

@MainActor
final class ChatServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(projectName: String = "TestProject") -> ChatService {
        ChatService(projectName: projectName)
    }

    // MARK: - Initial Messages

    func testInitialMessagesContainsSystemAndAssistantMessages() {
        let messages = ChatService.initialMessages(for: "MyApp")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testInitialMessagesIncludesProjectName() {
        let messages = ChatService.initialMessages(for: "WidgetHub")
        XCTAssertTrue(messages[1].text.contains("WidgetHub"))
    }

    func testInitialBuilderMessagesContainsOneAssistantMessage() {
        let messages = ChatService.initialBuilderMessages(for: "MyApp")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .assistant)
    }

    func testInitialBuilderMessagesIncludesProjectName() {
        let messages = ChatService.initialBuilderMessages(for: "SalesTracker")
        XCTAssertTrue(messages[0].text.contains("SalesTracker"))
    }

    // MARK: - Init

    func testInitSetsMessagesFromProjectName() {
        let service = makeService(projectName: "Alpha")
        XCTAssertEqual(service.messages.count, 2)
        XCTAssertTrue(service.messages[1].text.contains("Alpha"))
        XCTAssertEqual(service.builderMessages.count, 1)
        XCTAssertTrue(service.builderMessages[0].text.contains("Alpha"))
    }

    // MARK: - clearChatHistory

    func testClearChatHistoryResetsMessages() {
        let service = makeService(projectName: "Demo")
        service.messages.append(ChatMessage(role: .user, text: "Hello"))
        service.messages.append(ChatMessage(role: .assistant, text: "Hi"))
        service.draftMessage = "pending draft"

        service.clearChatHistory(projectName: "Demo", memoryLatestSummary: "")

        // Should reset to initial messages (2) with no extra memory message
        XCTAssertEqual(service.messages.count, 2)
        XCTAssertEqual(service.messages[0].role, .system)
        XCTAssertEqual(service.messages[1].role, .assistant)
        XCTAssertEqual(service.draftMessage, "")
    }

    func testClearChatHistoryAppendsMemorySummaryWhenNonEmpty() {
        let service = makeService(projectName: "Demo")

        service.clearChatHistory(projectName: "Demo", memoryLatestSummary: "Latest summary of work done.")

        XCTAssertEqual(service.messages.count, 3)
        XCTAssertEqual(service.messages[2].role, .assistant)
        XCTAssertTrue(service.messages[2].text.contains("Memory context retained"))
        XCTAssertTrue(service.messages[2].text.contains("Latest summary of work done."))
    }

    func testClearChatHistoryDoesNotAppendEmptyMemorySummary() {
        let service = makeService(projectName: "Demo")

        service.clearChatHistory(projectName: "Demo", memoryLatestSummary: "")

        XCTAssertEqual(service.messages.count, 2)
    }

    // MARK: - clearBuilderConversation

    func testClearBuilderConversationResetsMessages() {
        let service = makeService(projectName: "Demo")
        service.builderMessages.append(ChatMessage(role: .user, text: "build it"))
        service.builderMessages.append(ChatMessage(role: .assistant, text: "ok"))
        service.builderDraft = "some draft"

        service.clearBuilderConversation(projectName: "Demo")

        XCTAssertEqual(service.builderMessages.count, 1)
        XCTAssertEqual(service.builderMessages[0].role, .assistant)
        XCTAssertTrue(service.builderMessages[0].text.contains("Demo"))
        XCTAssertEqual(service.builderDraft, "")
    }

    // MARK: - extractIdeaPrompt (via sendBuilderPrompt behavior)

    func testExtractIdeaPromptStripsIdeaPrefix() {
        // We test this indirectly by checking that "idea: food delivery app"
        // triggers onStartStrategy with the stripped prompt
        let service = makeService()
        service.builderDraft = "idea: food delivery app"

        var receivedPrompt = ""
        var registry = ChatService.BuilderCommandRegistry()
        registry.onStartStrategy = { prompt in receivedPrompt = prompt }

        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertEqual(receivedPrompt, "food delivery app")
    }

    // MARK: - Builder command parsing

    func testSetModeAutoCommand() {
        let service = makeService()
        service.builderDraft = "set mode auto"
        var receivedMode: PipelineMode?

        var registry = ChatService.BuilderCommandRegistry()
        registry.onSetPipelineMode = { mode in receivedMode = mode }

        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertEqual(receivedMode, .auto)
        XCTAssertTrue(service.builderMessages.last?.text.contains("Auto") ?? false)
    }

    func testSetModeGuidedCommand() {
        let service = makeService()
        service.builderDraft = "mode guided"
        var receivedMode: PipelineMode?

        var registry = ChatService.BuilderCommandRegistry()
        registry.onSetPipelineMode = { receivedMode = $0 }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertEqual(receivedMode, .guided)
    }

    func testSetModeHybridCommand() {
        let service = makeService()
        service.builderDraft = "set mode hybrid"
        var receivedMode: PipelineMode?

        var registry = ChatService.BuilderCommandRegistry()
        registry.onSetPipelineMode = { receivedMode = $0 }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertEqual(receivedMode, .hybrid)
    }

    func testDistributeHorizontalCommand() {
        let service = makeService()
        service.builderDraft = "distribute horizontal"
        var called = false

        var registry = ChatService.BuilderCommandRegistry()
        registry.onDistributeHorizontally = { called = true }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertTrue(called)
        XCTAssertTrue(service.builderMessages.last?.text.contains("horizontal distribution") ?? false)
    }

    func testDistributeVerticalCommand() {
        let service = makeService()
        service.builderDraft = "distribute vertical"
        var called = false

        var registry = ChatService.BuilderCommandRegistry()
        registry.onDistributeVertically = { called = true }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertTrue(called)
    }

    func testCreateComponentCommand() {
        let service = makeService()
        service.builderDraft = "create component"
        var called = false

        var registry = ChatService.BuilderCommandRegistry()
        registry.onCreateComponent = { called = true }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertTrue(called)
    }

    func testNewInstanceCommand() {
        let service = makeService()
        service.builderDraft = "new instance"
        var called = false

        var registry = ChatService.BuilderCommandRegistry()
        registry.onCreateComponentInstance = { called = true }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertTrue(called)
    }

    func testNewArtboardCommand() {
        let service = makeService()
        service.builderDraft = "new artboard"
        var called = false

        var registry = ChatService.BuilderCommandRegistry()
        registry.onAddArtboard = { called = true }
        service.sendBuilderPrompt(context: makeBuilderContext(), registry: registry)

        XCTAssertTrue(called)
        XCTAssertTrue(service.builderMessages.last?.text.contains("artboard") ?? false)
    }

    func testEmptyBuilderDraftIsIgnored() {
        let service = makeService()
        service.builderDraft = "   "

        service.sendBuilderPrompt(context: makeBuilderContext(), registry: ChatService.BuilderCommandRegistry())

        // Only the initial builder message should remain, nothing appended
        XCTAssertEqual(service.builderMessages.count, 1)
    }

    func testBuilderDraftIsClearedAfterSend() {
        let service = makeService()
        service.builderDraft = "new artboard"

        service.sendBuilderPrompt(context: makeBuilderContext(), registry: ChatService.BuilderCommandRegistry())

        XCTAssertEqual(service.builderDraft, "")
    }

    func testUserMessageIsAppendedToBuilderMessages() {
        let service = makeService()
        service.builderDraft = "new artboard"

        service.sendBuilderPrompt(context: makeBuilderContext(), registry: ChatService.BuilderCommandRegistry())

        let userMessages = service.builderMessages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.first?.text, "new artboard")
    }

    // MARK: - Helper for building context

    private func makeBuilderContext(
        isAnalyzing: Bool = false,
        pipelineMode: PipelineMode = .auto,
        selectedImage: Any? = nil,
        acceptedStrategySpec: StrategySpec? = nil,
        renderableElements: [CanvasElement] = [],
        latestScope: ProductScopeSnapshot? = nil,
        strategySession: StrategySession? = nil,
        strategyActiveQuestion: StrategyQuestion? = nil,
        projectName: String = "TestProject"
    ) -> ChatService.BuilderCommandContext {
        ChatService.BuilderCommandContext(
            isAnalyzing: isAnalyzing,
            pipelineMode: pipelineMode,
            selectedImage: nil,
            acceptedStrategySpec: acceptedStrategySpec,
            renderableElements: renderableElements,
            latestScope: latestScope,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            projectName: projectName
        )
    }
}
