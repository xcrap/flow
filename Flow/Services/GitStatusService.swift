import Foundation

@Observable
@MainActor
final class GitStatusService {
    struct FileStatus: Equatable, Identifiable {
        var id: String { path }
        var path: String
        var status: String      // "M", "A", "D", "??" etc.
        var isUntracked: Bool { status == "??" }
    }

    struct GitInfo: Equatable {
        var isGitRepo: Bool = false
        var branch: String = ""
        var additions: Int = 0
        var deletions: Int = 0
        var filesChanged: Int = 0
        var statusFileCount: Int = 0
        var files: [FileStatus] = []
        var hasChanges: Bool { statusFileCount > 0 }
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

    /// Tracks root paths so commit/push/forceRefresh can work by project ID.
    private var rootPaths: [UUID: String] = [:]

    func forceRefresh(projectID: UUID) {
        guard let rootPath = rootPaths[projectID] else { return }
        Task { await refresh(projectID: projectID, rootPath: rootPath) }
    }

    func commit(projectID: UUID, message: String, includeUntracked: Bool) async -> Bool {
        guard let rootPath = rootPaths[projectID] else { return false }
        if includeUntracked {
            _ = await runGit(["add", "-A"], in: rootPath)
        } else {
            // Only stage tracked (modified/deleted) files, skip untracked
            _ = await runGit(["add", "-u"], in: rootPath)
        }
        let commitResult = await runGitWithStatus(["commit", "-m", message], in: rootPath)
        guard commitResult else { return false }
        await refresh(projectID: projectID, rootPath: rootPath)
        return true
    }

    func push(projectID: UUID) async -> Bool {
        guard let rootPath = rootPaths[projectID] else { return false }
        let result = await runGitWithStatus(["push"], in: rootPath)
        await refresh(projectID: projectID, rootPath: rootPath)
        return result
    }

    private func refresh(projectID: UUID, rootPath: String) async {
        rootPaths[projectID] = rootPath

        let gitDir = await runGit(["rev-parse", "--git-dir"], in: rootPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var gitInfo = GitInfo()
        gitInfo.isGitRepo = !gitDir.isEmpty

        guard gitInfo.isGitRepo else {
            info[projectID] = gitInfo
            return
        }

        let branch = await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        gitInfo.branch = branch

        let diffStat = await runGit(["diff", "--shortstat"], in: rootPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

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

        // Parse all changed/untracked files
        let status = await runGit(["status", "--porcelain"], in: rootPath)
        let lines = status.components(separatedBy: "\n").filter { !$0.isEmpty }
        gitInfo.files = lines.map { line in
            let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(line.dropFirst(3))
            return FileStatus(path: path, status: code.isEmpty ? "?" : code)
        }
        gitInfo.statusFileCount = lines.count

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

    private func runGitWithStatus(_ args: [String], in directory: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
