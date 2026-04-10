import SwiftUI

struct MenuSettingsPage: View {
    @EnvironmentObject private var model: AppModel

    let onBack: () -> Void

    @State private var diagnosticsExpanded = false

    private let density: SlateDensity = .compact

    private var notificationsBinding: Binding<Bool> {
        binding(for: \.enableGameNotifications)
    }

    private var microphoneBinding: Binding<Bool> {
        binding(for: \.includeMicrophone)
    }

    private var microphoneDeviceBinding: Binding<String> {
        Binding(
            get: { model.selectedMicrophoneID },
            set: { model.setSelectedMicrophoneID($0) }
        )
    }

    private var systemAudioBinding: Binding<Bool> {
        binding(for: \.captureSystemAudio)
    }

    private var showCursorBinding: Binding<Bool> {
        binding(for: \.showCursor)
    }

    private var useCommandBinding: Binding<Bool> {
        binding(for: \.useCommand)
    }

    private var useShiftBinding: Binding<Bool> {
        binding(for: \.useShift)
    }

    private var useOptionBinding: Binding<Bool> {
        binding(for: \.useOption)
    }

    private var useControlBinding: Binding<Bool> {
        binding(for: \.useControl)
    }

    private var captureDisplayBinding: Binding<String> {
        Binding(
            get: { model.selectedCaptureDisplayID },
            set: { model.setSelectedCaptureDisplayID($0) }
        )
    }

    private var videoQualityBinding: Binding<VideoQualityPreset> {
        Binding(
            get: { model.videoQualityPreset },
            set: { model.setVideoQualityPreset($0) }
        )
    }

    private var resolutionBinding: Binding<CaptureResolutionPreset> {
        Binding(
            get: { model.captureResolutionPreset },
            set: { model.setCaptureResolutionPreset($0) }
        )
    }

