import Foundation
import AFCore
import AFAgent

// MARK: - Conversation Persistence

struct PersistedConversation: Codable {
    var nodeID: UUID
    var sessionID: String?
    var messages: [ConversationMessage]
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
    var lines: [PersistedTerminalLine]
}

struct PersistedTerminalLine: Codable {
    var text: String
    var type: String // "prompt", "command", "output", "error"
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
        let persisted = PersistedProjectData(
            conversations: conversations.map { (nodeID, state) in
                PersistedConversation(
                    nodeID: nodeID,
                    sessionID: state.sessionID,
                    messages: state.messages,
                    totalCostUSD: state.totalCostUSD,
                    totalInputTokens: state.totalInputTokens,
                    totalOutputTokens: state.totalOutputTokens,
                    totalCachedInputTokens: state.totalCachedInputTokens,
                    totalReasoningOutputTokens: state.totalReasoningOutputTokens,
                    totalTokens: state.totalTokens,
                    reportedContextWindow: state.reportedContextWindow
                )
            },
            terminals: terminals.map { (nodeID, session) in
                PersistedTerminal(
                    nodeID: nodeID,
                    lines: session.outputLines.suffix(500).map { line in
                        let typeStr: String = switch line.type {
                        case .prompt: "prompt"
                        case .command: "command"
                        case .output: "output"
                        case .error: "error"
                        }
                        return PersistedTerminalLine(text: line.text, type: typeStr)
                    }
                )
            }
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
        guard let data = loadData(for: projectID),
              let terminals = data.terminals
        else { return [:] }

        var result: [UUID: TerminalSession] = [:]
        for term in terminals {
            let session = TerminalSession(id: term.nodeID, currentDirectory: rootPath)
            session.outputLines = term.lines.map { line in
                let type: TerminalLine.LineType = switch line.type {
                case "command": .command
                case "output": .output
                case "error": .error
                default: .prompt
                }
                return TerminalLine(text: line.text, type: type)
            }
            result[term.nodeID] = session
        }
        return result
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
