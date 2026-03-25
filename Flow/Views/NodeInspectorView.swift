import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct NodeInspectorView: View {
    @Bindable var projectState: ProjectState
    var conversations: [UUID: ConversationState]
    var onSendMessage: (UUID, String, [Attachment]) -> Void

    private var selectedNode: WorkflowNode? {
        guard let id = projectState.selectedNodeIDs.first else { return nil }
        return projectState.nodes[id]
    }

    var body: some View {
        Group {
            if let node = selectedNode {
                if node.kind == .agent {
                    agentPanel(node)
                } else {
                    nodeDetail(node)
                }
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "cursorarrow.click.2")
                } description: {
                    Text("Select a node on the canvas to inspect it.")
                }
            }
        }
    }

    @ViewBuilder
    private func agentPanel(_ node: WorkflowNode) -> some View {
        let conversation = conversations[node.id] ?? ConversationState(nodeID: node.id)

        VStack(spacing: 0) {
            ConversationView(
                conversationState: conversation,
                node: node,
                onSend: { text, attachments in
                    onSendMessage(node.id, text, attachments)
                }
            )
        }
    }

    @ViewBuilder
    private func nodeDetail(_ node: WorkflowNode) -> some View {
        Form {
            Section("Node") {
                LabeledContent("Type") {
                    Label(node.kind.rawValue, systemImage: node.iconName)
                }

                TextField("Title", text: Binding(
                    get: { projectState.nodes[node.id]?.title ?? "" },
                    set: { projectState.nodes[node.id]?.title = $0 }
                ))

                LabeledContent("Position") {
                    Text("(\(Int(node.position.x)), \(Int(node.position.y)))")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Status") {
                    Text(node.executionState.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete Node", role: .destructive) {
                    projectState.removeNode(node.id)
                }
            }
        }
        .formStyle(.grouped)
    }
}
