import Foundation
import AFCore

// MARK: - Serializable State

struct PersistedProject: Codable {
    var project: Project
    var nodes: [WorkflowNode]
    var connections: [NodeConnection]
    var nodeZOrder: [UUID]?
}

struct PersistedAppState: Codable {
    var projects: [PersistedProject]
    var activeProjectID: UUID?
}

// MARK: - Persistence Manager

@MainActor
public final class ProjectPersistence {
    private static var saveURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }

    private static var isSaving = false

    private static var knownProjectCount = 0

    public static func save(_ appState: AppState) {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let currentCount = appState.openProjects.count

        // Safety: never lose more than 1 project at a time (prevent accidental wipe)
        if currentCount < knownProjectCount && (knownProjectCount - currentCount) > 1 {
            return
        }

        knownProjectCount = currentCount

        let persisted = PersistedAppState(
            projects: appState.openProjects.map { state in
                // Sync canvas state into project model before saving
                var project = state.project
                project.canvasOffset = CanvasOffset(state.canvasState.offset)
                project.canvasZoom = state.canvasState.zoom

                return PersistedProject(
                    project: project,
                    nodes: Array(state.nodes.values),
                    connections: Array(state.connections.values),
                    nodeZOrder: state.nodeZOrder
                )
            },
            activeProjectID: appState.activeProjectID
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(persisted)

            // Backup before overwriting
            let backupURL = saveURL.deletingLastPathComponent().appendingPathComponent("projects.backup.json")
            if FileManager.default.fileExists(atPath: saveURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: saveURL, to: backupURL)
            }

            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }

    public static func load(into appState: AppState) {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }

        do {
            let data = try Data(contentsOf: saveURL)
            let persisted = try JSONDecoder().decode(PersistedAppState.self, from: data)

            appState.openProjects = persisted.projects.map { p in
                let state = ProjectState(project: p.project)
                state.canvasState.offset = p.project.canvasOffset.cgPoint
                state.canvasState.zoom = p.project.canvasZoom
                for node in p.nodes {
                    state.nodes[node.id] = node
                }
                for conn in p.connections {
                    state.connections[conn.id] = conn
                }
                state.nodeZOrder = p.nodeZOrder ?? Array(state.nodes.keys)
                return state
            }
            appState.activeProjectID = persisted.activeProjectID ?? appState.openProjects.first?.project.id
            knownProjectCount = appState.openProjects.count
            appState.wireOnChange()
        } catch {
            print("Failed to load projects: \(error)")
        }
    }
}
