import Foundation

struct IdeaPlannerResult {
    var scope: ProductScopeSnapshot
    var blueprint: BuildBlueprint
    var artboards: [Artboard]
    var narrative: String
}

struct IdeaPlanner {
    func generate(from strategySpec: StrategySpec, projectName: String) -> IdeaPlannerResult {
        let seed = """
        \(strategySpec.vision)
        Users: \(strategySpec.targetUsers.joined(separator: ", "))
        Jobs: \(strategySpec.jobsToBeDone.joined(separator: ", "))
        Must-have: \(strategySpec.mustHaveFeatures.joined(separator: ", "))
        Later: \(strategySpec.laterFeatures.joined(separator: ", "))
        Constraints: \(strategySpec.constraints.joined(separator: ", "))
        Metrics: \(strategySpec.successMetrics.joined(separator: ", "))
        """

        var generated = generate(from: seed, projectName: projectName)
        generated.scope.productIntent = strategySpec.vision
        generated.scope.targetUsers = strategySpec.targetUsers.isEmpty ? generated.scope.targetUsers : strategySpec.targetUsers
        generated.scope.keyCapabilities = strategySpec.mustHaveFeatures.isEmpty ? generated.scope.keyCapabilities : strategySpec.mustHaveFeatures
        generated.scope.openQuestions = strategySpec.laterFeatures.map { "Defer to later release: \($0)" }
        generated.scope.summary = "Strategy spec generated \(generated.artboards.count) token-ready wireframe artboards."

        var notes = generated.blueprint.buildNotes
        notes.insert("Generated from approved strategist session \(strategySpec.sessionID.uuidString).", at: 0)
        notes.insert("Strategy confidence: \(Int((strategySpec.confidence * 100).rounded()))%.", at: 1)
        generated.blueprint.buildNotes = Array(notes.prefix(8))

        generated.narrative = """
        Strategy-backed mockups ready: \(generated.artboards.count) wireframe screens generated \
        from an approved strategist spec.
        """
        return generated
    }

    func generate(from idea: String, projectName: String) -> IdeaPlannerResult {
        let normalized = normalize(idea)
        let platform = inferPlatform(from: normalized)
        let classification = classifyIdea(from: normalized)
        let screens = inferScreens(from: normalized, appType: classification.appType)

        let size = canvasSize(for: platform)
        let artboards = screens.enumerated().map { index, screen in
            wireframeArtboard(
                screenName: screen.name,
                screenFocus: screen.focus,
                allScreens: screens.map(\.name),
                appType: classification.appType,
                index: index,
                size: size,
                platform: platform
            )
        }

        let capabilities = inferCapabilities(from: normalized, appType: classification.appType)
        let scope = ProductScopeSnapshot(
            appType: classification.appType,
            confidence: classification.confidence,
            productIntent: "Transform idea into wireframes, state map, and build scaffolds for \(classification.appType.lowercased()).",
            targetUsers: classification.targetUsers,
            keyCapabilities: capabilities,
            openQuestions: inferOpenQuestions(from: normalized, appType: classification.appType),
            implementationRoadmap: [
                "Generate wireframes from idea and confirm navigation/state flows.",
                "Convert approved wireframes into semantic JSON with reusable components.",
                "Bind data models and API contracts for each screen state.",
                "Generate target scaffolds and iterate toward production UI.",
            ],
            summary: "Idea planner generated \(artboards.count) wireframe artboards for \(classification.appType)."
        )

        let controls = inferControls(screens: screens)
        let states = screens.map { screen in
            InferredState(
                id: UUID(),
                name: "Screen: \(screen.name)",
                triggerControlID: nil,
                triggerLabel: screen.name,
                description: "Wireframe state for \(screen.focus).",
                confidence: 0.92
            )
        }
        let suggestedArtboards = screens.map { screen in
            SuggestedArtboard(
                id: UUID(),
                name: "State • \(screen.name)",
                sourceStateID: nil,
                reason: "Generated from idea prompt.",
                confidence: 0.9
            )
        }

        let blueprint = BuildBlueprint(
            mirrorScore: 0.78,
            detectionSummary: "Idea mode generated a full wireframe set from text prompt with \(controls.count) controls and \(states.count) states.",
            controls: controls,
            states: states,
            suggestedArtboards: suggestedArtboards,
            buildNotes: [
                "Project '\(projectName)' is running in idea-first mode.",
                "Validate the generated screens and rename/reorder artboards as needed.",
                "Upload reference designs later to refine visual fidelity.",
            ]
        )

        let narrative = """
        Idea workflow ready: I created \(artboards.count) wireframe screens for \(classification.appType). \
        Review the emulator view, refine scope, and then run build setup.
        """

        return IdeaPlannerResult(
            scope: scope,
            blueprint: blueprint,
            artboards: artboards,
            narrative: narrative
        )
    }

