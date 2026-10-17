import Foundation

public enum CleanupCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case developer = "Developer caches"
    case applications = "App caches"
    case browsers = "Browser caches"
    case logs = "Old logs"
    case leftovers = "App leftovers"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .developer: return "curlybraces"
        case .applications: return "square.stack.3d.up"
        case .browsers: return "globe"
        case .logs: return "doc.text"
        case .leftovers: return "shippingbox"
        }
    }
    public var detail: String {
        switch self {
        case .developer: return "Build artifacts & package caches"
        case .applications: return "Temporary data from your apps"
        case .browsers: return "Cached pages & graphics"
        case .logs: return "User logs older than 30 days"
        case .leftovers: return "Possible data from removed apps"
        }
    }
}

public enum ReviewLevel: String, Codable, Sendable {
    case cache, review, protected
    public var label: String {
        switch self {
        case .cache: return "Rebuildable"
        case .review: return "Review first"
        case .protected: return "Protected"
        }
    }
}

public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let modified: Date
    public init(device: UInt64, inode: UInt64, modified: Date) {
        self.device = device; self.inode = inode; self.modified = modified
    }
}

public struct CleanupItem: Identifiable, Codable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
    public let subtitle: String
    public let category: CleanupCategory
    public let bytes: Int64
    public let fileCount: Int
    public let level: ReviewLevel
    public let explanation: String
    public let ownerID: String?
    public let identity: FileIdentity
    public let complete: Bool
    public var selectable: Bool { level != .protected && complete }
    public var recommended: Bool { selectable && level == .cache && bytes > 0 }
    public var displayPath: String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~", options: .anchored)
    }
    public init(url: URL, title: String, subtitle: String, category: CleanupCategory,
                bytes: Int64, fileCount: Int, level: ReviewLevel, explanation: String,
                ownerID: String?, identity: FileIdentity, complete: Bool = true) {
        self.id = url.standardizedFileURL.path
        self.url = url.standardizedFileURL; self.title = title; self.subtitle = subtitle; self.category = category
        self.bytes = bytes; self.fileCount = fileCount; self.level = level
        self.explanation = explanation; self.ownerID = ownerID; self.identity = identity; self.complete = complete
    }
}

public struct ScanResult: Sendable {
    public let items: [CleanupItem]
    public let issues: [String]
    public let appCount: Int
    public let date: Date
    public let cancelled: Bool
    public init(items: [CleanupItem], issues: [String] = [], appCount: Int = 0, date: Date = Date(), cancelled: Bool = false) {
        self.items = items; self.issues = issues; self.appCount = appCount; self.date = date; self.cancelled = cancelled
    }
}

public struct CleanupRecord: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    public let originalPath: String
    public let trashPath: String
    public let bytes: Int64
    public let title: String
    public var restored = false
    public let trashIdentity: FileIdentity?
    public init(originalPath: String, trashPath: String, bytes: Int64, title: String, trashIdentity: FileIdentity? = nil) {
        self.originalPath = originalPath; self.trashPath = trashPath; self.bytes = bytes; self.title = title
        self.trashIdentity = trashIdentity
    }
}

public struct CleanupOutcome: Sendable {
    public var records: [CleanupRecord] = []
    public var failures: [String] = []
    public init() {}
}

public enum Format {
    public static func bytes(_ value: Int64) -> String {
        value <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
