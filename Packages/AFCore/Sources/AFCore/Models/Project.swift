import CoreGraphics
import Foundation

public struct CanvasOffset: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public static let zero = CanvasOffset(x: 0, y: 0)

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }
}

public struct Project: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var rootPath: String
    public var description: String
    public var createdAt: Date
    public var updatedAt: Date
    public var canvasOffset: CanvasOffset
    public var canvasZoom: Double

    public var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Project",
        rootPath: String = NSHomeDirectory(),
        description: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        canvasOffset: CanvasOffset = .zero,
        canvasZoom: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canvasOffset = canvasOffset
        self.canvasZoom = canvasZoom
    }
}
