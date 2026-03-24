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
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? accentColor.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 0.5
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
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

            // Fake input bar matching the bordered box style
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("Message...")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.quaternary)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            )
            .padding(10)
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

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                    Text("Enter command...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }
}
