#!/usr/bin/env python3

import re

file_path = "Sources/ImageElementStudio/StudioViewModel.swift"

with open(file_path, 'r') as f:
    content = f.read()

# Helper function to find and remove a complete method
def remove_method(content, method_signature):
    """Remove a method by finding its signature and matching braces"""
    start_pattern = re.escape(method_signature)
    start_match = re.search(start_pattern, content)

    if not start_match:
        print(f"WARNING: Could not find method: {method_signature}")
        return content

    start_idx = start_match.start()
    # Go back to start of line
    while start_idx > 0 and content[start_idx - 1] != '\n':
        start_idx -= 1

    # Find opening brace
    brace_idx = content.find('{', start_match.end())
    if brace_idx == -1:
        print(f"ERROR: Could not find opening brace for {method_signature}")
        return content

    # Count braces to find end
    brace_count = 1
    end_idx = brace_idx + 1
    while end_idx < len(content) and brace_count > 0:
        if content[end_idx] == '{':
            brace_count += 1
        elif content[end_idx] == '}':
            brace_count -= 1
        end_idx += 1

    # Move to end of line
    while end_idx < len(content) and content[end_idx] != '\n':
        end_idx += 1
    if end_idx < len(content):
        end_idx += 1  # Include the newline

    # Also consume one more newline if present (to remove blank line)
    if end_idx < len(content) and content[end_idx] == '\n':
        end_idx += 1

    print(f"Removing {method_signature} from {start_idx} to {end_idx}")
    return content[:start_idx] + content[end_idx:]

# Remove the old methods
methods_to_remove = [
    "private func assistantReply(for prompt: String) -> String",
    "private func runBuilderBuildCommand()",
    "private func runBuilderAnalyzeCommand()",
    "private func builderStatusSummary() -> String",
    "private static func initialMessages(for projectName: String) -> [ChatMessage]",
    "private static func initialBuilderMessages(for projectName: String) -> [ChatMessage]"
]

for method in methods_to_remove:
    content = remove_method(content, method)

# Write back
with open(file_path, 'w') as f:
    f.write(content)

print("\nAll old chat methods removed successfully")
