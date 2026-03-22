import Foundation
import AFCore
import AFAgent

struct PersistedConversation: Codable {
    var nodeID: UUID
    var sessionID: String?
    var messages: [ConversationMessage]
    var totalInputTokens: Int
    var totalOutputTokens: Int
}

struct PersistedConversations: Codable {
    var conversations: [PersistedConversation]
}

@MainActor
enum ConversationPersistence {
    private static var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentFlow/conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for projectID: UUID) -> URL {
        baseDir.appendingPathComponent("\(projectID.uuidString).json")
    }

    static func save(conversations: [UUID: ConversationState], for projectID: UUID) {
        let persisted = PersistedConversations(
            conversations: conversations.map { (nodeID, state) in
                PersistedConversation(
                    nodeID: nodeID,
                    sessionID: state.sessionID,
                    messages: state.messages,
                    totalInputTokens: state.totalInputTokens,
                    totalOutputTokens: state.totalOutputTokens
                )
            }
        )

        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: fileURL(for: projectID), options: .atomic)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    static func load(for projectID: UUID) -> [UUID: ConversationState] {
        let url = fileURL(for: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            let persisted = try JSONDecoder().decode(PersistedConversations.self, from: data)

            var result: [UUID: ConversationState] = [:]
            for conv in persisted.conversations {
                let state = ConversationState(nodeID: conv.nodeID)
                state.sessionID = conv.sessionID
                state.messages = conv.messages
                state.totalInputTokens = conv.totalInputTokens
                state.totalOutputTokens = conv.totalOutputTokens
                result[conv.nodeID] = state
            }
            return result
        } catch {
            print("Failed to load conversations: \(error)")
            return [:]
        }
    }

    static func delete(for projectID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: projectID))
    }
}
