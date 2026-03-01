import SwiftUI

struct ReviewPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Review") {
            VStack(alignment: .leading, spacing: 8) {
                Picker(
                    "Approval",
                    selection: Binding(
                        get: { viewModel.reviewApprovalState },
                        set: { viewModel.setReviewApprovalState($0) }
                    )
                ) {
                    ForEach(ReviewApprovalState.allCases) { state in
                        Text(state.rawValue.capitalized).tag(state)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField("Add review comment...", text: $viewModel.reviewCommentDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Add") {
                        viewModel.addReviewComment(viewModel.reviewCommentDraft)
                    }
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    TextField("Assignee (optional)", text: $viewModel.reviewCommentAssigneeDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)

                    Toggle("Due", isOn: $viewModel.reviewCommentHasDueDate)
                        .toggleStyle(.switch)
                        .font(.caption2)
                        .frame(width: 76, alignment: .leading)

                    if viewModel.reviewCommentHasDueDate {
                        DatePicker(
                            "",
                            selection: $viewModel.reviewCommentDueDateDraft,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                Text(viewModel.reviewGateStatusLine)
                    .font(.caption2)
                    .foregroundStyle(viewModel.canExportBuildArtifacts ? .green : .orange)

                Text(
                    "Comments: \(viewModel.unresolvedReviewCommentCount) open \u{00B7} " +
                        "\(viewModel.resolvedReviewCommentCount) resolved \u{00B7} " +
                        "\(viewModel.overdueReviewCommentCount) overdue"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Resolve All") {
                        viewModel.resolveAllReviewComments()
                    }
                    .controlSize(.small)
                    .disabled(viewModel.unresolvedReviewCommentCount == 0)

                    Button("Clear Resolved") {
                        viewModel.clearResolvedReviewComments()
                    }
                    .controlSize(.small)
                    .disabled(viewModel.resolvedReviewCommentCount == 0)
                }

                if viewModel.reviewCommentsPreview.isEmpty {
                    Text("No review comments yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.reviewCommentsPreview.prefix(5))) { comment in
                        ReviewCommentRow(viewModel: viewModel, comment: comment)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReviewCommentRow: View {
    @ObservedObject var viewModel: StudioViewModel
    let comment: DesignReviewComment

    var body: some View {
        let overdue = viewModel.isReviewCommentOverdue(comment)
        let assignee = (comment.assignee?.isEmpty == false) ? (comment.assignee ?? "Unassigned") : "Unassigned"
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(comment.author) \u{00B7} \(comment.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(comment.resolved ? "Reopen" : "Resolve") {
                    viewModel.toggleReviewCommentResolution(comment.id)
                }
                .controlSize(.mini)
                Button("Delete", role: .destructive) {
                    viewModel.deleteReviewComment(comment.id)
                }
                .controlSize(.mini)
            }

            HStack {
                Text("Assignee: \(assignee)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\u{00B7} \(viewModel.reviewCommentDueDateLine(comment))")
                    .font(.caption2)
                    .foregroundStyle(overdue ? .red : .secondary)
                if overdue {
                    Text("OVERDUE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Text(comment.message)
                .font(.caption)
                .foregroundStyle(comment.resolved ? .secondary : .primary)
                .strikethrough(comment.resolved, color: .secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(overdue ? Color.red.opacity(0.1) : Color.secondary.opacity(0.08))
        )
    }
}
