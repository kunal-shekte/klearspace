import AppKit
import KlearspaceCore
import SwiftUI

private let mint = Theme.accent
private let canvas = Theme.canvas
private let panel = Theme.panel
private let muted = Theme.muted
private let ink = Theme.ink
private let line = Theme.edge.opacity(0.09)

private func categoryColor(_ category: CleanupCategory) -> Color {
    switch category {
    case .developer: return mint
    case .applications: return Theme.blue
    case .browsers: return Theme.gold
    case .logs: return Theme.violet
    case .leftovers: return Theme.coral
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                if model.page == "Activity" { historyView }
                else if model.page == "Settings" { settingsView }
                else { scanContent }
                if model.page != "Activity" && model.page != "Settings" { actionBar }
            }
        }
        .background(canvas).foregroundStyle(ink)
        .font(.system(size: 13))
        .sheet(isPresented: $model.showingReview) { ReviewSheet().environmentObject(model) }
        .sheet(isPresented: $model.showingIssues) { issuesSheet }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 20, weight: .medium)).foregroundStyle(canvas)
                    .frame(width: 35, height: 35).background(mint, in: RoundedRectangle(cornerRadius: 11))
                Text("Klearspace").font(.system(size: 21, weight: .semibold, design: .rounded)).tracking(-0.5)
            }.padding(.top, 45).padding(.bottom, 42)
            label("WORKSPACE")
            nav("Overview", icon: "square.grid.2x2", color: mint)
            label("CLEAN UP").padding(.top, 26)
            ForEach(CleanupCategory.allCases) { category in
                nav(category.rawValue, icon: category.symbol, color: categoryColor(category), count: model.items.filter { $0.category == category && $0.selectable }.count)
            }
            label("MANAGE").padding(.top, 26)
            nav("Activity", icon: "clock.arrow.circlepath", color: muted)
            nav("Settings", icon: "slider.horizontal.3", color: muted)
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "internaldrive").foregroundStyle(mint); Text("Macintosh storage").font(.system(size: 12, weight: .medium)) }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.edge.opacity(0.08))
                        Capsule().fill(mint.opacity(0.7)).frame(width: geo.size.width * (model.capacity > 0 ? min(1, Double(model.capacity - model.available) / Double(model.capacity)) : 0))
                    }
                }.frame(height: 5)
                Text("\(Format.bytes(model.available)) available").font(.system(size: 11)).foregroundStyle(muted)
            }.padding(16).background(Theme.edge.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) { Circle().fill(mint).frame(width: 5, height: 5); Text("On-device. Always private.").font(.system(size: 10)).foregroundStyle(muted) }.padding(.top, 19).padding(.bottom, 22)
        }.padding(.horizontal, 19).frame(width: 220).background(Theme.sidebar)
    }
    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(muted.opacity(0.7)).padding(.leading, 11).padding(.bottom, 9)
    }
    private func nav(_ title: String, icon: String, color: Color, count: Int = 0) -> some View {
        Button { model.page = title; model.query = ""; model.focused = nil } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(model.page == title ? mint : color.opacity(0.75)).frame(width: 20)
                Text(title).font(.system(size: 12, weight: model.page == title ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.9)
                Spacer(minLength: 2)
                if count > 0 { Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted) }
            }.padding(.horizontal, 11).frame(height: 37)
                .foregroundStyle(model.page == title ? ink : muted)
                .background(model.page == title ? mint.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.bottom, 3)
    }

    private var topbar: some View {
        HStack {
            Text("My Mac").foregroundStyle(muted)
            Text("/").foregroundStyle(muted.opacity(0.4)).padding(.horizontal, 4)
            Text(model.page).fontWeight(.medium)
            Spacer()
            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
            } label: {
                Label(appearance.title, systemImage: appearance.symbol).font(.system(size: 11)).foregroundStyle(muted)
            }.menuStyle(.borderlessButton).fixedSize().help("Choose System, Light, or Dark appearance")
            if model.demo { pill("SAMPLE DATA", color: Theme.warning) }
            Image(systemName: "lock.shield").foregroundStyle(mint)
            Text("Recoverable cleanup").font(.system(size: 11)).foregroundStyle(muted)
        }.padding(.horizontal, 32).frame(height: 65).overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private var scanContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.page == "Overview" ? "A little room to breathe." : model.page).font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                        Text(model.page == "Overview" ? "Less clutter. More space for what’s next." : (CleanupCategory.allCases.first { $0.rawValue == model.page }?.detail ?? "Review the files found on your Mac.")).foregroundStyle(muted)
                    }
                    Spacer()
                    if model.result != nil && !model.busy {
                        Button { model.scan() } label: { Label("Scan again", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9).background(Theme.edge.opacity(0.055), in: Capsule()) }.buttonStyle(.plain)
                    }
                }
                if model.page == "Overview" { hero }
                if let message = model.message { notice(message, icon: "checkmark.circle", color: mint) }
                if !model.errors.isEmpty {
                    Button { model.showingIssues = true } label: { notice("\(model.errors.count) items need attention. View details.", icon: "exclamationmark.circle", color: Theme.warning) }.buttonStyle(.plain)
                }
                if model.result != nil && !model.scanning {
                    if model.page == "Overview" { categories }
                    resultsList
                } else if model.page != "Overview" {
                    VStack(spacing: 14) {
                        Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(mint)
                        Text("See what’s taking up space").font(.system(size: 20, weight: .medium))
                        Text("Scan your Mac to find cleanup options in this category.").foregroundStyle(muted)
                        scanButton
                    }.frame(maxWidth: .infinity).padding(.vertical, 80)
                }
            }.padding(32)
        }
    }
    private var hero: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(mint.opacity(0.035), lineWidth: 1).frame(width: 198, height: 198)
                Circle().stroke(Theme.edge.opacity(0.045), lineWidth: 12).frame(width: 164, height: 164)
                Circle().trim(from: 0, to: model.result == nil ? 0.26 : max(0.005, Double(model.eligibleBytes) / Double(max(1, model.items.reduce(Int64(0)) { $0 + $1.bytes })))).stroke(mint, style: StrokeStyle(lineWidth: 12, lineCap: .round)).frame(width: 164, height: 164).rotationEffect(.degrees(-90))
                VStack(spacing: 5) {
                    Image(systemName: model.scanning ? "sparkle.magnifyingglass" : "sparkles").font(.system(size: 26, weight: .light)).foregroundStyle(mint)
                    Text(model.scanning ? "Scanning" : model.result == nil ? "Fresh start" : "Ready to review").font(.system(size: 12, weight: .medium)).padding(.top, 5)
                    Text(model.result == nil ? "START WITH A SCAN" : "ELIGIBLE / SCANNED").font(.system(size: 7, weight: .medium)).tracking(1.6).foregroundStyle(muted)
                }
            }.frame(width: 215, height: 215).accessibilityLabel(model.scanning ? "Scan in progress" : "Cleanup overview")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) { Circle().fill(mint).frame(width: 5, height: 5); Text(model.result == nil ? "SMART SCAN" : "CLEANUP OPPORTUNITIES").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(mint) }
                if model.scanning {
                    Text("Finding the clutter.").font(.system(size: 33, weight: .semibold)).tracking(-1)
                    ProgressView().controlSize(.small)
                    Text(model.status).font(.system(size: 12)).foregroundStyle(muted)
                } else {
                    Text(model.result == nil ? "Make space for more." : Format.bytes(model.eligibleBytes)).font(.system(size: model.result == nil ? 32 : 48, weight: .semibold)).tracking(-1.7)
                    Text(model.result == nil ? "Find rebuildable caches, old logs, and data left behind by removed apps." : "of eligible data found across \(model.items.filter(\.selectable).count) items.")
                        .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    if model.result != nil {
                        Text("\(Format.bytes(model.recommendedBytes)) in recommended caches & old logs").font(.system(size: 11)).foregroundStyle(mint.opacity(0.8))
                    } else { scanButton.padding(.top, 5) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.result != nil && !model.scanning {
                VStack(alignment: .leading, spacing: 18) {
                    stat("\(model.result?.appCount ?? 0)", "apps checked", "app.badge.checkmark")
                    stat("\(model.items.filter { $0.level == .protected }.count)", "items protected", "shield.lefthalf.filled")
                }.padding(.leading, 20).overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
            }
        }.padding(.horizontal, 24).padding(.vertical, 13)
            .background(LinearGradient(colors: [panel, Theme.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(mint.opacity(0.1), lineWidth: 1))
    }
    private func stat(_ value: String, _ name: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(muted).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 19, weight: .medium)); Text(name).font(.system(size: 10)).foregroundStyle(muted) }
        }
    }
    private var scanButton: some View {
        Button { model.scan() } label: { Label("Scan my Mac", systemImage: "sparkle.magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(canvas).padding(.horizontal, 19).padding(.vertical, 12).background(mint, in: Capsule()) }.buttonStyle(.plain).disabled(model.busy)
    }
    private var categories: some View {
        HStack(spacing: 10) {
            ForEach(CleanupCategory.allCases) { category in
                Button { model.page = category.rawValue } label: {
                    VStack(alignment: .leading, spacing: 13) {
                        Image(systemName: category.symbol).font(.system(size: 17)).foregroundStyle(categoryColor(category))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Format.bytes(model.items.filter { $0.category == category && $0.selectable }.reduce(0) { $0 + $1.bytes })).font(.system(size: 21, weight: .medium)).tracking(-0.6)
                            Text(category.rawValue).font(.system(size: 10)).foregroundStyle(muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(line, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review your scan").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                Text("\(model.visibleItems.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).padding(.horizontal, 7).padding(.vertical, 4).background(Theme.edge.opacity(0.05), in: Capsule())
                Spacer()
                HStack(spacing: 7) { Image(systemName: "magnifyingglass"); TextField("Filter files…", text: $model.query).textFieldStyle(.plain) }.font(.system(size: 11)).foregroundStyle(muted).padding(9).frame(width: 170).background(Theme.edge.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }.padding(.bottom, 15)
            HStack {
                Text("ITEM / LOCATION").tracking(1.2)
                Spacer()
                if model.page == CleanupCategory.leftovers.rawValue {
                    Button("Select candidates") {
                        model.selected.formUnion(model.visibleItems.filter(\.selectable).map(\.id))
                    }.buttonStyle(.plain).foregroundStyle(Theme.warning)
                    Text("·").foregroundStyle(muted)
                }
                Button("Recommended") { model.selectRecommended() }.buttonStyle(.plain).foregroundStyle(mint)
                Text("·").foregroundStyle(muted)
                Button("Clear selection") { model.selected = [] }.buttonStyle(.plain).foregroundStyle(muted)
                Text("SIZE").tracking(1.2).frame(width: 90, alignment: .trailing)
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(muted).padding(.horizontal, 13).padding(.vertical, 11)
            Rectangle().fill(line).frame(height: 1)
            LazyVStack(spacing: 0) {
                ForEach(model.visibleItems) { item in
                    VStack(spacing: 0) {
                        itemRow(item)
                        if model.focused?.id == item.id {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.explanation).font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                                Text("\(item.fileCount) files · \(item.complete ? "Complete scan" : "Partial scan")").font(.system(size: 10)).foregroundStyle(muted)
                                Button { model.reveal(item.url) } label: { Label("Reveal in Finder", systemImage: "folder").font(.system(size: 11)).foregroundStyle(mint) }.buttonStyle(.plain)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 72).padding(.trailing, 18).padding(.bottom, 17)
                        }
                        Rectangle().fill(line).frame(height: 1)
                    }.background(model.focused?.id == item.id ? mint.opacity(0.025) : .clear)
                }
                if model.visibleItems.isEmpty { Text(model.query.isEmpty ? "Nothing to clean here. Looking good." : "No matching items.").foregroundStyle(muted).frame(maxWidth: .infinity).padding(35) }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("Estimates use allocated file sizes. Space is reclaimed after you empty Trash.")
                Spacer()
                if !(model.result?.issues.isEmpty ?? true) {
                    Button("\(model.result?.issues.count ?? 0) scan notes") { model.showingIssues = true }.buttonStyle(.plain).foregroundStyle(Theme.warning)
                }
            }.font(.system(size: 10)).foregroundStyle(muted).padding(.top, 13)
        }
    }
    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 12) {
            Button { model.toggle(item) } label: {
                Image(systemName: item.selectable ? (model.selected.contains(item.id) ? "checkmark.square.fill" : "square") : "lock.fill")
                    .font(.system(size: item.selectable ? 16 : 12)).foregroundStyle(item.selectable && model.selected.contains(item.id) ? mint : muted.opacity(0.65)).frame(width: 20)
            }.buttonStyle(.plain).disabled(!item.selectable || model.busy).accessibilityLabel("Select \(item.title)")
            Image(systemName: item.category.symbol).font(.system(size: 16)).foregroundStyle(categoryColor(item.category)).frame(width: 32, height: 34).background(categoryColor(item.category).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Button { model.focused = model.focused?.id == item.id ? nil : item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                    Text(item.displayPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted.opacity(0.75)).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            pill(item.complete ? item.level.label : "Incomplete", color: item.level == .cache ? mint : item.level == .review ? Theme.warning : muted)
            Text((item.complete ? "" : "≥ ") + Format.bytes(item.bytes)).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 92, alignment: .trailing)
            Button { model.focused = model.focused?.id == item.id ? nil : item } label: { Image(systemName: model.focused?.id == item.id ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundStyle(muted) }.buttonStyle(.plain).accessibilityLabel("Details for \(item.title)")
        }.padding(.horizontal, 13).padding(.vertical, 15)
    }
    private var actionBar: some View {
        HStack(spacing: 14) {
            Image(systemName: model.busy ? "sparkle.magnifyingglass" : "checkmark.shield").foregroundStyle(mint).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.busy ? model.status : "\(model.chosen.count) items selected · \(Format.bytes(model.chosenBytes))").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(model.busy ? "Your files stay in place until you approve cleanup." : "Review once, then move everything selected to Trash.").font(.system(size: 10)).foregroundStyle(muted)
            }
            Spacer()
            if model.scanning {
                Button("Cancel scan") { model.cancelScan() }.buttonStyle(.plain).foregroundStyle(muted)
            } else {
                Button { model.showingReview = true } label: {
                    HStack(spacing: 12) { Text("Review cleanup"); Image(systemName: "arrow.right") }.font(.system(size: 12, weight: .semibold)).foregroundStyle(canvas).padding(.horizontal, 22).padding(.vertical, 13).background(mint.opacity(model.chosen.isEmpty || model.busy ? 0.35 : 1), in: Capsule())
                }.buttonStyle(.plain).disabled(model.chosen.isEmpty || model.busy)
            }
        }.padding(.horizontal, 32).frame(height: 82).background(panel.opacity(0.6)).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }
    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("A cleaner Mac. A clear history.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text("Restore items from Trash before it’s emptied. If an app has recreated a folder, reveal the original in Trash and restore it manually.").foregroundStyle(muted).lineSpacing(5)
                if model.history.isEmpty { notice("Your cleanup history will appear here after your first cleanup.", icon: "clock", color: mint) }
                ForEach(model.history) { record in
                    HStack(spacing: 15) {
                        Image(systemName: record.restored ? "arrow.uturn.backward.circle" : "trash").foregroundStyle(mint)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.title).fontWeight(.medium)
                            Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(Format.bytes(record.bytes))\(record.restored ? " · Restored" : "")").font(.system(size: 10)).foregroundStyle(muted)
                            Text(record.originalPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if !record.restored {
                            Button("Reveal in Trash") { model.reveal(URL(fileURLWithPath: record.trashPath)) }.buttonStyle(.plain).foregroundStyle(muted)
                            Button("Restore") { model.restore(record) }.disabled(model.busy).tint(mint)
                        }
                    }.padding(18).background(panel, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(32)
        }
    }
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("Thoughtful by default.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                settingsBlock("APPEARANCE", symbol: "circle.lefthalf.filled", text: "System follows your Mac’s appearance and is the default. Choose Light or Dark to keep Klearspace in that mode. Your choice is saved for future launches.") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }.pickerStyle(.segmented).frame(width: 340).accessibilityLabel("Appearance")
                }
                settingsBlock("ACCESS", symbol: "lock.open", text: "macOS may block protected folders. If a scan reports access errors, grant Klearspace Full Disk Access in System Settings, quit the app, and reopen it. Access is optional; unreadable items stay excluded.") {
                    Button("Open privacy settings") { model.openPermissions() }.tint(mint)
                }
                settingsBlock("APP LEFTOVERS", symbol: "shippingbox", text: "Finds bundle-identifier matches in Containers, Application Scripts, Preferences, Application Support, Saved Application State, WebKit, and HTTPStorages. A local app-name history helps identify named support folders after future uninstalls. Missing apps are candidates for review; they are never selected automatically. Shared containers and Apple data stay protected.") { EmptyView() }
                settingsBlock("CLEANUP & RECOVERY", symbol: "arrow.uturn.backward", text: "Items move to your Mac’s Trash using Finder’s recovery mechanism. Empty Trash in Finder to reclaim storage. Restore from Activity or Finder first if you need something back. No administrator password is requested.") { EmptyView() }
                settingsBlock("WHAT THE SCAN COVERS", symbol: "scope", text: "Xcode build caches, Gradle, npm, Yarn, pnpm cache, Homebrew, CocoaPods, Python, SwiftPM, Cargo, Flutter/Dart package downloads, JetBrains, VS Code, Chrome, Edge, Brave, Firefox, Safari caches, other user app caches, and user logs older than 30 days. Simulators, editor workspaces, browser profiles, system folders, cloud data, Keychain, and permanent Trash deletion are excluded.") { EmptyView() }
                settingsBlock("SCAN REPORT", symbol: "square.and.arrow.up", text: "Export the current results as JSON. The report contains local file paths and cleanup estimates. Nothing is uploaded.") {
                    Button("Export scan report…") { model.exportReport() }.disabled(model.result == nil).tint(mint)
                }
                Text("Klearspace 1.1.0 · Native macOS · Open source").font(.system(size: 11)).foregroundStyle(muted)
            }.padding(32)
        }
    }
    private func settingsBlock<Content: View>(_ title: String, symbol: String, text: String, @ViewBuilder action: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(mint)
            Text(text).foregroundStyle(muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            action()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(panel, in: RoundedRectangle(cornerRadius: 13))
    }
    private var issuesSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Scan & cleanup notes").font(.system(size: 23, weight: .semibold))
            Text("Unreadable or changing files are skipped. Access errors may require Full Disk Access in Settings.").foregroundStyle(muted)
            ScrollView { VStack(alignment: .leading, spacing: 14) { ForEach(Array((model.errors + (model.result?.issues ?? [])).enumerated()), id: \.offset) { _, text in Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } } }.frame(maxHeight: .infinity)
            HStack { Button("Open privacy settings") { model.openPermissions() }; Spacer(); Button("Done") { model.showingIssues = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 650, height: 500).background(canvas).foregroundStyle(ink)
    }
}

private func pill(_ text: String, color: Color) -> some View {
    Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 5).background(color.opacity(0.07), in: Capsule())
}
private func notice(_ text: String, icon: String, color: Color) -> some View {
    HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(color); Text(text).font(.system(size: 12)).lineSpacing(4); Spacer(minLength: 0) }.padding(16).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
}

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var acknowledged = false
    private var hasData: Bool { model.chosen.contains { $0.category == .leftovers } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "trash.circle").font(.system(size: 35, weight: .light)).foregroundStyle(mint)
            Text("Make room, with a way back.").font(.system(size: 25, weight: .semibold)).tracking(-0.5)
            Text("Move \(model.chosen.count) selected items (\(Format.bytes(model.chosenBytes))) to Trash. Quit the apps you’re cleaning first. You can restore these files until Trash is emptied.").foregroundStyle(muted).lineSpacing(5)
            if hasData { notice("App leftovers can contain personal documents, databases, and settings. An absent app does not prove its data is unused.", icon: "exclamationmark.triangle", color: Theme.warning) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    ForEach(model.chosen) { item in
                        HStack(alignment: .top) {
                            Image(systemName: item.category.symbol).foregroundStyle(categoryColor(item.category)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.system(size: 12, weight: .medium))
                                Text(item.displayPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).textSelection(.enabled)
                            }
                            Spacer()
                            Text(Format.bytes(item.bytes)).font(.system(size: 11, design: .monospaced))
                        }.padding(.vertical, 5)
                    }
                }
            }.frame(maxHeight: .infinity).padding(15).background(Theme.edge.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
            if hasData { Toggle("I reviewed the selected app data and want to remove it.", isOn: $acknowledged).toggleStyle(.checkbox).tint(mint).font(.system(size: 12)) }
            Text("Disk space becomes available after you empty Trash in Finder.").font(.system(size: 11)).foregroundStyle(muted)
            HStack {
                Button("Keep reviewing") { model.showingReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { model.clean() } label: { Label("Move selected to Trash", systemImage: "trash").fontWeight(.semibold).foregroundStyle(canvas).padding(.horizontal, 16).padding(.vertical, 11).background(mint.opacity(hasData && !acknowledged ? 0.3 : 1), in: Capsule()) }.buttonStyle(.plain).disabled((hasData && !acknowledged) || model.chosen.isEmpty || model.demo)
            }
        }.padding(30).frame(width: 660, height: 650).background(canvas).foregroundStyle(ink)
    }
}
