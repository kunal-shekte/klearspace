import AppKit
import KlearspaceCore
import SwiftUI

@main
struct KlearspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1270, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Mac") { model.scan() }.keyboardShortcut("r").disabled(model.busy)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var result: ScanResult?
    @Published var selected: Set<String> = []
    @Published var page = "Overview"
    @Published var query = ""
    @Published var scanning = false
    @Published var cleaning = false
    @Published var status = "Ready when you are"
    @Published var history = HistoryStore().load()
    @Published var showingReview = false
    @Published var showingIssues = false
    @Published var focused: CleanupItem?
    @Published var message: String?
    @Published var errors: [String] = []
    @Published var capacity: Int64 = 0
    @Published var available: Int64 = 0
    private var cancellation: CancellationFlag?
    var demo: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }
    var busy: Bool { scanning || cleaning }
    var items: [CleanupItem] { result?.items ?? [] }
    var chosen: [CleanupItem] { items.filter { selected.contains($0.id) && $0.selectable } }
    var chosenBytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }
    var eligibleBytes: Int64 { items.filter(\.selectable).reduce(0) { $0 + $1.bytes } }
    var recommendedBytes: Int64 { items.filter(\.recommended).reduce(0) { $0 + $1.bytes } }
    var visibleItems: [CleanupItem] {
        items.filter { item in
            (page == "Overview" || item.category.rawValue == page) &&
            (query.isEmpty || (item.title + item.displayPath).localizedCaseInsensitiveContains(query))
        }
    }
    init() { refreshDisk(); if demo { loadDemo() } }
    func refreshDisk() {
        if let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            capacity = Int64(values.volumeTotalCapacity ?? 0); available = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }
    func scan() {
        guard !busy else { return }
        if demo { loadDemo(); return }
        scanning = true; message = nil; errors = []; selected = []; focused = nil
        let flag = CancellationFlag(); cancellation = flag
        Task {
            let scan = await Task.detached(priority: .userInitiated) {
                CleanupScanner(cancellation: flag).scan { text in
                    Task { @MainActor [weak self] in self?.status = text }
                }
            }.value
            result = scan; scanning = false; cancellation = nil
            if scan.cancelled { selected = []; status = "Scan cancelled · partial results" }
            else { selected = Set(scan.items.filter(\.recommended).map(\.id)); status = "Scan complete" }
            refreshDisk()
        }
    }
    func cancelScan() { cancellation?.cancel(); status = "Stopping scan…" }
    func toggle(_ item: CleanupItem) {
        guard item.selectable && !busy else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }
    func selectRecommended() { selected = Set(items.filter(\.recommended).map(\.id)) }
    func clean() {
        guard !busy, !chosen.isEmpty, !demo else { return }
        let targets = chosen
        showingReview = false; cleaning = true; message = nil; errors = []
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                CleanupEngine().clean(targets) { title in
                    Task { @MainActor [weak self] in self?.status = "Moving \(title)…" }
                }
            }.value
            cleaning = false
            let moved = Set(outcome.records.map(\.originalPath))
            if let old = result {
                result = ScanResult(items: old.items.filter { !moved.contains($0.url.path) }, issues: old.issues, appCount: old.appCount, date: old.date)
            }
            selected.subtract(moved); focused = nil; errors = outcome.failures
            history = HistoryStore().load()
            let bytes = outcome.records.reduce(Int64(0)) { $0 + $1.bytes }
            message = "Moved \(outcome.records.count) items (\(Format.bytes(bytes))) to Trash. Empty Trash in Finder when you’re ready to reclaim disk space."
            status = outcome.failures.isEmpty ? "Cleanup complete" : "Cleanup completed with skipped items"
            refreshDisk()
        }
    }
    func restore(_ record: CleanupRecord) {
        guard !busy, !demo else { return }
        cleaning = true
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do { try CleanupEngine().restore(record); return nil }
                catch { return error.localizedDescription }
            }.value
            cleaning = false
            if let error { errors = [error]; showingIssues = true }
            else { history = HistoryStore().load(); message = "Restored \(record.title). Scan again to refresh the results."; result = nil; selected = [] }
        }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Klearspace-scan.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(items).write(to: url, options: [.atomic]) }
        catch { errors = [error.localizedDescription]; showingIssues = true }
    }
    private func loadDemo() {
        capacity = 512_000_000_000; available = 190_000_000_000
        let home = FileManager.default.homeDirectoryForCurrentUser
        let specs: [(String, String, CleanupCategory, Int64, ReviewLevel)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode Derived Data", .developer, 6_800_000_000, .cache),
            ("Library/Caches/Homebrew", "Homebrew downloads", .developer, 2_420_000_000, .cache),
            (".npm/_cacache", "npm package cache", .developer, 1_180_000_000, .cache),
            ("Library/Caches/com.spotify.client", "Spotify cache", .applications, 740_000_000, .cache),
            ("Library/Caches/com.google.Chrome", "Chrome disk cache", .browsers, 620_000_000, .cache),
            ("Library/Containers/com.example.retired", "com.example.retired", .leftovers, 460_000_000, .review),
            ("Library/Logs/old-build.log", "Build logs · older than 30 days", .logs, 182_000_000, .cache),
            ("Library/Group Containers/group.example.shared", "Shared app container", .leftovers, 280_000_000, .protected)
        ]
        let items = specs.map { spec in CleanupItem(url: home.appendingPathComponent(spec.0), title: spec.1, subtitle: spec.2.detail, category: spec.2, bytes: spec.3, fileCount: 1240, level: spec.4, explanation: spec.4 == .review ? "Possible data from an uninstalled app. Review its documents and settings before selecting." : "Rebuildable cache files. The next launch or build may take longer.", ownerID: nil, identity: FileIdentity(device: 0, inode: 0, modified: Date())) }
        result = ScanResult(items: items, appCount: 86); selected = Set(items.filter(\.recommended).map(\.id)); status = "Preview mode · sample data"
    }
}
