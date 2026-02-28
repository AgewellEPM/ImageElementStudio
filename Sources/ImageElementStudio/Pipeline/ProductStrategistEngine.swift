import Foundation

struct ProductStrategistEngine {
    private struct QuestionTemplate {
        var id: String
        var prompt: String
        var whyAsked: String
        var required: Bool
        var options: [String]?
    }

    func startSession(projectID: String, idea: String, mode: PipelineMode) -> StrategySession {
        let seed = normalize(idea)
        let stage = StrategyStage.vision
        return StrategySession(
            id: UUID(),
            projectID: projectID,
            stage: stage,
            ideaSeed: seed,
            questions: questions(for: stage),
            answers: [],
            confidence: 0.0,
            isComplete: false,
            pipelineMode: mode,
            createdAt: Date()
        )
    }

    func activeQuestion(in session: StrategySession) -> StrategyQuestion? {
        let answered = Set(session.answers.map(\.questionID))
        return session.questions.first(where: { question in
            question.stage == session.stage && !answered.contains(question.id)
        })
    }

    func submit(
        answerText: String,
        questionID: String,
        in session: StrategySession,
        skipped: Bool = false
    ) -> StrategySession {
        var updated = session
        guard let question = updated.questions.first(where: { $0.id == questionID }) else {
            return updated
        }

        let cleaned = normalize(answerText)
        guard !cleaned.isEmpty else { return updated }

        let confidence = skipped
            ? 0.62
            : score(answerText: cleaned, stage: question.stage)

        let answer = StrategyAnswer(
            questionID: questionID,
            answerText: cleaned,
            confidence: confidence,
            createdAt: Date()
        )

        if let answerIndex = updated.answers.firstIndex(where: { $0.questionID == questionID }) {
            updated.answers[answerIndex] = answer
        } else {
            updated.answers.append(answer)
        }

        if confidence < 0.55, !skipped {
            let followupID = "\(questionID)-followup"
            let alreadyInserted = updated.questions.contains(where: { $0.id == followupID })
            if !alreadyInserted {
                let followup = StrategyQuestion(
                    id: followupID,
                    stage: question.stage,
                    prompt: followupPrompt(for: question.stage),
                    whyAsked: "Initial answer had low confidence. Follow-up tightens planning quality.",
                    required: true,
                    options: nil
                )
                if let questionIndex = updated.questions.firstIndex(where: { $0.id == questionID }) {
                    updated.questions.insert(followup, at: questionIndex + 1)
                } else {
                    updated.questions.append(followup)
                }
            }
        }

        updated.confidence = sessionConfidence(updated.answers)
        updated.isComplete = isSessionComplete(updated)
        return updated
    }

    func canApproveCurrentStage(_ session: StrategySession) -> Bool {
        let answered = Set(session.answers.map(\.questionID))
        let requiredQuestions = session.questions.filter { question in
            question.stage == session.stage && question.required
        }
        return requiredQuestions.allSatisfy { answered.contains($0.id) }
    }

    func approveCurrentStage(in session: StrategySession) -> StrategySession {
        var updated = session
        guard canApproveCurrentStage(updated) else { return updated }

        if let next = updated.stage.next {
            updated.stage = next
            if !updated.questions.contains(where: { $0.stage == next }) {
                updated.questions.append(contentsOf: questions(for: next))
            }
            updated.isComplete = false
        } else {
            updated.isComplete = isSessionComplete(updated)
        }

        updated.confidence = sessionConfidence(updated.answers)
        return updated
    }

    func autoRun(session: StrategySession) -> StrategySession {
        var updated = session
        var safetyCounter = 0

        while !updated.isComplete, safetyCounter < 60 {
            safetyCounter += 1

            if let question = activeQuestion(in: updated) {
                let answer = autoAnswer(for: question, session: updated)
                updated = submit(answerText: answer, questionID: question.id, in: updated)
                continue
            }

            if canApproveCurrentStage(updated) {
                updated = approveCurrentStage(in: updated)
                continue
            }

            break
        }

        updated.isComplete = isSessionComplete(updated)
        return updated
    }

