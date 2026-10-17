import Foundation
import XCTest
@testable import KlearspaceCore

final class SafetyTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("klearspace-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    @discardableResult
    func file(_ path: String, text: String = "fixture", daysOld: Int = 0) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if daysOld > 0 { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(-daysOld * 86400))], ofItemAtPath: url.path) }
        return url
    }
    func item(_ url: URL, category: CleanupCategory = .applications, level: ReviewLevel = .cache, owner: String? = nil, complete: Bool = true) throws -> CleanupItem {
        CleanupItem(url: url, title: url.lastPathComponent, subtitle: "", category: category, bytes: 4096, fileCount: 1, level: level, explanation: "", ownerID: owner, identity: try PathPolicy(home: home).identity(at: url), complete: complete)
    }
    func testAllowsExactCacheButRefusesEntireCacheRoot() throws {
        let url = try file("Library/Caches/test/a")
        let policy = PathPolicy(home: home)
        XCTAssertNoThrow(try policy.validate(item(url.deletingLastPathComponent())))
        XCTAssertThrowsError(try policy.validate(item(home.appendingPathComponent("Library/Caches"))))
    }
    func testRefusesDocumentsOutsideHomeAndProtectedOrIncompleteItems() throws {
        let document = try file("Documents/important.txt")
        let cache = try file("Library/Caches/test/a")
        let policy = PathPolicy(home: home)
        XCTAssertThrowsError(try policy.validate(item(document)))
        XCTAssertThrowsError(try PathPolicy(home: home.appendingPathComponent("other")).validate(item(cache)))
        XCTAssertThrowsError(try policy.validate(item(cache, level: .protected)))
        XCTAssertThrowsError(try policy.validate(item(cache, complete: false)))
    }
    func testSymlinkTargetsAndSymlinkParentsAreRefused() throws {
        let actual = try file("Documents/precious/a")
        let link = home.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual.deletingLastPathComponent())
        XCTAssertThrowsError(try PathPolicy(home: home).identity(at: link))
        let fake = try item(link.appendingPathComponent("a"))
        XCTAssertThrowsError(try PathPolicy(home: home).validate(fake))
        XCTAssertEqual(try String(contentsOf: actual, encoding: .utf8), "fixture")
    }
    func testChangedOrReplacedFileIsRefused() throws {
        let url = try file("Library/Caches/test/a")
        let scanned = try item(url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        XCTAssertThrowsError(try PathPolicy(home: home).validate(scanned))
        try FileManager.default.removeItem(at: url)
        try Data("new".utf8).write(to: url)
        XCTAssertThrowsError(try PathPolicy(home: home).validate(scanned))
    }
    func testLogsRequireOldIndividualFiles() throws {
        let old = try file("Library/Logs/old.log", daysOld: 40)
        let recent = try file("Library/Logs/recent.log", daysOld: 2)
        let policy = PathPolicy(home: home)
        XCTAssertNoThrow(try policy.validate(item(old, category: .logs)))
        XCTAssertThrowsError(try policy.validate(item(recent, category: .logs)))
        XCTAssertThrowsError(try policy.validate(item(old.deletingLastPathComponent(), category: .logs)))
    }
    func testBrowserPolicyRefusesPasswordsAndWholeProfiles() throws {
        let password = try file("Library/Application Support/Google/Chrome/Default/Login Data")
        let cache = try file("Library/Application Support/Google/Chrome/Default/Cache/a")
        let policy = PathPolicy(home: home)
        XCTAssertThrowsError(try policy.validate(item(password, category: .browsers)))
        XCTAssertThrowsError(try policy.validate(item(password.deletingLastPathComponent(), category: .browsers)))
        XCTAssertNoThrow(try policy.validate(item(cache.deletingLastPathComponent(), category: .browsers)))
    }
    func testLeftoversCannotTargetAppleOrSharedContainers() throws {
        let ordinary = try file("Library/Containers/com.example.removed/a")
        let group = try file("Library/Group Containers/group.example.shared/a")
        let apple = try file("Library/Containers/com.apple.test/a")
        let policy = PathPolicy(home: home)
        XCTAssertNoThrow(try policy.validate(item(ordinary.deletingLastPathComponent(), category: .leftovers, level: .review, owner: "com.example.removed")))
        XCTAssertThrowsError(try policy.validate(item(group.deletingLastPathComponent(), category: .leftovers, level: .review, owner: "group.example.shared")))
        XCTAssertThrowsError(try policy.validate(item(apple.deletingLastPathComponent(), category: .leftovers, level: .review, owner: "com.apple.test")))
        XCTAssertThrowsError(try policy.validate(item(ordinary.deletingLastPathComponent(), category: .leftovers, level: .review, owner: "io.github.kunal-shekte.klearspace")))
    }
    func testOverlapDeduplicatesWithoutPrefixCollision() throws {
        let a = try file("Library/Caches/a/cache/a")
        let b = try file("Library/Caches/ab/a")
        let parent = try item(home.appendingPathComponent("Library/Caches/a"))
        let children = [try item(a), try item(b), parent, parent]
        let result = PathPolicy.removeOverlaps(children)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == parent.id })
    }
    func testFixtureScanExcludesPersonalAndBrowserProfileDataAndClassifiesLeftovers() throws {
        try file("Library/Caches/com.example.cache/cache")
        try file("Library/Application Support/Google/Chrome/Default/Cache/data")
        try file("Library/Application Support/Google/Chrome/Default/Login Data")
        try file("Library/Containers/com.example.removed/Data/Documents/private.txt")
        try file("Library/Containers/com.example.installed/Data/a")
        try file("Library/Containers/com.apple.finder/Data/a")
        try file("Library/Group Containers/group.example.shared/a")
        try file("Library/Logs/old.log", daysOld: 45)
        try file("Library/Logs/recent.log", daysOld: 1)
        try file("Documents/personal.txt")
        var inventory = AppInventory(); inventory.identifiers = ["com.example.installed"]
        let result = CleanupScanner(home: home).scan(inventory: inventory, activity: ActivitySnapshot(appIDs: [], processes: []))
        XCTAssertTrue(result.items.contains { $0.category == .browsers && $0.url.lastPathComponent == "Cache" })
        XCTAssertFalse(result.items.contains { $0.url.lastPathComponent == "Login Data" || $0.url.lastPathComponent == "personal.txt" || $0.url.lastPathComponent == "recent.log" })
        let leftover = try XCTUnwrap(result.items.first { $0.ownerID == "com.example.removed" })
        XCTAssertEqual(leftover.level, .review); XCTAssertFalse(leftover.recommended)
        XCTAssertFalse(result.items.contains { $0.ownerID == "com.example.installed" || $0.ownerID == "com.apple.finder" })
        XCTAssertEqual(result.items.first { $0.ownerID == "group.example.shared" }?.level, .protected)
        for candidate in result.items.filter(\.selectable) { XCTAssertNoThrow(try PathPolicy(home: home).validate(candidate), "\(candidate.url.path) | standard: \(candidate.url.standardizedFileURL.path) | resolved: \(candidate.url.resolvingSymlinksInPath().path) | home: \(home.path)") }
    }
    func testActiveAppsAndBuildToolsAreProtected() throws {
        try file("Library/Caches/com.example.active/a")
        try file(".npm/_cacache/a")
        let result = CleanupScanner(home: home).scan(inventory: AppInventory(), activity: ActivitySnapshot(appIDs: ["com.example.active"], processes: ["node"]))
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { $0.level == .protected })
    }
    func testCancellationDoesNotRecommendPartialScan() throws {
        try file("Library/Caches/com.example.cache/a")
        let flag = CancellationFlag(); flag.cancel()
        let result = CleanupScanner(home: home, cancellation: flag).scan(inventory: AppInventory(), activity: ActivitySnapshot(appIDs: [], processes: []))
        XCTAssertTrue(result.cancelled); XCTAssertTrue(result.items.isEmpty)
    }
    func testHistoryRoundTripAndRestoreWithoutOverwrite() throws {
        let source = try file(".Trash/fixture.cache", text: "recover me")
        let destination = home.appendingPathComponent("Library/Caches/fixture.cache")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = CleanupRecord(originalPath: destination.path, trashPath: source.path, bytes: 10, title: "Fixture", trashIdentity: try PathPolicy(home: home).identity(at: source))
        let store = HistoryStore(home: home); try store.save([record])
        XCTAssertEqual(store.load().first?.id, record.id)
        try CleanupEngine(home: home).restore(record)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "recover me")
        XCTAssertEqual(store.load().first?.restored, true)
        XCTAssertThrowsError(try CleanupEngine(home: home).restore(record))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "recover me")
    }
    func testNamedSupportFoldersAreRecognizedAfterRecordedAppRemoval() throws {
        let store = home.appendingPathComponent("Library/Application Support/Klearspace/known-apps.json")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["com.klearspacetest.removed": "Fixture Notes"]).write(to: store)
        try file("Library/Application Support/Fixture Notes/database.sqlite")
        let result = CleanupScanner(home: home).scan(inventory: AppInventory(), activity: ActivitySnapshot(appIDs: [], processes: []))
        let candidate = try XCTUnwrap(result.items.first { $0.ownerID == "com.klearspacetest.removed" })
        XCTAssertEqual(candidate.level, .review); XCTAssertFalse(candidate.recommended)
        XCTAssertEqual(candidate.url.lastPathComponent, "Fixture Notes")
    }
    func testMacOSTrashRoundTripUsesOnlyGeneratedFixture() throws {
        // This test moves only its newly created UUID fixture to macOS Trash and back.
        let url = try file("Library/Caches/com.klearspacetest." + UUID().uuidString + "/data", text: "generated fixture only")
        let root = url.deletingLastPathComponent()
        let candidate = try item(root)
        let outcome = CleanupEngine(home: home).clean([candidate])
        XCTAssertTrue(outcome.failures.isEmpty, outcome.failures.joined(separator: "\n"))
        let record = try XCTUnwrap(outcome.records.first)
        let trash = URL(fileURLWithPath: record.trashPath)
        defer { if FileManager.default.fileExists(atPath: trash.path) { try? FileManager.default.moveItem(at: trash, to: root) } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertEqual(HistoryStore(home: home).load().first?.originalPath, root.path)
        try FileManager.default.moveItem(at: trash, to: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "generated fixture only")
    }
}
