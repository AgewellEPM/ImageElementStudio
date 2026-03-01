import Foundation

// MARK: - BenchmarkContext

/// Captures the ViewModel state and action callbacks needed by benchmark methods.
/// The ViewModel constructs one of these before invoking benchmark operations on the service.
struct BenchmarkContext {
    // State snapshots
    var artboards: [Artboard]
    var selectedElementIDs: Set<UUID>
    var selectedElements: [CanvasElement]
    var selectedElement: CanvasElement?
    var activeArtboard: Artboard?
    var renderableElements: [CanvasElement]
    var latestDesignTokens: DesignTokenSet?
    var latestComponentSpecs: [ComponentSpec]
    var componentInstances: [ComponentInstance]
    var latestScope: ProductScopeSnapshot?
    var latestBlueprint: BuildBlueprint?

    // Action callbacks — the ViewModel implements these using its own internal methods.
    var onSetSelectedElements: (Set<UUID>, UUID?) -> Void
    var onDistributeHorizontally: () -> Void
    var onToggleConstraint: (ConstraintPin, Bool) -> Void
    var onResizeSelectedElements: (StudioViewModel.ResizeHandle, Double, Double) -> Void
    var onRotateSelectedElements: (Double) -> Void
    var onRunProEditingBenchmark: () -> Void

    /// Convenience initializer that snapshots a StudioViewModel and wires callbacks.
    @MainActor init(from vm: StudioViewModel) {
        artboards = vm.artboards; selectedElementIDs = vm.selectedElementIDs; selectedElements = vm.selectedElements
        selectedElement = vm.selectedElement; activeArtboard = vm.activeArtboard; renderableElements = vm.renderableElements
        latestDesignTokens = vm.latestDesignTokens; latestComponentSpecs = vm.latestComponentSpecs
        componentInstances = vm.componentInstances; latestScope = vm.latestScope; latestBlueprint = vm.latestBlueprint
        onSetSelectedElements = { [weak vm] ids, primary in vm?.setSelectedElements(ids, preferredPrimary: primary) }
        onDistributeHorizontally = { [weak vm] in vm?.distributeSelectedElementsHorizontally() }
        onToggleConstraint = { [weak vm] pin, enabled in vm?.toggleConstraint(pin, enabled: enabled) }
        onResizeSelectedElements = { [weak vm] handle, dx, dy in vm?.resizeSelectedElements(handle: handle, deltaX: dx, deltaY: dy) }
        onRotateSelectedElements = { [weak vm] degrees in vm?.rotateSelectedElements(by: degrees) }
        onRunProEditingBenchmark = { [weak vm] in vm?.runProEditingBenchmark() }
    }
}

@MainActor
final class BenchmarkService: ObservableObject {
    @Published var latestBenchmarkReport: BenchmarkRunReport?
    @Published var benchmarkHistory: [BenchmarkRunReport] = []

    // MARK: - Computed Properties

    var benchmarkStatusLine: String {
        guard let latestBenchmarkReport else { return "Benchmark not run yet." }
        let passCount = latestBenchmarkReport.steps.filter(\.passed).count
        let latency = latestBenchmarkReport.medianStepLatencyMilliseconds.map { " · median \(Int($0.rounded()))ms" } ?? ""
        return "\(latestBenchmarkReport.passed ? "Pass" : "Fail") · \(passCount)/\(latestBenchmarkReport.steps.count) steps\(latency)"
    }

    var benchmarkHistoryPreview: [BenchmarkRunReport] {
        Array(benchmarkHistory.suffix(Constants.Benchmark.historyPreviewCount).reversed())
    }

    var benchmarkTrendScore: BenchmarkTrendScore? {
        computeBenchmarkTrendScore(from: benchmarkHistory)
    }

    var benchmarkTrendPoints: [BenchmarkTrendPoint] {
        benchmarkTrendScore?.points ?? []
    }

    var benchmarkTrendStatusLine: String {
        guard let benchmarkTrendScore else {
            return "Run benchmark to build trend data."
        }
        let passRate = Int((benchmarkTrendScore.passRate * 100).rounded())
        let latency = benchmarkTrendScore.medianStepLatencyMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "n/a"
        return "Window \(benchmarkTrendScore.runCount) · pass-rate \(passRate)% · median latency \(latency)"
    }

