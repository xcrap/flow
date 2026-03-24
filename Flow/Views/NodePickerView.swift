import SwiftUI
import AFCore

struct NodePickerView: View {
    var onPick: (NodeKind, String) -> Void

    private let nodeTypes: [(NodeKind, String, String, Color, String)] = [
        (.agent, "AI Agent", "brain", .purple, "Chat with Claude or OpenAI"),
        (.terminal, "Terminal", "terminal", .blue, "Run commands and scripts"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add Node")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(nodeTypes, id: \.0) { kind, title, icon, color, description in
                Button {
                    onPick(kind, title)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 13, weight: .medium))
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: icon)
                            .foregroundStyle(color)
                            .frame(width: 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240)
    }
}
