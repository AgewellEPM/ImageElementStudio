import Foundation

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
        Array(benchmarkHistory.suffix(6).reversed())
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

        if passRateDelta >= 0.08 || (passRateDelta >= 0 && latencyDelta <= -10) {
            return "Trend: Improving"
        }
        if passRateDelta <= -0.08 || latencyDelta >= 10 {
            return "Trend: Regressing"
        }
        return "Trend: Stable"
    }

    // MARK: - Public Methods

    func appendBenchmarkReport(_ report: BenchmarkRunReport) {
        latestBenchmarkReport = report
        benchmarkHistory.append(report)
        if benchmarkHistory.count > 40 {
            benchmarkHistory.removeFirst(benchmarkHistory.count - 40)
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

    // MARK: - Private Methods

    private func computeBenchmarkTrendScore(from history: [BenchmarkRunReport], windowSize: Int = 12) -> BenchmarkTrendScore? {
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