    var benchmarkTrendDirectionLine: String {
        let points = benchmarkTrendPoints
        guard points.count >= 2 else { return "Trend: need at least 2 runs." }
        let first = points.first
        let last = points.last
        guard let first, let last else { return "Trend: unavailable." }

        let passRateDelta = last.passRate - first.passRate
        let firstLatency = first.medianStepLatencyMilliseconds
        let lastLatency = last.medianStepLatencyMilliseconds
        let latencyDelta = (lastLatency ?? 0) - (firstLatency ?? 0)

        if passRateDelta >= Constants.Benchmark.improvingPassRateDelta || (passRateDelta >= 0 && latencyDelta <= -Constants.Benchmark.latencyDeltaThreshold) {
            return "Trend: Improving"
        }
        if passRateDelta <= Constants.Benchmark.regressingPassRateDelta || latencyDelta >= Constants.Benchmark.latencyDeltaThreshold {
            return "Trend: Regressing"
        }
        return "Trend: Stable"
    }

    // MARK: - Public Methods

    func appendBenchmarkReport(_ report: BenchmarkRunReport) {
        latestBenchmarkReport = report
        benchmarkHistory.append(report)
        if benchmarkHistory.count > Constants.Benchmark.maxHistoryEntries {
            benchmarkHistory.removeFirst(benchmarkHistory.count - Constants.Benchmark.maxHistoryEntries)
        }
    }

    func benchmarkStep(title: String, action: () -> (passed: Bool, detail: String)) -> BenchmarkStepResult {
        let start = DispatchTime.now().uptimeNanoseconds
        let outcome = action()
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
        return BenchmarkStepResult(
            id: UUID(),
            title: title,
            passed: outcome.passed,
            detail: outcome.detail,
            latencyMilliseconds: elapsedMilliseconds
        )
    }

    func resetState() {
        latestBenchmarkReport = nil
        benchmarkHistory = []
    }

    // MARK: - Benchmark Run

