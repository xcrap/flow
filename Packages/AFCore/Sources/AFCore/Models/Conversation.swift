import Foundation

// MARK: - Message Role

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Message Content

public enum MessageContent: Codable, Sendable, Equatable {
    case text(String)
    case code(language: String, code: String)
    case image(data: Data, mimeType: String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(id: String, content: String, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type, text, language, code, data, mimeType, id, name, input, content, isError
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .code(let language, let code):
            try container.encode("code", forKey: .type)
            try container.encode(language, forKey: .language)
            try container.encode(code, forKey: .code)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .toolUse(let id, let name, let input):
            try container.encode("toolUse", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let id, let content, let isError):
            try container.encode("toolResult", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "code":
            self = .code(
                language: try container.decode(String.self, forKey: .language),
                code: try container.decode(String.self, forKey: .code)
            )
        case "image":
            self = .image(
                data: try container.decode(Data.self, forKey: .data),
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        case "toolUse":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decode(String.self, forKey: .input)
            )
        case "toolResult":
            self = .toolResult(
                id: try container.decode(String.self, forKey: .id),
                content: try container.decode(String.self, forKey: .content),
                isError: try container.decode(Bool.self, forKey: .isError)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }
}

// MARK: - Conversation Message

public struct ConversationMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var role: MessageRole
    public var content: [MessageContent]
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [MessageContent],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    public var textContent: String {
        content.compactMap { item in
            if case .text(let text) = item { return text }
            return nil
        }.joined()
    }
}

// MARK: - Conversation

public struct Conversation: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var nodeID: UUID
    public var messages: [ConversationMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        nodeID: UUID,
        messages: [ConversationMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.nodeID = nodeID
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
