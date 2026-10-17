import AppKit
import Foundation

public struct CleanupEngine {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public func clean(_ items: [CleanupItem], progress: (String) -> Void = { _ in }) -> CleanupOutcome {
        var outcome = CleanupOutcome()
        let fm = FileManager.default
        let policy = PathPolicy(home: home)
        let inventory = AppInventory.collect(home: home)
        let activity = ActivitySnapshot.collect()
        let store = HistoryStore(home: home)
        var history = store.load()
        // Check that history can be saved before touching cleanup targets.
        do { try store.save(history) }
        catch { outcome.failures.append("Cannot save recovery history: \(error.localizedDescription)"); return outcome }
        for item in PathPolicy.removeOverlaps(items) {
            progress(item.title)
            do {
                try policy.validate(item)
                if activity.isBusy(owner: item.ownerID, title: item.title) { throw CleanupError.refused("An associated app or build tool is running.") }
                if item.category == .leftovers, let owner = item.ownerID, inventory.contains(owner) { throw CleanupError.refused("A matching app is installed. Scan again.") }
                var destination: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &destination)
                guard let trashURL = destination as URL? else {
                    outcome.failures.append("\(item.title) moved to Trash, but macOS did not return its recovery path. Restore it using Finder."); continue
                }
                let record = CleanupRecord(originalPath: item.url.path, trashPath: trashURL.path, bytes: item.bytes, title: item.title, trashIdentity: try? policy.identity(at: trashURL))
                outcome.records.append(record); history.insert(record, at: 0)
                do { try store.save(history) }
                catch { outcome.failures.append("Moved \(item.title), but recovery history could not be saved. Restore from Trash in Finder. \(error.localizedDescription)") }
            } catch { outcome.failures.append("\(item.title): \(error.localizedDescription)") }
        }
        return outcome
    }

    public func restore(_ record: CleanupRecord) throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: record.trashPath)
        let destination = URL(fileURLWithPath: record.originalPath).standardizedFileURL
        let trash = home.appendingPathComponent(".Trash").standardizedFileURL
        guard !record.restored, let identity = record.trashIdentity,
              (try? PathPolicy(home: home).identity(at: source)) == identity,
              destination.path.hasPrefix(home.path + "/"),
              source.path.hasPrefix(trash.path + "/"), source.resolvingSymlinksInPath().path == source.path,
              destination.deletingLastPathComponent().resolvingSymlinksInPath().path == destination.deletingLastPathComponent().path,
              fm.fileExists(atPath: destination.deletingLastPathComponent().path),
              !fm.fileExists(atPath: destination.path) else {
            throw CleanupError.refused("The original location is occupied or changed. Use Reveal in Trash to restore manually.")
        }
        try fm.moveItem(at: source, to: destination)
        let store = HistoryStore(home: home)
        var history = store.load()
        if let index = history.firstIndex(where: { $0.id == record.id }) { history[index].restored = true }
        try store.save(history)
    }
}
