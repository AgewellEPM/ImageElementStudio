import SwiftUI

struct TokenSwatch: View {
    let hex: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: hex, fallback: .blue))
                .frame(width: 28, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TokenHexEditorRow: View {
    let title: String
    let value: String
    let onChange: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            TextField("#RRGGBB", text: $draft)
                .font(.caption.monospaced())
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    draft = value
                }
                .onChange(of: value) { _, newValue in
                    draft = newValue
                }
                .onChange(of: draft) { _, newValue in
                    if let normalized = normalizedHex(newValue) {
                        onChange(normalized)
                    }
                }
        }
    }

    private func normalizedHex(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(cleaned)"
    }
}

struct BenchmarkPassRateChart: View {
    let points: [BenchmarkTrendPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(points.suffix(16)) { point in
                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(point.runPassed ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
                        .frame(height: max(4, CGFloat(point.passRate) * 32))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityLabel("Benchmark pass-rate chart")
    }
}

extension Color {
    init(hex: String, fallback: Color) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6, let intValue = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