    func finalizeSpec(from session: StrategySession) -> StrategySpec? {
        guard isSessionComplete(session) else { return nil }

        let vision = stageSummary(for: .vision, session: session, fallback: session.ideaSeed)
        let users = stageList(for: .users, session: session, fallback: ["Primary users not specified"])
        let jobs = stageList(for: .jobs, session: session, fallback: ["Define top jobs-to-be-done"])
        let scopedFeatures = splitFeatureScope(stageText: stageSummary(for: .feature_scope, session: session, fallback: "Define launch and later features"))
        let constraints = stageList(for: .constraints, session: session, fallback: ["No major constraints provided"])
        let metrics = stageList(for: .success_metrics, session: session, fallback: ["Define launch success metric"])
        let confidence = max(0.5, sessionConfidence(session.answers))

        let summary = """
        \(vision). Target users: \(joined(users)). Must-have: \(joined(scopedFeatures.must)). \
        Success metrics: \(joined(metrics)).
        """

        return StrategySpec(
            id: UUID(),
            sessionID: session.id,
            projectID: session.projectID,
            createdAt: Date(),
            confidence: confidence,
            vision: vision,
            targetUsers: users,
            jobsToBeDone: jobs,
            mustHaveFeatures: scopedFeatures.must,
            laterFeatures: scopedFeatures.later,
            constraints: constraints,
            successMetrics: metrics,
            summary: normalize(summary),
            planningNotes: [
                "Generated via 6-stage strategist flow.",
                "Session confidence \(Int((confidence * 100).rounded()))%.",
            ]
        )
    }

    private func isSessionComplete(_ session: StrategySession) -> Bool {
        let answered = Set(session.answers.map(\.questionID))
        for stage in StrategyStage.allCases {
            let required = session.questions.filter { $0.stage == stage && $0.required }
            if required.isEmpty { return false }
            if required.contains(where: { !answered.contains($0.id) }) {
                return false
            }
        }
        return session.stage == .success_metrics
    }

    private func sessionConfidence(_ answers: [StrategyAnswer]) -> Double {
        guard !answers.isEmpty else { return 0.0 }
        let mean = answers.map(\.confidence).reduce(0, +) / Double(answers.count)
        return max(0.15, min(0.97, mean))
    }

    private func stageSummary(for stage: StrategyStage, session: StrategySession, fallback: String) -> String {
        let answers = stageAnswers(for: stage, session: session)
        guard !answers.isEmpty else { return fallback }
        return normalize(answers.joined(separator: " "))
    }

    private func stageList(for stage: StrategyStage, session: StrategySession, fallback: [String]) -> [String] {
        let answers = stageAnswers(for: stage, session: session)
        let parsed = parseList(from: answers)
        return parsed.isEmpty ? fallback : parsed
    }

    private func stageAnswers(for stage: StrategyStage, session: StrategySession) -> [String] {
        let questions = session.questions.filter { $0.stage == stage }
        let map = Dictionary(uniqueKeysWithValues: session.answers.map { ($0.questionID, $0.answerText) })
        return questions.compactMap { map[$0.id] }
    }

    private func splitFeatureScope(stageText: String) -> (must: [String], later: [String]) {
        let items = parseList(from: [stageText])
        if items.isEmpty {
            return (["Define launch-critical features"], ["Defer non-core enhancements"])
        }

        let midpoint = max(1, items.count / 2)
        let must = Array(items.prefix(midpoint))
        let later = Array(items.dropFirst(midpoint))
        return (must, later.isEmpty ? ["Defer non-core enhancements"] : later)
    }

    private func joined(_ values: [String]) -> String {
        let nonEmpty = values.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? "N/A" : nonEmpty.joined(separator: ", ")
    }

