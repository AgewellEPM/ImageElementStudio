import Foundation

struct BenchmarkStepResult: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var passed: Bool
    var detail: String
    var latencyMilliseconds: Double? = nil
}

struct BenchmarkRunReport: Codable, Hashable {
    var generatedAt: Date
    var scenario: String
    var passed: Bool
    var steps: [BenchmarkStepResult]

    var stepPassRate: Double {
        guard !steps.isEmpty else { return 0 }
        let passCount = steps.filter(\.passed).count
        return Double(passCount) / Double(steps.count)
    }

    var medianStepLatencyMilliseconds: Double? {
        let latencies = steps.compactMap(\.latencyMilliseconds)
        guard !latencies.isEmpty else { return nil }
        let sorted = latencies.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct BenchmarkTrendPoint: Codable, Hashable, Identifiable {
    var runID: String
    var generatedAt: Date
    var passRate: Double
    var medianStepLatencyMilliseconds: Double?
    var runPassed: Bool

    var id: String { runID }
}

struct BenchmarkTrendScore: Codable, Hashable {
    var generatedAt: Date
    var windowSize: Int
    var runCount: Int
    var passRate: Double
    var medianStepLatencyMilliseconds: Double?
    var points: [BenchmarkTrendPoint]
}

struct BenchmarkTrendArtifact: Codable, Hashable {
    var generatedAt: Date
    var projectName: String
    var projectID: String
    var target: String
    var deterministicHash: String
    var latestBenchmarkReport: BenchmarkRunReport?
    var trendScore: BenchmarkTrendScore?
    var history: [BenchmarkRunReport]
}
