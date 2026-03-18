import AppKit
import SwiftUI

/// Shows generated Swift/SwiftUI code for the selected artboard.
/// Files come from `CodeGenerationPipeline.generatedFiles`.
struct ArtboardCodeViewer: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var selectedFileIndex: Int = 0

    private var files: [GeneratedFileEntry] {
        viewModel.codeGenerationPipeline.generatedFiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if files.isEmpty {
                emptyState
            } else {
                filePickerBar
                codeContent
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "curlybraces")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No Generated Code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Generate an app to see the SwiftUI code for each view here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - File Picker

    @ViewBuilder
    private var filePickerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)

            if files.count == 1 {
                Text(files[0].name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            } else {
                Picker("File", selection: $selectedFileIndex) {
                    ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                        Text(file.name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Spacer()

            Text("\(currentFile?.content.components(separatedBy: "\n").count ?? 0) lines")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Button {
                copyCurrentFileToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy code to clipboard")
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Code Content

    @ViewBuilder
    private var codeContent: some View {
        if let file = currentFile {
            ScrollView([.horizontal, .vertical]) {
                Text(attributedCode(file.content))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(hex: "#1A1D23", fallback: Color(nsColor: .textBackgroundColor)).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private var currentFile: GeneratedFileEntry? {
        guard selectedFileIndex >= 0, selectedFileIndex < files.count else {
            return files.first
        }
        return files[selectedFileIndex]
    }

    private func copyCurrentFileToClipboard() {
        guard let file = currentFile else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.content, forType: .string)
    }

    /// Simple keyword highlighting for Swift code.
    private func attributedCode(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        result.foregroundColor = Color(hex: "#D4D4D4", fallback: .white)

        let keywords: Set<String> = [
            "import", "struct", "class", "enum", "func", "var", "let", "if", "else",
            "guard", "return", "switch", "case", "for", "in", "while", "do", "try",
            "catch", "throw", "throws", "async", "await", "some", "any", "@State",
            "@Binding", "@ObservedObject", "@Published", "@Environment", "@MainActor",
            "private", "public", "internal", "fileprivate", "static", "final",
            "override", "mutating", "protocol", "extension", "typealias", "where",
            "self", "Self", "true", "false", "nil", "init", "deinit", "super",
            "@StateObject", "@EnvironmentObject", "@ViewBuilder",
        ]

        let typeKeywords: Set<String> = [
            "View", "Body", "Text", "VStack", "HStack", "ZStack", "Button", "Image",
            "NavigationView", "List", "ForEach", "Color", "Font", "CGFloat", "String",
            "Int", "Double", "Bool", "UUID", "Date", "URL", "Optional", "Array",
            "GeometryReader", "ScrollView", "LazyVStack", "LazyHStack", "Spacer",
            "Divider", "Group", "Section", "NavigationLink", "TabView",
        ]

        let lines = source.components(separatedBy: "\n")
        var charOffset = 0

        for line in lines {
            // Highlight comments
            if let commentRange = line.range(of: "//") {
                let commentStart = charOffset + line.distance(from: line.startIndex, to: commentRange.lowerBound)
                let commentLength = line.distance(from: commentRange.lowerBound, to: line.endIndex)
                if let attrRange = attributedRange(in: result, start: commentStart, length: commentLength) {
                    result[attrRange].foregroundColor = Color(hex: "#6A9955", fallback: .green)
                }
            }

            // Highlight strings
            var inString = false
            var stringStart = 0
            for (i, char) in line.enumerated() {
                if char == "\"" {
                    if inString {
                        let length = i - stringStart + 1
                        if let attrRange = attributedRange(in: result, start: charOffset + stringStart, length: length) {
                            result[attrRange].foregroundColor = Color(hex: "#CE9178", fallback: .orange)
                        }
                        inString = false
                    } else {
                        stringStart = i
                        inString = true
                    }
                }
            }

            // Highlight keywords
            let tokens = line.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@_")).inverted)
            var searchStart = line.startIndex
            for token in tokens where !token.isEmpty {
                guard let tokenRange = line.range(of: token, range: searchStart..<line.endIndex) else { continue }
                searchStart = tokenRange.upperBound

                let tokenStart = charOffset + line.distance(from: line.startIndex, to: tokenRange.lowerBound)

                if keywords.contains(token) {
                    if let attrRange = attributedRange(in: result, start: tokenStart, length: token.count) {
                        result[attrRange].foregroundColor = Color(hex: "#569CD6", fallback: .blue)
                    }
                } else if typeKeywords.contains(token) {
                    if let attrRange = attributedRange(in: result, start: tokenStart, length: token.count) {
                        result[attrRange].foregroundColor = Color(hex: "#4EC9B0", fallback: .teal)
                    }
                }
            }

            charOffset += line.count + 1 // +1 for newline
        }

        return result
    }

    private func attributedRange(in str: AttributedString, start: Int, length: Int) -> Range<AttributedString.Index>? {
        let chars = str.characters
        guard start >= 0, start + length <= chars.count else { return nil }
        let startIdx = chars.index(chars.startIndex, offsetBy: start)
        let endIdx = chars.index(startIdx, offsetBy: length)
        return startIdx..<endIdx
    }
}