    private func parseList(from inputs: [String]) -> [String] {
        var output: [String] = []

        for input in inputs {
            let normalized = input
                .replacingOccurrences(of: "\n", with: ",")
                .replacingOccurrences(of: ";", with: ",")
            for rawPart in normalized.split(separator: ",") {
                let cleaned = rawPart
                    .replacingOccurrences(of: #"^\s*[-*0-9.)]+\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 2 {
                    output.append(cleaned)
                }
            }
        }

        var deduped: [String] = []
        for item in output {
            if !deduped.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                deduped.append(item)
            }
        }
        return Array(deduped.prefix(8))
    }

    private func score(answerText: String, stage: StrategyStage) -> Double {
        let words = answerText.split(whereSeparator: \.isWhitespace)
        var score = 0.28

        if words.count >= 8 { score += 0.2 }
        if words.count >= 16 { score += 0.15 }
        if answerText.count >= 32 { score += 0.14 }
        if answerText.contains(",") || answerText.contains(";") || answerText.contains("\n") { score += 0.08 }
        if answerText.contains("%") || answerText.contains("week") || answerText.contains("month") || answerText.contains("quarter") {
            score += 0.08
        }
        if answerText.contains("because") || answerText.contains("so that") || answerText.contains("therefore") {
            score += 0.06
        }
        if answerText.contains("skip") { score = max(score, 0.62) }

        switch stage {
        case .success_metrics:
            if answerText.contains("%") || answerText.contains("target") {
                score += 0.07
            }
        case .constraints:
            if answerText.contains("timeline") || answerText.contains("budget") || answerText.contains("team") {
                score += 0.05
            }
        default:
            break
        }

        return max(0.15, min(0.96, score))
    }

    private func autoAnswer(for question: StrategyQuestion, session: StrategySession) -> String {
        switch question.stage {
        case .vision:
            return "Build \(session.ideaSeed) as a focused v1 product that reduces user friction and delivers one clear outcome within the first week of usage."
        case .users:
            return "Primary users are operators and decision-makers who need faster workflows; secondary users are collaborators who consume updates."
        case .jobs:
            return "When tasks change, users need clear priorities, reliable status updates, and one place to complete key actions quickly."
        case .feature_scope:
            return "Must-have: onboarding, core workflow dashboard, task/detail actions, notifications. Later: advanced analytics, deep customization, and automation rules."
        case .constraints:
            return "Constraints include a six-week timeline, small team capacity, and preference for managed backend services with straightforward auth and data models."
        case .success_metrics:
            return "Primary success metric is weekly active teams with a 20% week-4 retention target, plus guardrails for crash-free sessions above 99% and response latency under 300ms."
        }
    }

    private func followupPrompt(for stage: StrategyStage) -> String {
        switch stage {
        case .vision:
            return "Can you rewrite the vision with one user outcome and a concrete v1 boundary?"
        case .users:
            return "Can you narrow this to one primary segment and one secondary segment?"
        case .jobs:
            return "Can you express each job as: when X, user wants Y, so they can Z?"
        case .feature_scope:
            return "Which feature is non-negotiable for launch, and which can definitely wait?"
        case .constraints:
            return "What is the hardest constraint and what mitigation should we plan now?"
        case .success_metrics:
            return "What numeric target and timeframe define success for the first release?"
        }
    }

    private func questions(for stage: StrategyStage) -> [StrategyQuestion] {
        templates(for: stage).map { template in
            StrategyQuestion(
                id: "\(stage.rawValue)-\(template.id)",
                stage: stage,
                prompt: template.prompt,
                whyAsked: template.whyAsked,
                required: template.required,
                options: template.options
            )
        }
    }

    private func templates(for stage: StrategyStage) -> [QuestionTemplate] {
        switch stage {
        case .vision:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "What are we building in one sentence, and what user outcome should improve first?",
                    whyAsked: "Defines product direction before feature planning.",
                    required: true,
                    options: nil
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "What is the smallest useful launch boundary for V1?",
                    whyAsked: "Prevents scope drift before design/code generation.",
                    required: true,
                    options: ["Single workflow", "Limited beta feature set", "Core module only"]
                ),
            ]
        case .users:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "Who are the primary users, and who is secondary for launch?",
                    whyAsked: "User segmentation drives design and architecture choices.",
                    required: true,
                    options: nil
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "Which users are intentionally out of scope in V1?",
                    whyAsked: "Out-of-scope users keep product scope realistic.",
                    required: true,
                    options: nil
                ),
            ]
        case .jobs:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "List the top jobs users need done with this product.",
                    whyAsked: "Jobs-to-be-done align interface and workflow priorities.",
                    required: true,
                    options: nil
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "Which job is highest priority on day one?",
                    whyAsked: "Prioritization drives must-have feature selection.",
                    required: true,
                    options: nil
                ),
            ]
        case .feature_scope:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "What are the 3-6 must-have features for launch?",
                    whyAsked: "Must-haves form the immediate build scope.",
                    required: true,
                    options: nil
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "Which features should explicitly be deferred to later releases?",
                    whyAsked: "Deferrals reduce launch complexity and timeline risk.",
                    required: true,
                    options: nil
                ),
            ]
        case .constraints:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "What constraints matter most (timeline, team, compliance, integrations, platform)?",
                    whyAsked: "Constraints affect architecture and delivery sequencing.",
                    required: true,
                    options: nil
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "What technical or business dependencies are mandatory for launch?",
                    whyAsked: "Dependencies determine feasibility and risk.",
                    required: true,
                    options: nil
                ),
            ]
        case .success_metrics:
            return [
                QuestionTemplate(
                    id: "1",
                    prompt: "What primary metric defines launch success?",
                    whyAsked: "A clear metric is needed for release decisions.",
                    required: true,
                    options: ["Retention", "Activation", "Revenue", "Task completion"]
                ),
                QuestionTemplate(
                    id: "2",
                    prompt: "What guardrail metrics protect quality and reliability?",
                    whyAsked: "Guardrails prevent growth at the cost of product health.",
                    required: true,
                    options: ["Crash-free sessions", "Latency", "Support volume", "Churn"]
                ),
            ]
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
