import SwiftUI
import AFCore

struct NodeView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let zoom: Double

    private var accentColor: Color {
        switch node.kind {
        case .agent: .purple
        case .terminal: .blue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (this is the drag handle)
            titleBar
                .accessibilityAddTraits(.isHeader)

            Divider()

            // Content area — placeholder, real content injected by CanvasNodeLayer
            contentPlaceholder
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.08), radius: isSelected ? 8 : 4, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Image(systemName: node.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            Text(node.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            if node.kind == .agent {
                Text(node.configuration.modelID ?? "sonnet")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var statusColor: Color {
        switch node.executionState {
        case .idle: .gray.opacity(0.4)
        case .running: .blue
        case .success: .green
        case .failure: .red
        case .waitingForApproval: .orange
        }
    }

    // MARK: - Content Placeholder

    @ViewBuilder
    private var contentPlaceholder: some View {
        switch node.kind {
        case .agent:
            agentPlaceholder
        case .terminal:
            terminalPlaceholder
        }
    }

    private var agentPlaceholder: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("Select to chat")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Fake input bar
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 32)
                    .overlay(alignment: .leading) {
                        Text("Message...")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                            .padding(.leading, 10)
                    }

                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
            }
            .padding(12)
        }
    }

    private var terminalPlaceholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("~ ")
                            .foregroundStyle(.green.opacity(0.5))
                        Text("$")
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .font(.system(size: 12, design: .monospaced))

            Divider()

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.6))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 26)
                    .overlay(alignment: .leading) {
                        Text("Enter command...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.leading, 8)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.02))
        }
    }
}
