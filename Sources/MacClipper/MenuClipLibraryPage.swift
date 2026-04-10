import SwiftUI
import AVKit
import AppKit

struct MenuClipLibraryPage: View {
    @EnvironmentObject private var model: AppModel

    let onBack: () -> Void

    @State private var player = AVPlayer()

    private let density: SlateDensity = .compact

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    selectedClipPanel

                    SlatePanelDivider()
                    SlateSectionCaption(title: "Saved Clips", density: density)

                    if model.clips.isEmpty {
                        SlateInsetPanel {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No Clips Yet")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(SlateTheme.textPrimary)

                                Text("Save a replay clip and it will show up here inside the popup.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(SlateTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(model.clips) { clip in
                            Button {
                                model.selectedClip = clip
                            } label: {
                                SlateRow(
                                    title: clip.url.deletingPathExtension().lastPathComponent,
                                    subtitle: clipSubtitle(for: clip),
                                    systemImage: clip.sourceApp?.isDesktopCapture == true ? "desktopcomputer" : "film.stack.fill",
                                    isSelected: model.selectedClip?.url == clip.url,
                                    tint: SlateTheme.accent,
                                    density: density
                                ) {
                                    HStack(spacing: 8) {
                                        MenuClipSourceIconView(sourceApp: clip.sourceApp, size: 24)

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(clip.fileSizeText)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(SlateTheme.textSecondary)

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(SlateTheme.textTertiary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 430)
        }
        .frame(width: 560)
        .onAppear {
            model.reloadClips()
            replacePlayerItem(with: model.selectedClip?.url)
        }
        .onChange(of: model.selectedClip?.url) { _, newValue in
            replacePlayerItem(with: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onBack()
            } label: {
                SlateToolbarButtonLabel(systemImage: "chevron.left", density: density)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clip Library")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SlateTheme.textPrimary)

                Text(model.clipCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SlateTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                model.reloadClips()
            } label: {
                SlateToolbarButtonLabel(systemImage: "arrow.clockwise", density: density)
            }
            .buttonStyle(.plain)

            Button {
                model.openClipsFolder()
            } label: {
                SlateToolbarButtonLabel(systemImage: "folder.fill", density: density)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var selectedClipPanel: some View {
        if let clip = model.selectedClip {
            SlateInsetPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        MenuClipSourceIconView(sourceApp: clip.sourceApp, size: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(clip.url.deletingPathExtension().lastPathComponent)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(SlateTheme.textPrimary)
                                .lineLimit(2)

                            Text(clipSubtitle(for: clip))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SlateTheme.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        SlateStatusBadge(title: clip.fileSizeText, tint: SlateTheme.warning)
                    }

                    VideoPlayer(player: player)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 6) {
                        Button {
                            player.play()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Play", systemImage: "play.fill", density: density)
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.pause()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Pause", systemImage: "pause.fill", density: density)
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.revealClip(at: clip.url)
                        } label: {
                            SlateCapsuleButtonLabel(title: "Reveal", systemImage: "folder", density: density)
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.openClip(clip)
                        } label: {
                            SlateCapsuleButtonLabel(title: "Open", systemImage: "arrow.up.right.square", density: density)
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.pause()
                            model.deleteClip(clip)
                        } label: {
                            SlateCapsuleButtonLabel(title: "Delete", systemImage: "trash", tint: SlateTheme.warning, density: density)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            SlateInsetPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick a Clip")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SlateTheme.textPrimary)

                    Text("Choose a saved clip below to preview it here without opening another page.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SlateTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func clipSubtitle(for clip: SavedClip) -> String {
        let sourceName = clip.sourceApp?.name ?? "Unknown App"
        let timestamp = clip.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(sourceName) • \(timestamp)"
    }

    private func replacePlayerItem(with url: URL?) {
        guard let url else {
            player.replaceCurrentItem(with: nil)
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
}

private struct MenuClipSourceIconView: View {
    let sourceApp: ClipSourceApp?
    let size: CGFloat

    var body: some View {
        if let icon = MenuClipAppIconProvider.icon(for: sourceApp, size: size) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "film.fill")
                .font(.system(size: max(10, size * 0.58), weight: .semibold))
                .foregroundStyle(SlateTheme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }
}

private enum MenuClipAppIconProvider {
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