    private func inferPlatform(from normalizedIdea: String) -> WireframePlatform {
        if containsAny(normalizedIdea, words: ["mobile", "ios", "iphone", "android", "phone"]) {
            return .mobile
        }
        return .desktop
    }

    private func classifyIdea(from normalizedIdea: String) -> (appType: String, confidence: Double, targetUsers: [String]) {
        let candidates: [(type: String, keywords: [String], users: [String])] = [
            (
                type: "E-commerce Platform",
                keywords: ["cart", "checkout", "product", "order", "catalog", "inventory", "shop", "store"],
                users: ["Customers", "Store admins", "Operations teams"]
            ),
            (
                type: "Project Management Workspace",
                keywords: ["task", "project", "kanban", "sprint", "roadmap", "milestone", "deadline", "team"],
                users: ["Project managers", "Product teams", "Engineering teams"]
            ),
            (
                type: "Social Collaboration App",
                keywords: ["feed", "post", "message", "chat", "comment", "community", "follow"],
                users: ["Community members", "Creators", "Moderators"]
            ),
            (
                type: "Business Analytics Dashboard",
                keywords: ["dashboard", "analytics", "report", "metric", "kpi", "performance", "revenue"],
                users: ["Operations managers", "Executives", "Analysts"]
            ),
        ]

        var best = candidates.last!
        var bestScore = -1

        for candidate in candidates {
            let score = candidate.keywords.reduce(into: 0) { partial, keyword in
                if normalizedIdea.contains(keyword) {
                    partial += 1
                }
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }

        let confidence = min(0.96, 0.55 + (Double(max(0, bestScore)) * 0.08))
        return (best.type, confidence, best.users)
    }

    private func inferScreens(from normalizedIdea: String, appType: String) -> [WireframeScreen] {
        var screens: [WireframeScreen]

        if appType.contains("E-commerce") {
            screens = [
                WireframeScreen(name: "Home", focus: "Landing, highlights, and categories"),
                WireframeScreen(name: "Catalog", focus: "Search and browse products"),
                WireframeScreen(name: "Product", focus: "Product details and purchase controls"),
                WireframeScreen(name: "Cart", focus: "Review items before checkout"),
                WireframeScreen(name: "Checkout", focus: "Address, payment, and confirmation"),
            ]
        } else if appType.contains("Project Management") {
            screens = [
                WireframeScreen(name: "Overview", focus: "Portfolio metrics and activity"),
                WireframeScreen(name: "Board", focus: "Kanban workflow and task states"),
                WireframeScreen(name: "Tasks", focus: "Task list, filters, and assignment"),
                WireframeScreen(name: "Calendar", focus: "Timeline and due dates"),
            ]
        } else if appType.contains("Social") {
            screens = [
                WireframeScreen(name: "Feed", focus: "Content stream and engagement"),
                WireframeScreen(name: "Compose", focus: "Create new content"),
                WireframeScreen(name: "Messages", focus: "Direct communication"),
                WireframeScreen(name: "Profile", focus: "User identity and settings"),
            ]
        } else {
            screens = [
                WireframeScreen(name: "Dashboard", focus: "KPI cards and overview"),
                WireframeScreen(name: "Reports", focus: "Detailed insights and trends"),
                WireframeScreen(name: "Operations", focus: "Team and process tracking"),
                WireframeScreen(name: "Settings", focus: "Configuration and management"),
            ]
        }

        if containsAny(normalizedIdea, words: ["login", "auth", "sign in", "signup"]) {
            screens.insert(
                WireframeScreen(name: "Auth", focus: "Login and onboarding"),
                at: 0
            )
        }

        if containsAny(normalizedIdea, words: ["billing", "payment", "subscription"]) && !screens.contains(where: { $0.name == "Billing" }) {
            screens.append(WireframeScreen(name: "Billing", focus: "Plans, invoices, and payment settings"))
        }

        return Array(screens.prefix(6))
    }

    private func inferCapabilities(from normalizedIdea: String, appType: String) -> [String] {
        var capabilities: [String] = []

        if containsAny(normalizedIdea, words: ["chat", "message", "assistant"]) {
            capabilities.append("Real-time messaging and collaboration")
        }
        if containsAny(normalizedIdea, words: ["analytics", "kpi", "report", "metric"]) {
            capabilities.append("Analytics dashboards with KPI cards and trend views")
        }
        if containsAny(normalizedIdea, words: ["task", "project", "board"]) {
            capabilities.append("Task management workflow with multi-state progress")
        }
        if containsAny(normalizedIdea, words: ["checkout", "cart", "payment"]) {
            capabilities.append("Commerce flow from catalog to checkout")
        }
        if containsAny(normalizedIdea, words: ["team", "member", "employee"]) {
            capabilities.append("Team management and role-oriented views")
        }
        if containsAny(normalizedIdea, words: ["settings", "admin", "config"]) {
            capabilities.append("Administrative settings and configuration")
        }

        if capabilities.isEmpty {
            capabilities.append("Modular UI with screen-based navigation and action workflows")
        }

        if !capabilities.contains(where: { $0.lowercased().contains("navigation") }) {
            capabilities.append("Multi-screen navigation with state transitions")
        }

        return Array(capabilities.prefix(7))
    }

    private func inferOpenQuestions(from normalizedIdea: String, appType: String) -> [String] {
        var questions: [String] = []

        if !containsAny(normalizedIdea, words: ["auth", "login", "signup"]) {
            questions.append("Should user authentication be required at launch?")
        }
        if !containsAny(normalizedIdea, words: ["api", "database", "data"]) {
            questions.append("What data source should power the \(appType.lowercased())?")
        }
        questions.append("Which target platform should be prioritized first: iOS, macOS, or Web?")
        questions.append("What is the primary user success metric for version 1?")
        return questions
    }

    private func inferControls(screens: [WireframeScreen]) -> [InferredControl] {
        var controls = screens.map { screen in
            InferredControl(
                id: UUID(),
                name: "Navigation Control",
                label: screen.name,
                kind: .navigation,
                role: .navigationItem,
                sourceElementID: nil,
                frame: nil,
                confidence: 0.9,
                rationale: "Generated from idea-based screen map."
            )
        }

        controls.append(
            InferredControl(
                id: UUID(),
                name: "Primary Action",
                label: "Create / Continue",
                kind: .button,
                role: .buttonPrimary,
                sourceElementID: nil,
                frame: nil,
                confidence: 0.86,
                rationale: "Default CTA added for wireframe interaction flow."
            )
        )

        return controls
    }

    private func wireframeArtboard(
        screenName: String,
        screenFocus: String,
        allScreens: [String],
        appType: String,
        index: Int,
        size: CGSize,
        platform: WireframePlatform
    ) -> Artboard {
        let width = Int(size.width)
        let height = Int(size.height)
        var elements: [CanvasElement] = [CanvasElement.root(width: width, height: height, filename: "idea-wireframe")]

        if platform == .desktop {
            elements.append(
                shape(
                    name: "Sidebar",
                    frame: ElementFrame(x: 0, y: 0, width: 230, height: Double(height)),
                    role: .panel
                )
            )
            elements.append(
                text(
                    name: "App Title",
                    content: appType,
                    frame: ElementFrame(x: 20, y: 20, width: 190, height: 34),
                    role: .heading
                )
            )

            let navStartY = 78.0
            for (navIndex, navName) in allScreens.prefix(6).enumerated() {
                elements.append(
                    text(
                        name: "Nav \(navName)",
                        content: navName,
                        frame: ElementFrame(x: 20, y: navStartY + (Double(navIndex) * 38), width: 180, height: 26),
                        role: .navigationItem
                    )
                )
            }

            elements.append(
                shape(
                    name: "Header Panel",
                    frame: ElementFrame(x: 250, y: 18, width: Double(width) - 280, height: 58),
                    role: .panel
                )
            )
            elements.append(
                text(
                    name: "Screen Heading",
                    content: screenName,
                    frame: ElementFrame(x: 274, y: 32, width: 350, height: 30),
                    role: .heading
                )
            )
            elements.append(
                shape(
                    name: "Primary Button",
                    frame: ElementFrame(x: Double(width) - 260, y: 28, width: 140, height: 34),
                    role: .buttonPrimary
                )
            )
            elements.append(
                text(
                    name: "Primary CTA",
                    content: "Create",
                    frame: ElementFrame(x: Double(width) - 224, y: 35, width: 72, height: 18),
                    role: .buttonPrimary
                )
            )

            let contentStartX = 250.0
            let contentWidth = Double(width) - 280
            let cardWidth = max(140.0, (contentWidth - 36) / 3)
            let cardY = 98.0
            for cardIndex in 0..<3 {
                let x = contentStartX + (Double(cardIndex) * (cardWidth + 18))
                elements.append(
                    shape(
                        name: "Metric Card \(cardIndex + 1)",
                        frame: ElementFrame(x: x, y: cardY, width: cardWidth, height: 110),
                        role: .panel
                    )
                )
                elements.append(
                    text(
                        name: "Metric Title \(cardIndex + 1)",
                        content: "Metric \(cardIndex + 1)",
                        frame: ElementFrame(x: x + 14, y: cardY + 16, width: cardWidth - 20, height: 18),
                        role: .metricLabel
                    )
                )
                elements.append(
                    text(
                        name: "Metric Value \(cardIndex + 1)",
                        content: "\(80 + (cardIndex * 6))",
                        frame: ElementFrame(x: x + 14, y: cardY + 44, width: 90, height: 34),
                        role: .metricValue
                    )
                )
            }

            elements.append(
                shape(
                    name: "Primary Content Panel",
                    frame: ElementFrame(x: contentStartX, y: 232, width: contentWidth, height: 250),
                    role: .chart
                )
            )
            elements.append(
                text(
                    name: "Content Focus",
                    content: screenFocus,
                    frame: ElementFrame(x: contentStartX + 16, y: 250, width: contentWidth - 20, height: 24),
                    role: .sectionTitle
                )
            )
            elements.append(
                shape(
                    name: "Secondary Content Panel",
                    frame: ElementFrame(x: contentStartX, y: 500, width: contentWidth, height: Double(height) - 540),
                    role: .panel
                )
            )
        } else {
            elements.append(
                shape(
                    name: "Top Bar",
                    frame: ElementFrame(x: 0, y: 0, width: Double(width), height: 70),
                    role: .panel
                )
            )
            elements.append(
                text(
                    name: "Screen Heading",
                    content: screenName,
                    frame: ElementFrame(x: 20, y: 24, width: Double(width) - 100, height: 30),
                    role: .heading
                )
            )
            elements.append(
                shape(
                    name: "Hero Card",
                    frame: ElementFrame(x: 16, y: 94, width: Double(width) - 32, height: 180),
                    role: .panel
                )
            )
            elements.append(
                text(
                    name: "Hero Focus",
                    content: screenFocus,
                    frame: ElementFrame(x: 30, y: 116, width: Double(width) - 56, height: 44),
                    role: .sectionTitle
                )
            )

            var listY = 300.0
            for itemIndex in 0..<3 {
                elements.append(
                    shape(
                        name: "List Row \(itemIndex + 1)",
                        frame: ElementFrame(x: 16, y: listY, width: Double(width) - 32, height: 78),
                        role: .listItem
                    )
                )
                elements.append(
                    text(
                        name: "List Label \(itemIndex + 1)",
                        content: "Item \(itemIndex + 1)",
                        frame: ElementFrame(x: 32, y: listY + 24, width: Double(width) - 120, height: 24),
                        role: .metricLabel
                    )
                )
                listY += 92
            }

            elements.append(
                shape(
                    name: "Bottom Nav",
                    frame: ElementFrame(x: 0, y: Double(height) - 90, width: Double(width), height: 90),
                    role: .panel
                )
            )
            for (navIndex, navName) in allScreens.prefix(4).enumerated() {
                let segmentWidth = Double(width) / 4
                let x = segmentWidth * Double(navIndex)
                elements.append(
                    text(
                        name: "Nav \(navName)",
                        content: navName,
                        frame: ElementFrame(x: x + 10, y: Double(height) - 58, width: segmentWidth - 20, height: 24),
                        role: .navigationItem
                    )
                )
            }
        }

        return Artboard(
            id: UUID(),
            name: screenName,
            width: width,
            height: height,
            elements: elements
        )
    }

    private func canvasSize(for platform: WireframePlatform) -> CGSize {
        switch platform {
        case .desktop:
            return CGSize(width: 1366, height: 900)
        case .mobile:
            return CGSize(width: 390, height: 844)
        }
    }

    private func text(
        name: String,
        content: String,
        frame: ElementFrame,
        role: SemanticElementRole
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: name,
            kind: .text,
            frame: frame,
            confidence: 0.92,
            content: content,
            tags: ["idea-wireframe", "semantic:\(role.rawValue)"],
            semanticRole: role,
            semanticReason: "Generated from idea prompt"
        )
    }

    private func shape(
        name: String,
        frame: ElementFrame,
        role: SemanticElementRole
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: name,
            kind: .shape,
            frame: frame,
            confidence: 0.9,
            content: nil,
            tags: ["idea-wireframe", "semantic:\(role.rawValue)"],
            semanticRole: role,
            semanticReason: "Generated wireframe container"
        )
    }

    private func containsAny(_ value: String, words: [String]) -> Bool {
        words.contains { value.contains($0) }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WireframeScreen {
    var name: String
    var focus: String
}

private enum WireframePlatform {
    case desktop
    case mobile
}
