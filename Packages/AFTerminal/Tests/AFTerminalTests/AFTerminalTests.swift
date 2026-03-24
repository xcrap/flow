import Foundation
import Testing
@testable import AFTerminal

private func sleepBriefly(_ milliseconds: UInt64) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

@Test @MainActor func sessionUsesProvidedDirectory() async throws {
    let session = TerminalSession(id: UUID(), currentDirectory: "/tmp/agentflow-terminal-test")
    #expect(session.currentDirectory == "/tmp/agentflow-terminal-test")
    #expect(session.launchDirectory == "/tmp/agentflow-terminal-test")
    #expect(session.isRunning == false)
}

@Test @MainActor func sessionDefaultsToStoppedShell() async throws {
    let session = TerminalSession(id: UUID())
    #expect(session.lastExitCode == nil)
    #expect(session.terminalTitle == nil)
}

@Test @MainActor func setLaunchDirectoryResetsStoppedSessionDirectory() async throws {
    let session = TerminalSession(id: UUID(), currentDirectory: "/tmp/original")
    session.setLaunchDirectory("/tmp/project-root")
    #expect(session.launchDirectory == "/tmp/project-root")
    #expect(session.currentDirectory == "/tmp/project-root")
}

@Test @MainActor func terminalDoesNotPersistTranscript() async throws {
    let session = TerminalSession(id: UUID(), currentDirectory: "/tmp/project-root")
    session.setPersistedTranscript("line 1\nline 2")
    #expect(session.snapshotTranscript() == nil)
}

@Test @MainActor func restartCreatesFreshTerminalSurface() async throws {
    let session = TerminalSession(id: UUID(), currentDirectory: "/tmp/project-root")
    let originalIdentity = session.viewIdentity
    _ = session.makeView()
    session.restart()
    #expect(session.viewIdentity != originalIdentity)
    #expect(session.isRunning == false)
    #expect(session.currentDirectory == "/tmp/project-root")
}

@Test @MainActor func shellExitUpdatesSessionState() async throws {
    let session = TerminalSession(
        id: UUID(),
        currentDirectory: "/tmp/project-root",
        shellPath: "/bin/sh"
    )
    let view = session.makeView()
    session.startIfNeeded()
    await sleepBriefly(150)
    #expect(session.isRunning == true)
    view.process.send(data: Array("exit\n".utf8)[...])
    await sleepBriefly(250)
    #expect(session.isRunning == false)
    #expect(session.lastExitCode == 0)
}

@Test @MainActor func startTriggersChangeNotification() async throws {
    let session = TerminalSession(
        id: UUID(),
        currentDirectory: "/tmp/project-root",
        shellPath: "/bin/sh"
    )
    var changeCount = 0
    session.onChange = {
        changeCount += 1
    }
    _ = session.makeView()
    session.startIfNeeded()
    await sleepBriefly(150)
    #expect(changeCount > 0)
}