    private var clipDurationBinding: Binding<Double> {
        Binding(
            get: { model.clipDuration },
            set: {
                model.clipDuration = $0
                model.savePreferences()
            }
        )
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { model.updater.automaticallyChecksForUpdates },
            set: {
                model.updater.automaticallyChecksForUpdates = $0
                model.updater.savePreferences()
            }
        )
    }

    private var shortcutKeyBinding: Binding<String> {
        Binding(
            get: { model.shortcutKey },
            set: {
                model.shortcutKey = $0
                model.savePreferences()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SlateSectionCaption(title: "Capture", density: density)

                    SlateRow(
                        title: "Capture Display",
                        subtitle: model.selectedCaptureDisplaySummary,
                        systemImage: "display.2",
                        isSelected: true,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        SlateFieldChrome {
                            Picker("Monitor", selection: captureDisplayBinding) {
                                ForEach(model.availableCaptureDisplays) { display in
                                    Text(display.title).tag(display.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(SlateTheme.textPrimary)
                        }
                        .frame(width: 180)
                    }

                    SlateRow(
                        title: "Clip Length",
                        subtitle: "Save the last \(Int(model.clipDuration)) seconds.",
                        systemImage: "timer",
                        isSelected: true,
                        tint: SlateTheme.warning,
                        density: density
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: clipDurationBinding, in: 15...120, step: 5)
                                .tint(SlateTheme.accent)
                                .frame(width: 120)

                            Text("\(Int(model.clipDuration))s")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SlateTheme.textPrimary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    SlateRow(
                        title: "Video Quality",
                        subtitle: model.videoQualityPreset.displayName,
                        systemImage: "sparkles",
                        isSelected: true,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        MenuSettingsQualitySelector(selection: videoQualityBinding)
                    }

                    SlateRow(
                        title: "Resolution",
                        subtitle: model.captureResolutionSelectionSummary,
                        systemImage: "rectangle.compress.vertical",
                        isSelected: true,
                        tint: SlateTheme.warning,
                        density: density
                    ) {
                        SlateFieldChrome {
                            Picker("Resolution", selection: resolutionBinding) {
                                ForEach(CaptureResolutionPreset.allCases) { preset in
                                    Text(model.captureResolutionOptionTitle(for: preset)).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(SlateTheme.textPrimary)
                        }
                        .frame(width: 170)
                    }

                    SlateRow(
                        title: "App UUID",
                        subtitle: model.appUUIDDisplayText,
                        systemImage: "number.square.fill",
                        isSelected: true,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        Button {
                            model.copyAppUUID()
                        } label: {
                            SlateCapsuleButtonLabel(
                                title: "Copy UUID",
                                systemImage: "doc.on.doc",
                                tint: SlateTheme.textPrimary,
                                highlighted: true,
                                density: density
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SlateRow(
                        title: "Website User ID",
                        subtitle: model.websiteUserIDDisplayText,
                        systemImage: "person.text.rectangle",
                        isSelected: !model.websiteUserID.isEmpty,
                        tint: model.websiteUserID.isEmpty ? SlateTheme.warning : SlateTheme.success,
                        density: density
                    ) {
                        Button {
                            model.copyWebsiteUserID()
                        } label: {
                            SlateCapsuleButtonLabel(
                                title: model.websiteUserID.isEmpty ? "Waiting" : "Copy ID",
                                systemImage: model.websiteUserID.isEmpty ? "hourglass" : "doc.on.doc",
                                tint: SlateTheme.textPrimary,
                                highlighted: !model.websiteUserID.isEmpty,
                                density: density
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.websiteUserID.isEmpty)
                    }

                    SlateRow(
                        title: "4K Pro",
                        subtitle: model.hasUnlocked4KPro ? "Purchased" : "Buy once on the website",
                        systemImage: model.hasUnlocked4KPro ? "checkmark.seal.fill" : "lock.fill",
                        isSelected: model.hasUnlocked4KPro,
                        tint: model.hasUnlocked4KPro ? SlateTheme.success : SlateTheme.warning,
                        density: density
                    ) {
                        Button {
                            model.open4KPurchasePage()
                        } label: {
                            SlateCapsuleButtonLabel(
                                title: model.hasUnlocked4KPro ? "Open Portal" : "Buy 4K",
                                systemImage: model.hasUnlocked4KPro ? "arrow.up.forward.app" : "cart.fill",
                                tint: SlateTheme.textPrimary,
                                highlighted: true,
                                density: density
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SlateRow(
                        title: "Shortcut",
                        subtitle: model.shortcutDisplayText,
                        systemImage: "keyboard",
                        isSelected: true,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        MenuSettingsShortcutEditor(
                            shortcutKey: shortcutKeyBinding,
                            useCommand: useCommandBinding,
                            useShift: useShiftBinding,
                            useOption: useOptionBinding,
                            useControl: useControlBinding
                        )
                    }

                    SlatePanelDivider()
                    SlateSectionCaption(title: "Audio + HUD", density: density)

                    SlateRow(
                        title: "System Audio",
                        subtitle: model.captureSystemAudio ? "Included in clips" : "Muted from clips",
                        systemImage: "speaker.wave.3.fill",
                        isSelected: model.captureSystemAudio,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        SlateToggleButton(isOn: systemAudioBinding)
                    }

                    SlateRow(
                        title: "Microphone",
                        subtitle: model.microphoneSettingsSubtitle,
                        systemImage: "mic.fill",
                        isSelected: model.includeMicrophone,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        SlateToggleButton(isOn: microphoneBinding)
                    }

                    SlateRow(
                        title: "Microphone Input",
                        subtitle: model.microphoneSelectionSubtitle,
                        systemImage: "mic",
                        isSelected: true,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        SlateFieldChrome {
                            Picker("Microphone", selection: microphoneDeviceBinding) {
                                ForEach(model.availableMicrophones) { microphone in
                                    Text(microphone.pickerLabel).tag(microphone.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(SlateTheme.textPrimary)
                        }
                        .frame(width: 210)
                    }

                    SlateRow(
                        title: "Cursor",
                        subtitle: model.showCursor ? "Visible in clips" : "Hidden from clips",
                        systemImage: "cursorarrow",
                        isSelected: model.showCursor,
                        tint: SlateTheme.warning,
                        density: density
                    ) {
                        SlateToggleButton(isOn: showCursorBinding)
                    }

                    SlateRow(
                        title: "Notifications",
                        subtitle: model.enableGameNotifications ? "Overlay toasts enabled" : "Overlay toasts disabled",
                        systemImage: "bell.badge.fill",
                        isSelected: model.enableGameNotifications,
                        tint: SlateTheme.warning,
                        density: density
                    ) {
                        SlateToggleButton(isOn: notificationsBinding)
                    }

                    SlatePanelDivider()
                    SlateSectionCaption(title: "Share + Storage", density: density)

                    SlateRow(
                        title: "Discord Channel",
                        subtitle: model.hasDiscordWebhookConfigured ? "Webhook locked for this build" : "No webhook configured",
                        systemImage: "paperplane.fill",
                        isSelected: model.hasDiscordWebhookConfigured,
                        tint: SlateTheme.accent,
                        density: density
                    ) {
                        Button {
                            model.testDiscordWebhook()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Test Channel", systemImage: "arrow.triangle.2.circlepath", density: density)
                        }
                        .buttonStyle(.plain)
                    }

                    SlateRow(
                        title: "Save Folder",
                        subtitle: model.saveDirectoryPath,
                        systemImage: "folder.fill",
                        isSelected: true,
                        tint: SlateTheme.warning,
                        density: density
                    ) {
                        HStack(spacing: 6) {
                            Button {
                                model.pickSaveDirectory()
                            } label: {
                                SlateCapsuleButtonLabel(title: "Choose", systemImage: "folder.badge.plus", density: density)
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.openClipsFolder()
                            } label: {
                                SlateCapsuleButtonLabel(title: "Open", systemImage: "folder", density: density)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SlatePanelDivider()
                    SlateSectionCaption(title: "Updates + Diagnostics", density: density)

                    SlateRow(
                        title: "Updater",
                        subtitle: model.updater.statusText,
                        systemImage: "arrow.triangle.2.circlepath",
                        isSelected: model.updater.availableUpdate != nil,
                        tint: SlateTheme.success,
                        density: density
                    ) {
                        HStack(spacing: 6) {
                            Button {
                                model.updater.checkForUpdates()
                            } label: {
                                SlateCapsuleButtonLabel(title: "Check", systemImage: "arrow.clockwise", density: density)
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.updater.canCheckForUpdates)
                        }
                    }

                    SlateRow(
                        title: "Automatic Update Checks",
                        subtitle: model.updater.automaticallyChecksForUpdates ? "Background checks on" : "Manual checks only",
                        systemImage: "clock.badge.checkmark",
                        isSelected: model.updater.automaticallyChecksForUpdates,
                        tint: SlateTheme.success,
                        density: density
                    ) {
                        SlateToggleButton(isOn: automaticUpdatesBinding, onTitle: "Auto", offTitle: "Manual")
                    }

                    SlateInsetPanel {
                        DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.diagnosticsLogStatusText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(SlateTheme.textSecondary)

                                HStack(spacing: 6) {
                                    Button {
                                        model.refreshDiagnosticsLog()
                                    } label: {
                                        SlateCapsuleButtonLabel(title: "Refresh", systemImage: "arrow.clockwise", density: density)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        model.copyDiagnosticsLog()
                                    } label: {
                                        SlateCapsuleButtonLabel(title: "Copy", systemImage: "doc.on.doc", density: density)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        model.revealDiagnosticsLog()
                                    } label: {
                                        SlateCapsuleButtonLabel(title: "Reveal", systemImage: "folder", density: density)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(model.diagnosticsLogFilePath)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(SlateTheme.textTertiary)
                                    .lineLimit(2)
                            }
                            .padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Advanced Diagnostics")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SlateTheme.textPrimary)

                                Text("Refresh, copy, or reveal the internal log without opening another window.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(SlateTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 430)
        }
        .frame(width: 560)
        .onAppear {
            model.refreshDiagnosticsLog()
        }
        .onDisappear {
            model.savePreferences()
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
                Text("Settings")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SlateTheme.textPrimary)

                Text("Scroll for capture, audio, share, updater, and diagnostics controls.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SlateTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                model.refreshDiagnosticsLog()
            } label: {
                SlateToolbarButtonLabel(systemImage: "arrow.clockwise", density: density)
            }
            .buttonStyle(.plain)
        }
    }

    private func binding(for keyPath: ReferenceWritableKeyPath<AppModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: {
                model[keyPath: keyPath] = $0
                model.savePreferences()
            }
        )
    }
}

private struct MenuSettingsQualitySelector: View {
    @Binding var selection: VideoQualityPreset

    var body: some View {
        HStack(spacing: 5) {
            ForEach(VideoQualityPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    Text(preset.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SlateTheme.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == preset ? SlateTheme.accentSoft : SlateTheme.control)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(selection == preset ? SlateTheme.accent.opacity(0.44) : SlateTheme.controlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MenuSettingsShortcutEditor: View {
    @Binding var shortcutKey: String
    @Binding var useCommand: Bool
    @Binding var useShift: Bool
    @Binding var useOption: Bool
    @Binding var useControl: Bool

    var body: some View {
        HStack(spacing: 6) {
            SlateFieldChrome {
                TextField("Key", text: $shortcutKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SlateTheme.textPrimary)
            }
            .frame(width: 56)

            HStack(spacing: 4) {
                MenuSettingsShortcutChip(title: "⌘", isOn: $useCommand)
                MenuSettingsShortcutChip(title: "⇧", isOn: $useShift)
                MenuSettingsShortcutChip(title: "⌥", isOn: $useOption)
                MenuSettingsShortcutChip(title: "⌃", isOn: $useControl)
            }
        }
    }
}

private struct MenuSettingsShortcutChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SlateTheme.textPrimary)
                .frame(width: 26)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? SlateTheme.accentSoft : SlateTheme.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isOn ? SlateTheme.accent.opacity(0.42) : SlateTheme.controlBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}