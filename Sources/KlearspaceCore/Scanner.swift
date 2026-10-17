import AppKit
import Foundation
import Security

public struct AppInventory {
    public var identifiers: Set<String> = []
    public var names: Set<String> = []
    public var groups: Set<String> = []
    public var paths: Set<String> = []
    public var appNames: [String: String] = [:]
    public var count: Int { paths.count }

    public static func collect(home: URL, extraRoots: [URL] = []) -> AppInventory {
        var result = AppInventory()
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Library/CoreServices"), URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")] + extraRoots
        func register(_ url: URL) {
            guard let bundle = Bundle(url: url) else { return }
            if let id = bundle.bundleIdentifier { result.identifiers.insert(id.lowercased()) }
            result.names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
            if url.pathExtension == "app" { result.paths.insert(url.path) }
            if url.pathExtension == "app", let id = bundle.bundleIdentifier {
                result.appNames[id] = url.deletingPathExtension().lastPathComponent
            }
            var code: SecStaticCode?
            if SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code {
                var info: CFDictionary?
                if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                   let dictionary = info as? [String: Any],
                   let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
                   let groups = entitlements["com.apple.security.application-groups"] as? [String] {
                    result.groups.formUnion(groups.map { $0.lowercased() })
                }
            }
        }
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    register(url)
                    for sub in ["Contents/PlugIns", "Contents/XPCServices", "Contents/Library", "Contents/Helpers", "Contents/Frameworks"] {
                        if let nested = fm.enumerator(at: url.appendingPathComponent(sub), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                            for case let child as URL in nested where ["app", "appex", "xpc", "bundle"].contains(child.pathExtension) { register(child) }
                        }
                    }
                    enumerator.skipDescendants()
                } else if url.pathExtension == "appex" { register(url); enumerator.skipDescendants() }
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { result.identifiers.insert(id.lowercased()) }
            if let url = app.bundleURL { result.names.insert(url.deletingPathExtension().lastPathComponent.lowercased()) }
        }
        return result
    }

    public func contains(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        if id.hasPrefix("com.apple.") || id.hasPrefix("apple.") || ["io.github.kunal-shekte.klearspace", "local.klearspace.app", "local.clearspace.app"].contains(id) { return true }
        if identifiers.contains(where: { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil
    }
}

public struct ActivitySnapshot {
    public let appIDs: Set<String>
    public let processes: Set<String>
    public let appNames: Set<String>
    public init(appIDs: Set<String>, processes: Set<String>, appNames: Set<String> = []) {
        self.appIDs = appIDs; self.processes = processes; self.appNames = appNames
    }
    public static func collect() -> ActivitySnapshot {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var names: Set<String> = []
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            names = Set((String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent.lowercased() })
        }
        let appNames = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        return ActivitySnapshot(appIDs: ids, processes: names, appNames: appNames)
    }
    public func isBusy(owner: String?, title: String) -> Bool {
        if let owner {
            let id = owner.lowercased()
            if appIDs.contains(where: { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return true }
        }
        let name = title.lowercased()
        if appNames.contains(where: { $0.count > 2 && (name == $0 || name.hasPrefix($0 + " ") || name.hasPrefix($0 + ".")) }) { return true }
        let commands: [String]
        if name.contains("xcode") || name.contains("swift") { commands = ["xcodebuild", "swift", "swiftc", "clang", "sourcekit-lsp"] }
        else if name.contains("gradle") || name.contains("android") || name.contains("jetbrains") { commands = ["java", "gradle", "studio"] }
        else if name.contains("npm") || name.contains("yarn") || name.contains("pnpm") { commands = ["node", "npm", "yarn", "pnpm"] }
        else if name.contains("homebrew") { commands = ["brew", "ruby"] }
        else if name.contains("cocoapods") { commands = ["pod", "ruby"] }
        else if name.contains("python") { commands = ["pip", "pip3"] }
        else if name.contains("cargo") { commands = ["cargo", "rustc"] }
        else if name.contains("flutter") || name.contains("dart") { commands = ["flutter", "dart"] }
        else { commands = [] }
        return !processes.isDisjoint(with: commands)
    }
}

public final class CleanupScanner {
    public let home: URL
    private let fm = FileManager.default
    private var issues: [String] = []
    private var items: [CleanupItem] = []
    private let cancellation: CancellationFlag
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, cancellation: CancellationFlag = CancellationFlag()) {
        self.home = home.standardizedFileURL; self.cancellation = cancellation
    }
    private func children(_ url: URL) -> [URL] {
        guard fm.fileExists(atPath: url.path) else { return [] }
        do { return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) }
        catch { issues.append("Could not read \(short(url)): \(error.localizedDescription)"); return [] }
    }
    private func short(_ url: URL) -> String { url.path.replacingOccurrences(of: home.path, with: "~", options: .anchored) }

    private func measure(_ url: URL) -> (Int64, Int, Bool) {
        var bytes: Int64 = 0; var count = 0; var complete = true
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func add(_ file: URL) {
            do {
                let values = try file.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { return }
                if values.isRegularFile == true { bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0); count += 1 }
            } catch { complete = false }
        }
        add(url)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return (bytes, count, complete) }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in complete = false; return true }) else { return (bytes, count, false) }
        var visited = 0
        for case let file as URL in enumerator {
            visited += 1
            if cancellation.isCancelled || visited > 150_000 { complete = false; break }
            if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { enumerator.skipDescendants(); continue }
            add(file)
        }
        return (bytes, count, complete)
    }

    private func add(_ url: URL, title: String, category: CleanupCategory, owner: String? = nil,
                     level: ReviewLevel = .cache, explanation: String, activity: ActivitySnapshot) {
        guard !cancellation.isCancelled, fm.fileExists(atPath: url.path),
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              let identity = try? PathPolicy(home: home).identity(at: url) else { return }
        let measured = measure(url)
        var protection = level
        var reason = explanation
        if activity.isBusy(owner: owner, title: title) { protection = .protected; reason = "An associated app or tool is running. Quit it and scan again. " + reason }
        if !measured.2 { reason = "Scan incomplete: some files were unreadable or the scan limit was reached. " + reason; issues.append("Incomplete: \(short(url))") }
        items.append(CleanupItem(url: url, title: title, subtitle: category.detail, category: category,
                                 bytes: measured.0, fileCount: measured.1, level: protection,
                                 explanation: reason, ownerID: owner, identity: identity, complete: measured.2))
    }

    public func scan(inventory suppliedInventory: AppInventory? = nil, activity suppliedActivity: ActivitySnapshot? = nil, progress: @escaping (String) -> Void = { _ in }) -> ScanResult {
        items = []; issues = []
        progress("Checking installed apps…")
        let inventory = suppliedInventory ?? AppInventory.collect(home: home)
        let activity = suppliedActivity ?? ActivitySnapshot.collect()
        // Remember exact application names so future scans can recognize named support folders
        // after the corresponding .app bundle has been removed.
        let catalogURL = home.appendingPathComponent("Library/Application Support/Klearspace/known-apps.json")
        var catalog = (try? Data(contentsOf: catalogURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        for (id, name) in inventory.appNames { catalog[id] = name }
        let rebuild = "Temporary files that can be recreated. The next build or launch may take longer."
        let targets: [(String, String, String?)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode Derived Data", "com.apple.dt.Xcode"),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode cache", "com.apple.dt.Xcode"),
            (".gradle/caches", "Gradle caches", nil), (".npm/_cacache", "npm package cache", nil),
            ("Library/Caches/Yarn", "Yarn package cache", nil), (".cache/yarn", "Yarn downloads", nil),
            ("Library/Caches/pnpm", "pnpm cache", nil),
            ("Library/Caches/Homebrew", "Homebrew downloads", nil),
            ("Library/Caches/CocoaPods", "CocoaPods cache", nil),
            ("Library/Caches/pip", "Python package cache", nil), (".cache/pip", "Python pip cache", nil),
            ("Library/Caches/org.swift.swiftpm", "Swift Package Manager", "com.apple.dt.Xcode"),
            (".cache/org.swift.swiftpm", "Swift package downloads", "com.apple.dt.Xcode"),
            (".cargo/registry/cache", "Cargo registry downloads", nil),
            ("Library/Application Support/Code/Cache", "VS Code cache", "com.microsoft.VSCode"),
            ("Library/Application Support/Code/CachedData", "VS Code cached data", "com.microsoft.VSCode"),
            ("Library/Application Support/Code/GPUCache", "VS Code GPU cache", "com.microsoft.VSCode"),
            ("Library/Application Support/Code/Code Cache", "VS Code code cache", "com.microsoft.VSCode")
        ]
        progress("Measuring developer caches…")
        for (path, title, owner) in targets { add(home.appendingPathComponent(path), title: title, category: .developer, owner: owner, explanation: rebuild, activity: activity) }
        for path in [".pub-cache/hosted", ".pub-cache/git/cache"] {
            add(home.appendingPathComponent(path), title: "Flutter / Dart package downloads", category: .developer, level: .review,
                explanation: "Downloaded Dart packages. Run flutter pub get or dart pub get in your projects afterward. Offline builds can stop working until packages are downloaded again. Active package binaries and project source files are excluded.", activity: activity)
        }
        for vendor in ["JetBrains", "Google"] {
            for child in children(home.appendingPathComponent("Library/Caches/" + vendor)) where vendor == "JetBrains" || child.lastPathComponent.hasPrefix("AndroidStudio") {
                add(child, title: child.lastPathComponent, category: .developer, owner: vendor == "Google" ? "com.google.android.studio" : "com.jetbrains", explanation: rebuild, activity: activity)
            }
        }
        progress("Finding browser caches…")
        let browserRoots: [(String, String, String)] = [
            ("Google/Chrome", "Chrome", "com.google.Chrome"), ("Microsoft Edge", "Microsoft Edge", "com.microsoft.edgemac"),
            ("BraveSoftware/Brave-Browser", "Brave", "com.brave.Browser")
        ]
        for (path, name, owner) in browserRoots {
            let root = home.appendingPathComponent("Library/Application Support/" + path)
            for profile in children(root) where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
                for cache in ["Cache", "Code Cache", "GPUCache", "DawnCache", "GrShaderCache"] {
                    add(profile.appendingPathComponent(cache), title: "\(name) · \(profile.lastPathComponent) · \(cache)", category: .browsers, owner: owner, explanation: "Cached web content. Cookies, saved passwords, browsing history, and bookmarks are excluded.", activity: activity)
                }
            }
        }
        for profile in children(home.appendingPathComponent("Library/Caches/Firefox/Profiles")) {
            add(profile, title: "Firefox · " + profile.lastPathComponent, category: .browsers, owner: "org.mozilla.firefox", explanation: "Firefox disk cache. Profile data in Application Support is excluded.", activity: activity)
        }
        progress("Measuring application caches…")
        let cacheRoot = home.appendingPathComponent("Library/Caches")
        for child in children(cacheRoot) {
            let key = child.lastPathComponent
            if ["Google", "JetBrains", "Firefox"].contains(key) { continue }
            if items.contains(where: { $0.url.path == child.path || $0.url.path.hasPrefix(child.path + "/") }) { continue }
            let browser = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"].contains(key)
            let category: CleanupCategory = browser ? .browsers : .applications
            let system = key.lowercased().hasPrefix("com.apple.") && !browser
            add(child, title: key, category: category, owner: key.contains(".") ? key : nil, level: system ? .protected : .cache,
                explanation: system ? "Apple service cache. Managed by macOS and excluded from cleanup." : rebuild, activity: activity)
        }
        progress("Finding logs older than 30 days…")
        let logsRoot = home.appendingPathComponent("Library/Logs")
        var logVisits = 0
        if let enumerator = fm.enumerator(at: logsRoot, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, error in self.issues.append("Could not read \(self.short(url)): \(error.localizedDescription)"); return true }) {
            for case let url as URL in enumerator {
                logVisits += 1
                if cancellation.isCancelled { break }
                if logVisits > 20_000 { issues.append("Old log discovery stopped at 20,000 entries."); break }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true, let date = values.contentModificationDate, date < Date().addingTimeInterval(-30 * 86400) {
                    add(url, title: url.lastPathComponent, category: .logs, explanation: "A user log last modified more than 30 days ago. It may be useful when troubleshooting an older issue.", activity: activity)
                }
            }
        }
        progress("Checking leftover app data…")
        for location in ["Containers", "Application Scripts", "Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit"] {
            for child in children(home.appendingPathComponent("Library/" + location)) {
                if cancellation.isCancelled { break }
                var identifier = child.lastPathComponent
                if location == "Preferences" { identifier = child.deletingPathExtension().lastPathComponent }
                if location == "Saved Application State" { identifier = identifier.replacingOccurrences(of: ".savedState", with: "") }
                if location == "Containers" {
                    let meta = child.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
                    if let data = try? Data(contentsOf: meta), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let value = plist["MCMMetadataIdentifier"] as? String { identifier = value }
                }
                if location == "Application Support", !Self.isBundleID(identifier) {
                    let matches = catalog.filter { $0.value.caseInsensitiveCompare(child.lastPathComponent) == .orderedSame }
                    guard matches.count == 1, let match = matches.first else { continue }
                    identifier = match.key
                }
                guard Self.isBundleID(identifier), !inventory.contains(identifier), !identifier.lowercased().hasPrefix("group.") else { continue }
                if location == "Application Support", items.contains(where: { $0.url.path.hasPrefix(child.path + "/") }) {
                    items.removeAll { $0.url.path.hasPrefix(child.path + "/") }
                }
                add(child, title: identifier, category: .leftovers, owner: identifier, level: .review,
                    explanation: "No matching app was found in standard application folders or Launch Services. Apps on disconnected disks, command-line tools, and helper services can still own this data. Review its contents before selecting; containers and support folders may include documents, settings, or databases.", activity: activity)
            }
        }
        progress("Checking shared containers…")
        for child in children(home.appendingPathComponent("Library/Group Containers")) {
            let id = child.lastPathComponent
            if id.lowercased().contains("apple") { continue }
            add(child, title: id, category: .leftovers, owner: id, level: .protected,
                explanation: inventory.groups.contains(id.lowercased()) ? "Shared with an installed app. Use its official uninstaller if needed." : "Shared container: ownership cannot be established reliably. Reveal it in Finder for manual review; automatic cleanup is disabled.", activity: activity)
        }
        // Parent candidates supersede nested cache candidates to avoid counting storage twice.
        let deduplicated = PathPolicy.removeOverlaps(items)
        if !cancellation.isCancelled && !inventory.appNames.isEmpty {
            do {
                try fm.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(catalog).write(to: catalogURL, options: [.atomic])
            } catch { issues.append("App-name history could not be saved: \(error.localizedDescription)") }
        }
        return ScanResult(items: deduplicated.sorted { $0.bytes > $1.bytes }, issues: Array(Set(issues)).sorted(), appCount: inventory.count, cancelled: cancellation.isCancelled)
    }

    public static func isBundleID(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 3 && components.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
    }
}