    /// Runs the Pro Editing Core benchmark scenario.
    /// All editing side-effects are performed via callbacks on `context`; the snapshot
    /// restore happens in the ViewModel after the call returns.
    func runProEditingBenchmark(context: BenchmarkContext) {
        let renderableElements = context.renderableElements

        guard !renderableElements.isEmpty else {
            let report = BenchmarkRunReport(
                generatedAt: Date(),
                scenario: "Pro Editing Core",
                passed: false,
                steps: [
                    BenchmarkStepResult(
                        id: UUID(),
                        title: "Input",
                        passed: false,
                        detail: "No elements available. Load or generate a mockup first.",
                        latencyMilliseconds: 0
                    ),
                ]
            )
            appendBenchmarkReport(report)
            return
        }

        let candidates = renderableElements.filter { $0.kind != .imageRoot }
        let selection = Set(candidates.prefix(Constants.Benchmark.multiSelectCandidateCount).map(\.id))
        var results: [BenchmarkStepResult] = []

        results.append(
            benchmarkStep(title: "Multi-select") {
                let passed = !selection.isEmpty
                if passed {
                    context.onSetSelectedElements(selection, selection.first)
                }
                return (
                    passed,
                    passed
                        ? "Selected \(selection.count) elements for benchmark."
                        : "Not enough elements for selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Distribute") {
                let before = context.renderableElements
                    .filter { selection.contains($0.id) }
                    .map(\.frame.minX)
                    .sorted()
                context.onDistributeHorizontally()
                let after = context.renderableElements
                    .filter { selection.contains($0.id) }
                    .map(\.frame.minX)
                    .sorted()
                let passed = before != after && after.count >= 2
                return (
                    passed,
                    passed
                        ? "Horizontal distribution updated element positions."
                        : "Distribution did not change geometry."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Constraint Pins") {
                context.onToggleConstraint(.left, true)
                context.onToggleConstraint(.top, true)
                let passed = context.selectedElements.allSatisfy {
                    $0.constraints.contains(.left) && $0.constraints.contains(.top)
                }
                return (
                    passed,
                    passed
                        ? "Pinned left/top on selected elements."
                        : "Constraint pinning failed for selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Resize Handles") {
                let sizeBefore = context.selectedElements.map {
                    "\($0.id.uuidString):\($0.frame.width):\($0.frame.height)"
                }
                context.onResizeSelectedElements(.bottomRight, Constants.Benchmark.benchmarkResizeDelta, Constants.Benchmark.benchmarkResizeDelta)
                let sizeAfter = context.selectedElements.map {
                    "\($0.id.uuidString):\($0.frame.width):\($0.frame.height)"
                }
                let passed = sizeBefore != sizeAfter
                return (
                    passed,
                    passed
                        ? "Resize handle interaction updated selection bounds."
                        : "Resize did not affect selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Rotate Handles") {
                let rotationBefore = context.selectedElements.map(\.rotationDegrees)
                context.onRotateSelectedElements(Constants.Benchmark.benchmarkRotateDegrees)
                let rotationAfter = context.selectedElements.map(\.rotationDegrees)
                let passed = rotationBefore != rotationAfter
                return (
                    passed,
                    passed
                        ? "Rotation interaction updated element angles."
                        : "Rotation did not update selected elements."
                )
            }
        )

        let allPassed = results.allSatisfy(\.passed)
        let report = BenchmarkRunReport(
            generatedAt: Date(),
            scenario: "Pro Editing Core",
            passed: allPassed,
            steps: results
        )
        appendBenchmarkReport(report)
    }

    /// Applies a targeted fix for the first failing benchmark step, then re-runs the benchmark.
    /// `onArtboardUpdate` is provided so that any artboard mutations triggered by fix actions
    /// can be reflected back to the ViewModel's artboard array.
    func autoFixFailingBenchmarkStep(
        context: BenchmarkContext,
        onArtboardUpdate: (inout [Artboard]) -> Void
    ) {
        guard let report = latestBenchmarkReport,
              let failingStep = report.steps.first(where: { !$0.passed }) else {
            return
        }

        switch failingStep.title {
        case "Multi-select":
            let ids = Set(
                context.renderableElements
                    .filter { $0.kind != .imageRoot }
                    .prefix(Constants.Benchmark.multiSelectCandidateCount)
                    .map(\.id)
            )
            if !ids.isEmpty {
                context.onSetSelectedElements(ids, ids.first)
            }
        case "Distribute":
            context.onDistributeHorizontally()
        case "Constraint Pins":
            context.onToggleConstraint(.left, true)
            context.onToggleConstraint(.top, true)
        case "Resize Handles":
            context.onResizeSelectedElements(.bottomRight, Constants.Benchmark.benchmarkResizeDelta, Constants.Benchmark.benchmarkResizeDelta)
        case "Rotate Handles":
            context.onRotateSelectedElements(Constants.Benchmark.benchmarkRotateDegrees)
        default:
            break
        }

        // Re-run the full benchmark after applying the fix
        context.onRunProEditingBenchmark()
    }

    // MARK: - Private Methods

    private func computeBenchmarkTrendScore(from history: [BenchmarkRunReport], windowSize: Int = Constants.Benchmark.defaultTrendWindowSize) -> BenchmarkTrendScore? {
        let recentReports = Array(history.suffix(windowSize))
        guard !recentReports.isEmpty else { return nil }

        let points = recentReports.enumerated().map { index, report in
            BenchmarkTrendPoint(
                runID: "\(report.generatedAt.timeIntervalSince1970)-\(index)",
                generatedAt: report.generatedAt,
                passRate: report.stepPassRate,
                medianStepLatencyMilliseconds: report.medianStepLatencyMilliseconds,
                runPassed: report.passed
            )
        }

        let passRate = points.map(\.passRate).reduce(0, +) / Double(points.count)
        let allLatencies = recentReports.flatMap { report in
            report.steps.compactMap(\.latencyMilliseconds)
        }

        return BenchmarkTrendScore(
            generatedAt: recentReports.last?.generatedAt ?? Date(timeIntervalSince1970: 0),
            windowSize: windowSize,
            runCount: recentReports.count,
            passRate: passRate,
            medianStepLatencyMilliseconds: median(of: allLatencies),
            points: points
        )
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
