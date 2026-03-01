import Foundation
import Testing

@testable import ImageElementStudio

@Suite("IdeaPlanner Tests")
struct IdeaPlannerTests {
    private let planner = IdeaPlanner()

    // MARK: - Tests

    @Test("Generate from idea produces valid result structure")
    func generateFromIdeaProducesValidResult() {
        let result = planner.generate(from: "A task management app with kanban boards", projectName: "TestProject")

        #expect(!result.artboards.isEmpty)
        #expect(!result.narrative.isEmpty)
        #expect(!result.scope.appType.isEmpty)
        #expect(result.blueprint.controls.count > 0)
        #expect(result.blueprint.states.count > 0)
    }

    @Test("E-commerce idea generates e-commerce screens")
    func ecommerceIdeaClassification() {
        let result = planner.generate(from: "An online store with product catalog and checkout cart", projectName: "ShopApp")

        #expect(result.scope.appType == "E-commerce Platform")
        let screenNames = result.artboards.map(\.name)
        #expect(screenNames.contains("Home"))
        #expect(screenNames.contains("Catalog"))
        #expect(screenNames.contains("Cart"))
        #expect(screenNames.contains("Checkout"))
    }

    @Test("Project management idea generates board and task screens")
    func projectManagementIdeaClassification() {
        let result = planner.generate(from: "A project management workspace with kanban boards and sprint planning", projectName: "PM Tool")

        #expect(result.scope.appType == "Project Management Workspace")
        let screenNames = result.artboards.map(\.name)
        #expect(screenNames.contains("Board"))
        #expect(screenNames.contains("Tasks"))
    }

    @Test("Social idea generates feed and messaging screens")
    func socialIdeaClassification() {
        let result = planner.generate(from: "A community app with feed posts and direct message chat", projectName: "SocialApp")

        #expect(result.scope.appType == "Social Collaboration App")
        let screenNames = result.artboards.map(\.name)
        #expect(screenNames.contains("Feed"))
        #expect(screenNames.contains("Messages"))
    }

    @Test("Login keyword adds auth screen")
    func loginKeywordAddsAuthScreen() {
        let result = planner.generate(from: "A dashboard with login and analytics reports", projectName: "DashApp")

        let screenNames = result.artboards.map(\.name)
        #expect(screenNames.contains("Auth"))
        // Auth should be the first screen
        #expect(screenNames.first == "Auth")
    }

    @Test("Mobile keyword generates mobile-sized artboards")
    func mobileKeywordGeneratesMobileSize() {
        let result = planner.generate(from: "A mobile ios app for tracking tasks", projectName: "MobileTask")

        for artboard in result.artboards {
            #expect(artboard.width == 390)
            #expect(artboard.height == 844)
        }
    }

    @Test("Desktop idea generates desktop-sized artboards")
    func desktopIdeaGeneratesDesktopSize() {
        let result = planner.generate(from: "A desktop analytics dashboard for revenue tracking", projectName: "DesktopDash")

        for artboard in result.artboards {
            #expect(artboard.width == 1366)
            #expect(artboard.height == 900)
        }
    }

    @Test("Artboards contain navigation elements")
    func artboardsContainNavigationElements() {
        let result = planner.generate(from: "A dashboard with analytics", projectName: "Test")

        for artboard in result.artboards {
            let navElements = artboard.elements.filter { $0.semanticRole == .navigationItem }
            #expect(!navElements.isEmpty, "Artboard \(artboard.name) should have navigation elements")
        }
    }

    @Test("Desktop artboards contain sidebar and metric cards")
    func desktopArtboardStructure() {
        let result = planner.generate(from: "A dashboard for kpi reporting", projectName: "KPIDash")

        let firstArtboard = result.artboards[0]
        let sidebarElements = firstArtboard.elements.filter { $0.name == "Sidebar" }
        #expect(!sidebarElements.isEmpty)

        let metricCards = firstArtboard.elements.filter { $0.name.contains("Metric Card") }
        #expect(metricCards.count == 3)
    }

    @Test("Blueprint includes navigation controls for each screen")
    func blueprintNavigationControls() {
        let result = planner.generate(from: "A simple dashboard app", projectName: "Test")

        let navControls = result.blueprint.controls.filter { $0.kind == .navigation }
        // Should have one navigation control per screen
        #expect(navControls.count == result.artboards.count)
    }

    @Test("Blueprint includes primary action button")
    func blueprintPrimaryAction() {
        let result = planner.generate(from: "A simple dashboard", projectName: "Test")

        let buttons = result.blueprint.controls.filter { $0.kind == .button }
        #expect(!buttons.isEmpty)
        #expect(buttons.first?.label == "Create / Continue")
    }

    @Test("Scope includes inferred capabilities")
    func scopeCapabilities() {
        let result = planner.generate(from: "A dashboard with analytics report and team members", projectName: "Test")

        let capabilities = result.scope.keyCapabilities
        #expect(!capabilities.isEmpty)
        #expect(capabilities.contains(where: { $0.lowercased().contains("analytics") || $0.lowercased().contains("team") }))
    }

    @Test("Build notes reference project name")
    func buildNotesReferenceProjectName() {
        let result = planner.generate(from: "A simple app", projectName: "MyProject")

        #expect(result.blueprint.buildNotes.contains(where: { $0.contains("MyProject") }))
    }

    @Test("Generate from strategy spec uses spec fields")
    func generateFromStrategySpec() {
        let spec = StrategySpec(
            id: UUID(),
            sessionID: UUID(),
            projectID: "test-project",
            createdAt: Date(),
            confidence: 0.9,
            vision: "Build a real-time analytics dashboard for tracking team performance",
            targetUsers: ["Product managers", "Engineering leads"],
            jobsToBeDone: ["Track sprint velocity", "Monitor deployment frequency"],
            mustHaveFeatures: ["KPI cards", "Trend charts", "Team roster"],
            laterFeatures: ["AI insights", "Custom reports"],
            constraints: ["6 week timeline"],
            successMetrics: ["Weekly active teams"],
            summary: "Analytics dashboard for team tracking",
            planningNotes: []
        )

        let result = planner.generate(from: spec, projectName: "TeamDash")

        #expect(result.scope.productIntent == spec.vision)
        #expect(result.scope.targetUsers == spec.targetUsers)
        #expect(result.scope.keyCapabilities == spec.mustHaveFeatures)
        #expect(!result.artboards.isEmpty)
        #expect(result.blueprint.buildNotes.contains(where: { $0.contains(spec.sessionID.uuidString) }))
    }

    @Test("Billing keyword adds billing screen")
    func billingKeywordAddsBillingScreen() {
        let result = planner.generate(from: "A dashboard with billing and subscription management", projectName: "BillApp")

        let screenNames = result.artboards.map(\.name)
        #expect(screenNames.contains("Billing"))
    }

    @Test("Maximum of 6 screens generated")
    func maxScreensEnforced() {
        let result = planner.generate(
            from: "A complex app with login, billing, checkout, cart, product, catalog, dashboard, reports, tasks",
            projectName: "BigApp"
        )

        #expect(result.artboards.count <= 6)
    }
}
