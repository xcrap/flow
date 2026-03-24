import Foundation
import AFCore
import AFAgent
import AFTerminal

// MARK: - Conversation Persistence

struct PersistedConversation: Codable {
    var nodeID: UUID
    var sessionID: String?
    var messages: [ConversationMessage]
    var runtimeActivities: [ConversationRuntimeActivity]
    var totalCostUSD: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalCachedInputTokens: Int
    var totalReasoningOutputTokens: Int
    var totalTokens: Int
    var reportedContextWindow: Int?

    init(
        nodeID: UUID,
        sessionID: String?,
        messages: [ConversationMessage],
        runtimeActivities: [ConversationRuntimeActivity],
        totalCostUSD: Double,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCachedInputTokens: Int,
        totalReasoningOutputTokens: Int,
        totalTokens: Int,
        reportedContextWindow: Int?
    ) {
        self.nodeID = nodeID
        self.sessionID = sessionID
        self.messages = messages
        self.runtimeActivities = runtimeActivities
        self.totalCostUSD = totalCostUSD
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCachedInputTokens = totalCachedInputTokens
        self.totalReasoningOutputTokens = totalReasoningOutputTokens
        self.totalTokens = totalTokens
        self.reportedContextWindow = reportedContextWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        messages = try container.decode([ConversationMessage].self, forKey: .messages)
        runtimeActivities = try container.decodeIfPresent([ConversationRuntimeActivity].self, forKey: .runtimeActivities) ?? []
        totalCostUSD = try container.decodeIfPresent(Double.self, forKey: .totalCostUSD) ?? 0
        totalInputTokens = try container.decodeIfPresent(Int.self, forKey: .totalInputTokens) ?? 0
        totalOutputTokens = try container.decodeIfPresent(Int.self, forKey: .totalOutputTokens) ?? 0
        totalCachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .totalCachedInputTokens) ?? 0
        totalReasoningOutputTokens = try container.decodeIfPresent(Int.self, forKey: .totalReasoningOutputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? (totalInputTokens + totalOutputTokens + totalCachedInputTokens + totalReasoningOutputTokens)
        reportedContextWindow = try container.decodeIfPresent(Int.self, forKey: .reportedContextWindow)
    }
}

struct PersistedTerminal: Codable {
    var nodeID: UUID
    var transcript: String?

    private enum CodingKeys: String, CodingKey {
        case nodeID
        case transcript
        case currentDirectory
        case lines
    }

    init(nodeID: UUID, transcript: String?) {
        self.nodeID = nodeID
        self.transcript = transcript
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encodeIfPresent(transcript, forKey: .transcript)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        _ = try container.decodeIfPresent(String.self, forKey: .currentDirectory)
        if transcript == nil,
           let lines = try container.decodeIfPresent([PersistedTerminalLine].self, forKey: .lines) {
            transcript = lines
                .map(\.text)
                .joined(separator: "\n")
                .nilIfEmpty
        }
    }
}

struct PersistedProjectData: Codable {
    var conversations: [PersistedConversation]
    var terminals: [PersistedTerminal]?
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

    static func save(conversations: [UUID: ConversationState], terminals: [UUID: TerminalSession], for projectID: UUID) {
        _ = terminals
        let persisted = PersistedProjectData(
            conversations: conversations.map { (nodeID, state) in
                PersistedConversation(
                    nodeID: nodeID,
                    sessionID: state.sessionID,
                    messages: state.messages,
                    runtimeActivities: state.runtimeActivities,
                    totalCostUSD: state.totalCostUSD,
                    totalInputTokens: state.totalInputTokens,
                    totalOutputTokens: state.totalOutputTokens,
                    totalCachedInputTokens: state.totalCachedInputTokens,
                    totalReasoningOutputTokens: state.totalReasoningOutputTokens,
                    totalTokens: state.totalTokens,
                    reportedContextWindow: state.reportedContextWindow
                )
            },
            terminals: nil
        )

        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: fileURL(for: projectID), options: .atomic)
        } catch {
            print("Failed to save: \(error)")
        }
    }

    static func loadConversations(for projectID: UUID) -> [UUID: ConversationState] {
        guard let data = loadData(for: projectID) else { return [:] }

        var result: [UUID: ConversationState] = [:]
        for conv in data.conversations {
            let state = ConversationState(nodeID: conv.nodeID)
            state.sessionID = conv.sessionID
            state.messages = conv.messages
            state.runtimeActivities = conv.runtimeActivities
            state.totalCostUSD = conv.totalCostUSD
            state.totalInputTokens = conv.totalInputTokens
            state.totalOutputTokens = conv.totalOutputTokens
            state.totalCachedInputTokens = conv.totalCachedInputTokens
            state.totalReasoningOutputTokens = conv.totalReasoningOutputTokens
            state.totalTokens = conv.totalTokens
            state.reportedContextWindow = conv.reportedContextWindow
            result[conv.nodeID] = state
        }
        return result
    }

    static func loadTerminals(for projectID: UUID, rootPath: String) -> [UUID: TerminalSession] {
        _ = projectID
        _ = rootPath
        return [:]
    }

    private static func loadData(for projectID: UUID) -> PersistedProjectData? {
        let url = fileURL(for: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            // Try new format first
            if let projectData = try? JSONDecoder().decode(PersistedProjectData.self, from: data) {
                return projectData
            }
            // Fallback: old format (just conversations)
            let oldFormat = try JSONDecoder().decode(PersistedConversations.self, from: data)
            return PersistedProjectData(conversations: oldFormat.conversations, terminals: nil)
        } catch {
            print("Failed to load: \(error)")
            return nil
        }
    }

    static func delete(for projectID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: projectID))
    }
}

// Keep old struct for backward compat
private struct PersistedConversations: Codable {
    var conversations: [PersistedConversation]
}

private struct PersistedTerminalLine: Codable {
    var text: String
    var type: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
