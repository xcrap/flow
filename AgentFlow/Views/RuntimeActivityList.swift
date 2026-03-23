import SwiftUI
import AFAgent

struct RuntimeActivityList: View {
    let activities: [ConversationRuntimeActivity]

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Runtime", systemImage: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(activities.reversed())) { activity in
                        RuntimeActivityRow(activity: activity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
            )
        }
    }
}

private struct RuntimeActivityRow: View {
    let activity: ConversationRuntimeActivity

    private var toneColor: Color {
        switch activity.tone {
        case .info:
            Color.white.opacity(0.62)
        case .working:
            Color(red: 0.93, green: 0.58, blue: 0.18)
        case .success:
            Color(red: 0.30, green: 0.78, blue: 0.47)
        case .warning:
            Color.orange
        case .error:
            Color.red
        }
    }

    private var iconName: String {
        switch activity.kind {
        case .session:
            "dot.radiowaves.left.and.right"
        case .queue:
            "hourglass.bottomhalf.filled"
        case .tool:
            "hammer"
        case .contextCompaction:
            "rectangle.compress.vertical"
        case .error:
            "exclamationmark.triangle.fill"
        case .note:
            "info.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(toneColor)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(activity.summary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let state = activity.state, !state.isEmpty {
                        Text(stateLabel(for: state))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(toneColor)
                    }
                }

                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stateLabel(for rawState: String) -> String {
        rawState
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
