import Foundation
import AFCore

@Observable
@MainActor
public final class AppState {
    public var openProjects: [ProjectState] = []
    public var activeProjectID: UUID?
    public var pendingApprovals: [ToolApprovalRequest] = []
    public var sidebarSelection: SidebarItem? = nil

    public init() {}

    public var hasProjects: Bool {
        !openProjects.isEmpty
    }

    public var activeProject: ProjectState? {
        openProjects.first { $0.project.id == activeProjectID }
    }

    @discardableResult
    public func createProject(name: String, rootPath: String) -> ProjectState {
        let state = ProjectState(project: Project(name: name, rootPath: rootPath))
        state.onChange = { [weak self] in self?.scheduleSave() }
        openProjects.append(state)
        activeProjectID = state.project.id
        scheduleSave()
        return state
    }

    public func wireOnChange() {
        for project in openProjects {
            project.onChange = { [weak self] in self?.scheduleSave() }
        }
    }

    public func deleteProject(_ id: UUID) {
        openProjects.removeAll { $0.project.id == id }
        if activeProjectID == id {
            activeProjectID = openProjects.first?.project.id
        }
        scheduleSave()
    }

    public func scheduleSave() {
        ProjectPersistence.save(self)
    }
}

public enum SidebarItem: Hashable, Sendable {
    case project(UUID)
    case sessions
    case settings
}
