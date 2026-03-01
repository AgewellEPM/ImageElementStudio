import XCTest
@testable import ImageElementStudio

@MainActor
final class BenchmarkServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> BenchmarkService {
        BenchmarkService()
    }

    private func makeReport(
        passed: Bool = true,
        stepCount: Int = 5,
        failCount: Int = 0,
        latencies: [Double]? = nil
    ) -> BenchmarkRunReport {
        let steps = (0..<stepCount).map { i in
            BenchmarkStepResult(
                id: UUID(),
                title: "Step \(i)",
                passed: i >= failCount,
                detail: "Detail \(i)",
                latencyMilliseconds: latencies?[safe: i] ?? Double(10 + i * 5)
            )
        }
        return BenchmarkRunReport(
            generatedAt: Date(timeIntervalSince1970: Double(100 + stepCount)),
            scenario: "Pro Editing Core",
            passed: passed,
            steps: steps
        )
    }

    // MARK: - benchmarkStatusLine

    func testBenchmarkStatusLineWhenNoReport() {
        let service = makeService()
        XCTAssertEqual(service.benchmarkStatusLine, "Benchmark not run yet.")
    }

    func testBenchmarkStatusLineWithPassingReport() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))

        let line = service.benchmarkStatusLine
        XCTAssertTrue(line.hasPrefix("Pass"))
        XCTAssertTrue(line.contains("5/5 steps"))
    }

    func testBenchmarkStatusLineWithFailingReport() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: false, stepCount: 5, failCount: 2))

        let line = service.benchmarkStatusLine
        XCTAssertTrue(line.hasPrefix("Fail"))
        XCTAssertTrue(line.contains("3/5 steps"))
    }

    func testBenchmarkStatusLineIncludesMedianLatency() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(
            passed: true, stepCount: 3, failCount: 0,
            latencies: [10, 20, 30]
        ))

        let line = service.benchmarkStatusLine
        // Median of [10, 20, 30] = 20
        XCTAssertTrue(line.contains("20ms"))
    }

    // MARK: - benchmarkHistoryPreview

    func testBenchmarkHistoryPreviewLimitsToSix() {
        let service = makeService()
        for i in 0..<10 {
            service.appendBenchmarkReport(makeReport(passed: true, stepCount: i + 1))
        }

        let preview = service.benchmarkHistoryPreview
        XCTAssertEqual(preview.count, 6)
    }

    func testBenchmarkHistoryPreviewIsReversed() {
        let service = makeService()
        for _ in 0..<3 {
            service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5))
        }

        let preview = service.benchmarkHistoryPreview
        // The most recent report should be first in preview
        XCTAssertEqual(preview.count, 3)
        XCTAssertTrue(preview.first!.generatedAt >= preview.last!.generatedAt)
    }

    func testBenchmarkHistoryPreviewReturnsAllWhenFewerThanSix() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true))
        service.appendBenchmarkReport(makeReport(passed: false))

        XCTAssertEqual(service.benchmarkHistoryPreview.count, 2)
    }

    // MARK: - benchmarkTrendScore

    func testBenchmarkTrendScoreNilWhenNoHistory() {
        let service = makeService()
        XCTAssertNil(service.benchmarkTrendScore)
    }

    func testBenchmarkTrendScoreComputesPassRate() {
        let service = makeService()
        // 3 reports with stepPassRate 1.0, 0.6, 0.8 -> avg 0.8
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))
        service.appendBenchmarkReport(makeReport(passed: false, stepCount: 5, failCount: 2))
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 1))

        let trend = service.benchmarkTrendScore
        XCTAssertNotNil(trend)
        XCTAssertEqual(trend?.runCount, 3)
        // Average of (5/5=1.0) + (3/5=0.6) + (4/5=0.8) = 2.4/3 = 0.8
        XCTAssertEqual(trend?.passRate ?? 0, 0.8, accuracy: 0.01)
    }

    func testBenchmarkTrendScoreWindowSizeDefault() {
        let service = makeService()
        for _ in 0..<15 {
            service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5))
        }

        let trend = service.benchmarkTrendScore
        // Window size is 12 by default, so only last 12 are considered
        XCTAssertEqual(trend?.runCount, 12)
    }

    // MARK: - benchmarkTrendPoints

    func testBenchmarkTrendPointsEmptyWhenNoHistory() {
        let service = makeService()
        XCTAssertTrue(service.benchmarkTrendPoints.isEmpty)
    }

    func testBenchmarkTrendPointsMatchesRunCount() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5))
        service.appendBenchmarkReport(makeReport(passed: false, stepCount: 5, failCount: 2))

        let points = service.benchmarkTrendPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].passRate, 1.0)
        XCTAssertEqual(points[1].passRate, 0.6)
    }

    // MARK: - benchmarkTrendStatusLine

    func testBenchmarkTrendStatusLineWhenNoTrend() {
        let service = makeService()
        XCTAssertEqual(service.benchmarkTrendStatusLine, "Run benchmark to build trend data.")
    }

    func testBenchmarkTrendStatusLineFormatsCorrectly() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))

        let line = service.benchmarkTrendStatusLine
        XCTAssertTrue(line.contains("Window 1"))
        XCTAssertTrue(line.contains("pass-rate 100%"))
        XCTAssertTrue(line.contains("median latency"))
    }

    // MARK: - benchmarkTrendDirectionLine

    func testBenchmarkTrendDirectionLineNeedsTwoRuns() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5))

        XCTAssertEqual(service.benchmarkTrendDirectionLine, "Trend: need at least 2 runs.")
    }

    func testBenchmarkTrendDirectionLineShowsImproving() {
        let service = makeService()
        // First report: low pass rate
        service.appendBenchmarkReport(makeReport(passed: false, stepCount: 5, failCount: 4))
        // Second report: high pass rate (big improvement)
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))

        XCTAssertEqual(service.benchmarkTrendDirectionLine, "Trend: Improving")
    }

    func testBenchmarkTrendDirectionLineShowsRegressing() {
        let service = makeService()
        // First report: high pass rate
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))
        // Second report: low pass rate (big regression)
        service.appendBenchmarkReport(makeReport(passed: false, stepCount: 5, failCount: 4))

        XCTAssertEqual(service.benchmarkTrendDirectionLine, "Trend: Regressing")
    }

    func testBenchmarkTrendDirectionLineShowsStable() {
        let service = makeService()
        // Two similar reports
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))
        service.appendBenchmarkReport(makeReport(passed: true, stepCount: 5, failCount: 0))

        XCTAssertEqual(service.benchmarkTrendDirectionLine, "Trend: Stable")
    }

    // MARK: - appendBenchmarkReport

    func testAppendBenchmarkReportSetsLatestReport() {
        let service = makeService()
        let report = makeReport(passed: true)

        service.appendBenchmarkReport(report)

        XCTAssertEqual(service.latestBenchmarkReport, report)
    }

    func testAppendBenchmarkReportAddsToHistory() {
        let service = makeService()

        service.appendBenchmarkReport(makeReport(passed: true))
        service.appendBenchmarkReport(makeReport(passed: false))

        XCTAssertEqual(service.benchmarkHistory.count, 2)
    }

    func testAppendBenchmarkReportCapsHistoryAt40() {
        let service = makeService()
        for _ in 0..<50 {
            service.appendBenchmarkReport(makeReport(passed: true))
        }

        XCTAssertEqual(service.benchmarkHistory.count, 40)
    }

    // MARK: - resetState

    func testResetStateClearsAll() {
        let service = makeService()
        service.appendBenchmarkReport(makeReport(passed: true))

        service.resetState()

        XCTAssertNil(service.latestBenchmarkReport)
        XCTAssertTrue(service.benchmarkHistory.isEmpty)
    }

    // MARK: - benchmarkStep

    func testBenchmarkStepCapturesPassedResult() {
        let service = makeService()

        let result = service.benchmarkStep(title: "Test Step") {
            (passed: true, detail: "All good")
        }

        XCTAssertEqual(result.title, "Test Step")
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.detail, "All good")
        XCTAssertNotNil(result.latencyMilliseconds)
    }

    func testBenchmarkStepCapturesFailedResult() {
        let service = makeService()

        let result = service.benchmarkStep(title: "Failing Step") {
            (passed: false, detail: "Something went wrong")
        }

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.detail, "Something went wrong")
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
