import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let deepLinkNotification = Notification.Name("MacClipperDeepLinkNotification")
    nonisolated static let deepLinkUserInfoKey = "urls"

    private let discordRichPresenceManager = DiscordRichPresenceManager()
    private static var pendingIncomingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppIntegrityMonitor.verifyCurrentAppBundleAtLaunch()
        discordRichPresenceManager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        discordRichPresenceManager.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.pendingIncomingURLs.append(contentsOf: urls)
        NotificationCenter.default.post(
            name: Self.deepLinkNotification,
            object: nil,
            userInfo: [Self.deepLinkUserInfoKey: urls]
        )
    }

    static func takePendingIncomingURLs() -> [URL] {
        let urls = pendingIncomingURLs
        pendingIncomingURLs.removeAll()
        return urls
    }
}

@main
struct MacClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("MacClipper", systemImage: model.isRecording ? "bolt.circle.fill" : "bolt.circle") {
            MenuContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel

    private let menuDensity: SlateDensity = .compact

    @State private var activePage: MenuPage = .dashboard

    enum MenuPage {
        case dashboard
        case library
        case editor
        case settings
    }

    private var saveFolderName: String {
        URL(fileURLWithPath: model.saveDirectoryPath, isDirectory: true).lastPathComponent
    }

    private var lastClipTitle: String {
        model.lastClipName ?? "No clip saved yet"
    }

    private var lastClipSubtitle: String {
        if model.lastClipURL == nil {
            return "Save a clip and it will show up here for fast reveal and sharing."
        }

        return model.clipCountText
    }

    private var replaySubtitle: String {
        model.statusText
    }

    private var captureStateDetail: String {
        if model.isRecording {
            return "\(Int(model.clipDuration))s armed"
        }

        return model.isBusy ? "Starting…" : "Trying to re-arm"
    }


