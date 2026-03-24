import Foundation

@Observable
@MainActor
final class GitStatusService {
    struct GitInfo: Equatable {
        var branch: String = ""
        var additions: Int = 0
        var deletions: Int = 0
        var filesChanged: Int = 0
        var hasChanges: Bool { additions > 0 || deletions > 0 }
    }

    private(set) var info: [UUID: GitInfo] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    func startPolling(projectID: UUID, rootPath: String) {
        guard pollingTasks[projectID] == nil else { return }
        pollingTasks[projectID] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(projectID: projectID, rootPath: rootPath)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling(projectID: UUID) {
        pollingTasks[projectID]?.cancel()
        pollingTasks.removeValue(forKey: projectID)
    }

    func stopAll() {
        for (_, task) in pollingTasks { task.cancel() }
        pollingTasks.removeAll()
    }

    private func refresh(projectID: UUID, rootPath: String) async {
        let branch = await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let diffStat = await runGit(["diff", "--shortstat"], in: rootPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var gitInfo = GitInfo()
        gitInfo.branch = branch.isEmpty ? "" : branch

        // Parse "3 files changed, 42 insertions(+), 7 deletions(-)"
        if !diffStat.isEmpty {
            let parts = diffStat.components(separatedBy: ",")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("file") {
                    gitInfo.filesChanged = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                } else if trimmed.contains("insertion") {
                    gitInfo.additions = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                } else if trimmed.contains("deletion") {
                    gitInfo.deletions = Int(trimmed.components(separatedBy: " ").first ?? "") ?? 0
                }
            }
        }

        info[projectID] = gitInfo
    }

    private func runGit(_ args: [String], in directory: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
