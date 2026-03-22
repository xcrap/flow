import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("AgentFlow")
                .font(.largeTitle.weight(.semibold))

            Text("Create and orchestrate AI agent projects visually")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Select a project from the sidebar or create a new one to get started.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
