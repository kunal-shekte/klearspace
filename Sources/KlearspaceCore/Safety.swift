import Foundation

public enum CleanupError: LocalizedError {
    case refused(String)
    public var errorDescription: String? {
        switch self { case .refused(let reason): return reason }
    }
}

public struct PathPolicy {
    public let home: URL
    public init(home: URL) { self.home = home.standardizedFileURL }

    public func identity(at url: URL) throws -> FileIdentity {
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attr[.type] as? FileAttributeType != .typeSymbolicLink,
              let device = attr[.systemNumber] as? NSNumber,
              let inode = attr[.systemFileNumber] as? NSNumber,
              let modified = attr[.modificationDate] as? Date else {
            throw CleanupError.refused("Symbolic links and unsupported files are excluded.")
        }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value, modified: modified)
    }

    public func validate(_ item: CleanupItem) throws {
        guard item.selectable else { throw CleanupError.refused("This item is protected or could not be fully scanned.") }
        let path = item.url.standardizedFileURL.path
        guard path == item.url.path,
              item.url.resolvingSymlinksInPath().path == path,
              home.resolvingSymlinksInPath().path == home.path else {
            throw CleanupError.refused("The path contains a symbolic link or has changed.")
        }
        let prefix = home.path + "/"
        guard path.hasPrefix(prefix) else { throw CleanupError.refused("Only approved files in your home folder can be cleaned.") }
        let relative = String(path.dropFirst(prefix.count))
        let roots: [String]
        switch item.category {
        case .developer:
            roots = ["Library/Developer/Xcode/DerivedData", "Library/Caches", ".gradle/caches", ".npm/_cacache", ".cache/yarn", ".cache/pip", ".cache/org.swift.swiftpm", ".cargo/registry/cache", ".pub-cache/hosted", ".pub-cache/git/cache", "Library/Application Support/Code/Cache", "Library/Application Support/Code/CachedData", "Library/Application Support/Code/GPUCache", "Library/Application Support/Code/Code Cache"]
        case .applications, .browsers:
            roots = ["Library/Caches", "Library/Application Support/Google/Chrome", "Library/Application Support/Microsoft Edge", "Library/Application Support/BraveSoftware/Brave-Browser", "Library/Application Support/Firefox/Profiles"]
        case .logs: roots = ["Library/Logs"]
        case .leftovers:
            roots = ["Library/Containers", "Library/Application Scripts", "Library/Application Support", "Library/Preferences", "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", "Library/Caches"]
        }
        let rootAllowed = roots.contains { root in
            relative.hasPrefix(root + "/") || (relative == root && !["Library/Caches", "Library/Logs", "Library/Containers", "Library/Application Scripts", "Library/Application Support", "Library/Preferences", "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit"].contains(root))
        }
        guard rootAllowed else { throw CleanupError.refused("This location is outside the cleanup policy.") }
        if item.category == .browsers && !relative.hasPrefix("Library/Caches/") {
            guard ["Cache", "Code Cache", "GPUCache", "cache2", "shader-cache", "DawnCache", "GrShaderCache"].contains(item.url.lastPathComponent) else {
                throw CleanupError.refused("Only browser cache folders can be cleaned.")
            }
        }
        if item.category == .logs {
            let a = try FileManager.default.attributesOfItem(atPath: path)
            guard a[.type] as? FileAttributeType == .typeRegular,
                  item.identity.modified < Date().addingTimeInterval(-30 * 86400) else {
                throw CleanupError.refused("Only individual log files older than 30 days are eligible.")
            }
        }
        if item.category == .leftovers {
            guard let owner = item.ownerID, !owner.lowercased().hasPrefix("com.apple."), !owner.lowercased().hasPrefix("group."), !["io.github.kunal-shekte.klearspace", "local.klearspace.app", "local.clearspace.app"].contains(owner.lowercased()) else {
                throw CleanupError.refused("System data, shared containers, and Klearspace data are protected.")
            }
        }
        guard try identity(at: item.url) == item.identity else {
            throw CleanupError.refused("This item changed since the scan. Scan again before cleaning.")
        }
    }

    public static func removeOverlaps(_ items: [CleanupItem]) -> [CleanupItem] {
        var accepted: [CleanupItem] = []
        for item in items.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if !accepted.contains(where: { item.url.path == $0.url.path || item.url.path.hasPrefix($0.url.path + "/") }) { accepted.append(item) }
        }
        return accepted
    }
}

public struct HistoryStore {
    public let url: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = home.appendingPathComponent("Library/Application Support/Klearspace/history.json")
    }
    public func load() -> [CleanupRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CleanupRecord].self, from: data)) ?? []
    }
    public func save(_ records: [CleanupRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: [.atomic])
    }
}
