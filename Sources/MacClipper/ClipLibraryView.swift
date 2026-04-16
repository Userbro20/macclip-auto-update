import SwiftUI
import AVKit
import AppKit

struct ClipLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var player = AVPlayer()

    var body: some View {
        NavigationSplitView {
            ZStack {
                MacClipperBackdrop()

                VStack(spacing: 14) {
                    MacClipperSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Clip Library")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))

                                    Text("Your saved moments, ready to scrub, replay, and find fast.")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                MacClipperPill(title: "\(model.clips.count)", systemImage: "film.stack.fill", tint: MacClipperTheme.cyan)
                            }

                            HStack(spacing: 10) {
                                Button("Refresh") {
                                    model.reloadClips()
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())

                                Button("Open Folder") {
                                    model.openClipsFolder()
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())
                            }
                        }
                    }

                    List(selection: selectedClipURLBinding) {
                        ForEach(model.clips) { clip in
                            ClipSidebarRow(clip: clip, isSelected: model.selectedClip?.url == clip.url)
                                .tag(Optional(clip.url))
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 330)
        } detail: {
            ZStack {
                MacClipperBackdrop()

                Group {
                    if let clip = model.selectedClip {
                        VStack(alignment: .leading, spacing: 18) {
                            MacClipperSurface {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(clip.url.deletingPathExtension().lastPathComponent)
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .lineLimit(2)

                                        Text("Saved \(clip.createdAt.formatted(date: .complete, time: .shortened))")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    ClipSourceIconView(sourceApp: clip.sourceApp, size: 36)
                                }

                                HStack(spacing: 8) {
                                    MacClipperPill(
                                        title: clip.sourceApp?.name ?? "Unknown App",
                                        systemImage: clip.sourceApp == nil ? "questionmark.app.fill" : "app.fill",
                                        tint: MacClipperTheme.cyan
                                    )
                                    MacClipperPill(title: clip.fileSizeText, systemImage: "internaldrive.fill", tint: MacClipperTheme.sand)
                                }
                            }

                            MacClipperSurface(cornerRadius: 28, padding: 14) {
                                VideoPlayer(player: player)
                                    .frame(minHeight: 410)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .onAppear { replacePlayerItem(with: clip.url) }
                            }


                            HStack(spacing: 10) {
                                Button("Play") {
                                    player.play()
                                }
                                .buttonStyle(MacClipperPrimaryButtonStyle())

                                Button("Pause") {
                                    player.pause()
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())

                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())

                                Button("Open Externally") {
                                    model.openClip(clip)
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())

                                Button("Delete") {
                                    player.pause()
                                    model.deleteClip(clip)
                                }
                                .buttonStyle(MacClipperSecondaryButtonStyle())

                                if clip.isUploadedToCloud {
                                    Button {
                                        // Already uploaded - maybe show some feedback
                                    } label: {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .foregroundStyle(MacClipperTheme.cyan)
                                    }
                                    .buttonStyle(MacClipperSecondaryButtonStyle())
                                    .help("Already uploaded to cloud")
                                } else {
                                    Button {
                                        model.uploadClipToBase44(clip.url, sourceApp: clip.sourceApp)
                                    } label: {
                                        Image(systemName: "icloud.and.arrow.up")
                                            .foregroundStyle(MacClipperTheme.cyan)
                                    }
                                    .buttonStyle(MacClipperSecondaryButtonStyle())
                                    .help("Upload to cloud")
                                }

                                ClipEditButton(isProUnlocked: model.hasUnlocked4KPro) {
                                    model.openClipEditor(for: clip)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(20)
                    } else {
                        MacClipperSurface {
                            ContentUnavailableView(
                                "No Clips Yet",
                                systemImage: "film.stack",
                                description: Text("Save a replay clip, then open this library to watch it here.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(20)
                    }
                }
            }
        }
        .navigationTitle("Clip Library")
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") {
                    model.reloadClips()
                }

                Button("Open Folder") {
                    model.openClipsFolder()
                }
            }
        }
        .onAppear {
            model.reloadClips()
            replacePlayerItem(with: model.selectedClip?.url)
        }
        .onChange(of: model.selectedClip?.url) { _, newValue in
            replacePlayerItem(with: newValue)
        }
    }

    private var selectedClipURLBinding: Binding<URL?> {
        Binding(
            get: { model.selectedClip?.url },
            set: { newURL in
                model.selectedClip = model.clips.first(where: { $0.url == newURL })
            }
        )
    }

    private func replacePlayerItem(with url: URL?) {
        guard let url else {
            player.replaceCurrentItem(with: nil)
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
}

private struct ClipSidebarRow: View {
    let clip: SavedClip
    let isSelected: Bool
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ClipSourceIconView(sourceApp: clip.sourceApp, size: 28)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 6) {
                    Text(clip.url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    if clip.isUploadedToCloud {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacClipperTheme.cyan)
                    }
                }

                Text(clip.sourceApp?.name ?? "App not detected")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("•")
                    Text(clip.fileSizeText)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if clip.isUploadedToCloud {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(MacClipperTheme.cyan)
                    .font(.system(size: 16))
                    .help("Already uploaded to cloud")
            } else {
                Button(action: {
                    model.uploadClipToBase44(clip.url, sourceApp: clip.sourceApp)
                }) {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Upload to Base44")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? MacClipperTheme.cyan.opacity(0.18) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? MacClipperTheme.cyan.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ClipEditButtonLabel: View {
    let isProUnlocked: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil.and.outline")
            Text("Edit")

            if isProUnlocked {
                Text("PRO")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
            }
        }
    }
}

private struct ClipEditButton: View {
    let isProUnlocked: Bool
    let action: () -> Void

    var body: some View {
        if isProUnlocked {
            Button(action: action) {
                ClipEditButtonLabel(isProUnlocked: true)
            }
            .buttonStyle(MacClipperPrimaryButtonStyle())
            .help("Edit this clip with the PRO Clip Editor")
        } else {
            Button(action: action) {
                ClipEditButtonLabel(isProUnlocked: false)
            }
            .buttonStyle(MacClipperSecondaryButtonStyle())
            .disabled(true)
            .opacity(0.5)
            .help("Unlock PRO to edit clips")
        }
    }
}

private struct ClipSourceIconView: View {
    let sourceApp: ClipSourceApp?
    let size: CGFloat

    var body: some View {
        if let icon = ClipAppIconProvider.icon(for: sourceApp, size: size) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: max(12, size * 0.72)))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22))
        }
    }
}

private enum ClipAppIconProvider {
    static func icon(for sourceApp: ClipSourceApp?, size: CGFloat) -> NSImage? {
        guard let sourceApp,
              let bundleIdentifier = sourceApp.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