    var body: some View {
        ZStack {
            MacClipperBackdrop(style: .menuGray)

            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    MenuTabButton(icon: "bolt", title: "Dashboard", isSelected: activePage == .dashboard) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .dashboard
                        }
                    }
                    MenuTabButton(icon: "rectangle.stack", title: "Library", isSelected: activePage == .library) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .library
                        }
                    }
                    MenuTabButton(icon: "scissors", title: "Editor", isSelected: activePage == .editor) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .editor
                        }
                    }
                    MenuTabButton(icon: "gearshape", title: "Settings", isSelected: activePage == .settings) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .settings
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                SlatePanel(cornerRadius: 26, padding: 14) {
                    Group {
                        switch activePage {
                        case .dashboard:
                            dashboardPage
                        case .library:
                            MenuClipLibraryPage {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    activePage = .dashboard
                                }
                            }
                            .environmentObject(model)
                        case .editor:
                            MenuClipEditorPage {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    activePage = .dashboard
                                }
                            }
                            .environmentObject(model)
                        case .settings:
                            MenuSettingsPage {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    activePage = .dashboard
                                }
                            }
                            .environmentObject(model)
                        }
                    }
                    .frame(width: 560)
                }
                .padding(12)
            }
        }
        .onAppear {
            model.ensureRecordingActive()
            resetToDashboard()
        }
        .onDisappear {
            model.savePreferences()
            resetToDashboard()
        }
    }

    private func resetToDashboard() {
        activePage = .dashboard
    }

    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            menuHeader

            VStack(spacing: 6) {
                SlateRow(
                    title: "Live Capture",
                    subtitle: replaySubtitle,
                    systemImage: model.isRecording ? "bolt.circle.fill" : "pause.circle.fill",
                        isSelected: activePage == .dashboard,
                    tint: model.isRecording ? SlateTheme.accent : SlateTheme.warning,
                    density: menuDensity
                ) {
                    VStack(alignment: .trailing, spacing: 5) {
                        SlateMeterBar(value: model.isRecording ? 1 : 0.12)
                            .frame(width: 180)

                        Text(captureStateDetail)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SlateTheme.textSecondary)
                    }
                }

                SlateRow(
                    title: lastClipTitle,
                    subtitle: lastClipSubtitle,
                    systemImage: "film.stack.fill",
                    isSelected: model.lastClipURL != nil,
                    tint: SlateTheme.accent,
                    density: menuDensity
                ) {
                    HStack(spacing: 6) {
                        if let lastClipURL = model.lastClipURL {
                            Button {
                                model.revealClip(at: lastClipURL)
                            } label: {
                                SlateCapsuleButtonLabel(title: "Reveal", systemImage: "play.rectangle", density: menuDensity)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            model.reloadClips()
                            withAnimation(.easeInOut(duration: 0.16)) {
                                activePage = .library
                            }
                        } label: {
                            SlateCapsuleButtonLabel(title: "Library", systemImage: "square.grid.2x2", density: menuDensity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                SlateRow(
                    title: saveFolderName,
                    subtitle: model.saveDirectoryPath,
                    systemImage: "folder.fill",
                    isSelected: true,
                    tint: SlateTheme.warning,
                    density: menuDensity
                ) {
                    Button {
                        model.openClipsFolder()
                    } label: {
                        SlateCapsuleButtonLabel(title: "Open Folder", systemImage: "folder", density: menuDensity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Cloud Connection Row
            if !model.isCloudConnected {
                SlateRow(
                    title: "Connect to Cloud",
                    subtitle: "Link your MacClipper account to sync clips automatically",
                    systemImage: "cloud",
                    isSelected: false,
                    tint: SlateTheme.accent,
                    density: menuDensity
                ) {
                    Button {
                        model.openCloudConnectURL()
                    } label: {
                        SlateCapsuleButtonLabel(title: "Connect", systemImage: "link", density: menuDensity)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                SlateRow(
                    title: "Cloud Connected",
                    subtitle: "Your clips are automatically synced to the cloud",
                    systemImage: "cloud.fill",
                    isSelected: true,
                    tint: SlateTheme.success,
                    density: menuDensity
                ) {
                    Button {
                        model.openCloudDashboard()
                    } label: {
                        SlateCapsuleButtonLabel(title: "My Clips", systemImage: "rectangle.stack.fill", density: menuDensity)
                    }
                    .buttonStyle(.plain)
                }
            }

            SlatePanelDivider()
            // --- PRO Section ---
            SlateSectionCaption(title: "PRO", density: menuDensity)
            SlateRow(
                title: "Clip Editor",
                subtitle: model.hasUnlocked4KPro ? "Edit your clips with advanced tools" : "Unlock PRO to use the Clip Editor",
                systemImage: "pencil.and.outline",
                isSelected: model.hasUnlocked4KPro,
                tint: model.hasUnlocked4KPro ? SlateTheme.success : SlateTheme.warning,
                density: menuDensity
            ) {
                Button {
                    if model.hasUnlocked4KPro, let firstClip = model.clips.first {
                        model.openClipEditor(for: firstClip)
                    }
                } label: {
                    SlateCapsuleButtonLabel(
                        title: model.hasUnlocked4KPro ? "Open Editor" : "PRO Only",
                        systemImage: "star.fill",
                        tint: SlateTheme.textPrimary,
                        highlighted: model.hasUnlocked4KPro,
                        density: menuDensity
                    )
                }
                .buttonStyle(.plain)
                .disabled(!model.hasUnlocked4KPro || model.clips.isEmpty)
            }

            SlatePanelDivider()
            SlateSectionCaption(title: "Actions", density: menuDensity)

            VStack(spacing: 6) {
                SlateRow(
                    title: "Clip Now",
                    subtitle: "Save the last \(Int(model.clipDuration)) seconds with \(model.shortcutDisplayText).",
                    systemImage: "bolt.fill",
                    isSelected: model.isRecording,
                    tint: SlateTheme.accent,
                    density: menuDensity
                ) {
                    Button {
                        model.saveClip()
                    } label: {
                        SlateCapsuleButtonLabel(title: "Clip", systemImage: "bolt.fill", tint: SlateTheme.accent, highlighted: true, density: menuDensity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isRecording)
                }

                SlateRow(
                    title: "Clip Library",
                    subtitle: "Browse, preview, and manage your saved clips.",
                    systemImage: "play.rectangle.on.rectangle.fill",
                    isSelected: true,
                    tint: SlateTheme.accent,
                    density: menuDensity
                ) {
                    Button {
                        model.reloadClips()
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .library
                        }
                    } label: {
                        SlateCapsuleButtonLabel(title: "Open Library", systemImage: "play.rectangle", density: menuDensity)
                    }
                    .buttonStyle(.plain)
                }

                SlateRow(
                    title: "Settings",
                    subtitle: "Open the scrollable settings page inside this popup.",
                    systemImage: "gearshape.fill",
                        isSelected: activePage == .settings,
                    tint: SlateTheme.textPrimary,
                    density: menuDensity
                ) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            activePage = .settings
                        }
                    } label: {
                        SlateCapsuleButtonLabel(title: "Open Settings", systemImage: "gearshape", density: menuDensity)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Text("MacClipper v1.2.4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SlateTheme.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    SlateCapsuleButtonLabel(title: "Quit MacClipper", density: menuDensity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Button {
                    model.saveClip()
                } label: {
                    SlateToolbarButtonLabel(systemImage: "bolt.fill", tint: SlateTheme.accent, isHighlighted: true, density: menuDensity)
                }
                .buttonStyle(.plain)
                .disabled(!model.isRecording)

                SlateToolbarButtonLabel(
                    systemImage: model.isRecording ? "wave.3.right.circle.fill" : "arrow.clockwise.circle.fill",
                    tint: model.isRecording ? SlateTheme.success : SlateTheme.warning,
                    density: menuDensity
                )
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            HStack(spacing: 5) {
                Image(systemName: "display")
                    .font(.system(size: 11, weight: .bold))
                Text(model.selectedCaptureDisplaySummary)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SlateTheme.textSecondary)

            HStack(spacing: 5) {
                Image(systemName: "number.square.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(model.appUUIDShortDisplayText)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(SlateTheme.accent)

            Spacer(minLength: 0)

            Button {
                model.openClipsFolder()
            } label: {
                SlateToolbarButtonLabel(systemImage: "folder.fill", density: menuDensity)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    activePage = .settings
                }
            } label: {
                SlateToolbarButtonLabel(systemImage: "gearshape.fill", density: menuDensity)
            }
            .buttonStyle(.plain)
        }
    }
}

struct UpdaterMenuSection: View {
    @ObservedObject var updater: UpdaterManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(updater.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                updater.checkForUpdates()
            } label: {
                Label(updater.checkForUpdatesButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
