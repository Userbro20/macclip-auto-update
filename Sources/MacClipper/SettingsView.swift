import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false

    private var clipDurationBinding: Binding<Double> {
        Binding(
            get: { model.clipDuration },
            set: {
                model.clipDuration = $0
                model.savePreferences()
            }
        )
    }

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

    private var systemAudioLevelBinding: Binding<Double> {
        Binding(
            get: { model.systemAudioLevel * 100 },
            set: {
                model.systemAudioLevel = $0 / 100
                model.savePreferences()
            }
        )
    }

    private var microphoneAudioLevelBinding: Binding<Double> {
        Binding(
            get: { model.microphoneAudioLevel * 100 },
            set: {
                model.microphoneAudioLevel = $0 / 100
                model.savePreferences()
            }
        )
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

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { model.updater.automaticallyChecksForUpdates },
            set: {
                model.updater.automaticallyChecksForUpdates = $0
                model.updater.savePreferences()
            }
        )
    }

    private var launchUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { model.updater.checksForUpdatesOnLaunch },
            set: {
                model.updater.checksForUpdatesOnLaunch = $0
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
        ZStack {
            MacClipperBackdrop(style: .menuGray)

            ScrollView {
                SlatePanel(cornerRadius: 34, padding: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsHeader

                        HStack(spacing: 8) {
                            SlateStatusBadge(title: model.isRecording ? "Live Capture" : "Recorder Idle", tint: model.isRecording ? SlateTheme.success : SlateTheme.warning)
                            SlateStatusBadge(title: model.videoQualityPreset.displayName, tint: SlateTheme.accent)
                            SlateStatusBadge(title: "UUID \(model.appUUIDShortDisplayText)", tint: SlateTheme.accent)
                            SlateStatusBadge(title: model.websiteUserIDDisplayText, tint: model.websiteUserID.isEmpty ? SlateTheme.warning : SlateTheme.success)
                            SlateStatusBadge(title: "\(Int(model.clipDuration))s", tint: SlateTheme.warning)
                            SlateStatusBadge(title: model.clipCountText, tint: SlateTheme.accent)
                        }

                        SlatePanelDivider()
                        SlateSectionCaption(title: "Capture")

                        SlateRow(
                            title: "Capture Display",
                            subtitle: "Choose which monitor stays armed for always-on desktop capture.",
                            systemImage: "display.2",
                            isSelected: true,
                            tint: SlateTheme.accent
                        ) {
                            SlateFieldChrome {
                                Picker("Monitor", selection: captureDisplayBinding) {
                                    ForEach(model.availableCaptureDisplays) { display in
                                        Text("\(display.title) • \(display.detail)").tag(display.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(SlateTheme.textPrimary)
                            }
                            .frame(width: 280)
                        }

                        SlateRow(
                            title: "Clip Length",
                            subtitle: "Longer clips keep more context but make export heavier.",
                            systemImage: "timer",
                            isSelected: true,
                            tint: SlateTheme.warning
                        ) {
                            HStack(spacing: 12) {
                                Slider(value: clipDurationBinding, in: 15...120, step: 5)
                                    .tint(SlateTheme.accent)
                                    .frame(width: 220)

                                Text("\(Int(model.clipDuration))s")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(SlateTheme.textPrimary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        SlateRow(
                            title: "Video Quality",
                            subtitle: "Higher quality keeps more detail without the old slow watermark path.",
                            systemImage: "sparkles",
                            isSelected: true,
                            tint: SlateTheme.accent
                        ) {
                            QualitySelector(selection: videoQualityBinding)
                        }

                        SlateRow(
                            title: "Resolution",
                            subtitle: model.captureResolutionSettingsSubtitle,
                            systemImage: "rectangle.compress.vertical",
                            isSelected: true,
                            tint: SlateTheme.warning
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
                            .frame(width: 210)
                        }

                        SlateRow(
                            title: "App UUID",
                            subtitle: model.appUUIDSubtitle,
                            systemImage: "number.square.fill",
                            isSelected: true,
                            tint: SlateTheme.accent
                        ) {
                            Button {
                                model.copyAppUUID()
                            } label: {
                                SlateCapsuleButtonLabel(
                                    title: "Copy UUID",
                                    systemImage: "doc.on.doc",
                                    tint: SlateTheme.textPrimary,
                                    highlighted: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SlateRow(
                            title: "Website User ID",
                            subtitle: model.websiteUserIDSubtitle,
                            systemImage: "person.text.rectangle",
                            isSelected: !model.websiteUserID.isEmpty,
                            tint: model.websiteUserID.isEmpty ? SlateTheme.warning : SlateTheme.success
                        ) {
                            Button {
                                model.copyWebsiteUserID()
                            } label: {
                                SlateCapsuleButtonLabel(
                                    title: model.websiteUserID.isEmpty ? "Waiting" : "Copy ID",
                                    systemImage: model.websiteUserID.isEmpty ? "hourglass" : "doc.on.doc",
                                    tint: SlateTheme.textPrimary,
                                    highlighted: !model.websiteUserID.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.websiteUserID.isEmpty)
                        }

                        SlateRow(
                            title: "4K Pro",
                            subtitle: model.fourKProStatusText,
                            systemImage: model.hasUnlocked4KPro ? "checkmark.seal.fill" : "lock.fill",
                            isSelected: model.hasUnlocked4KPro,
                            tint: model.hasUnlocked4KPro ? SlateTheme.success : SlateTheme.warning
                        ) {
                            Button {
                                model.open4KPurchasePage()
                            } label: {
                                SlateCapsuleButtonLabel(
                                    title: model.hasUnlocked4KPro ? "Open Portal" : "Buy 4K",
                                    systemImage: model.hasUnlocked4KPro ? "arrow.up.forward.app" : "cart.fill",
                                    tint: SlateTheme.textPrimary,
                                    highlighted: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SlateRow(
                            title: "Clip Shortcut",
                            subtitle: model.shortcutDisplayText,
                            systemImage: "keyboard",
                            isSelected: true,
                            tint: SlateTheme.accent
                        ) {
                            ShortcutEditor(
                                shortcutKey: shortcutKeyBinding,
                                useCommand: useCommandBinding,
                                useShift: useShiftBinding,
                                useOption: useOptionBinding,
                                useControl: useControlBinding
                            )
                        }

                        SlatePanelDivider()
                        SlateSectionCaption(title: "Audio + HUD")

                        SlateRow(
                            title: "System Audio",
                            subtitle: model.systemAudioSettingsSubtitle,
                            systemImage: "speaker.wave.3.fill",
                            isSelected: model.captureSystemAudio,
                            tint: SlateTheme.accent
                        ) {
                            SlateToggleButton(isOn: systemAudioBinding)
                        }

                        SlateRow(
                            title: "System Audio Level",
                            subtitle: model.systemAudioLevelSubtitle,
                            systemImage: "slider.horizontal.3",
                            isSelected: model.captureSystemAudio,
                            tint: SlateTheme.accent
                        ) {
                            HStack(spacing: 12) {
                                Slider(value: systemAudioLevelBinding, in: 0...100, step: 5)
                                    .tint(SlateTheme.accent)
                                    .frame(width: 220)
                                    .disabled(!model.captureSystemAudio)

                                Text("\(model.systemAudioLevelPercent)%")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(model.captureSystemAudio ? SlateTheme.textPrimary : SlateTheme.textSecondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        SlateRow(
                            title: "Microphone",
                            subtitle: model.microphoneSettingsSubtitle,
                            systemImage: "mic.fill",
                            isSelected: model.includeMicrophone,
                            tint: SlateTheme.accent
                        ) {
                            SlateToggleButton(isOn: microphoneBinding)
                        }

                        SlateRow(
                            title: "Microphone Level",
                            subtitle: model.microphoneAudioLevelSubtitle,
                            systemImage: "waveform",
                            isSelected: model.includeMicrophone,
                            tint: SlateTheme.accent
                        ) {
                            HStack(spacing: 12) {
                                Slider(value: microphoneAudioLevelBinding, in: 0...200, step: 5)
                                    .tint(SlateTheme.accent)
                                    .frame(width: 220)
                                    .disabled(!model.includeMicrophone)

                                Text("\(model.microphoneAudioLevelPercent)%")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(model.includeMicrophone ? SlateTheme.textPrimary : SlateTheme.textSecondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        SlateRow(
                            title: "Microphone Input",
                            subtitle: model.microphoneSelectionSubtitle,
                            systemImage: "mic",
                            isSelected: true,
                            tint: SlateTheme.accent
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
                            .frame(width: 280)
                        }

                        SlateRow(
                            title: "Cursor",
                            subtitle: model.showCursor ? "Mouse pointer will appear in clips." : "Cursor is hidden from clips.",
                            systemImage: "cursorarrow",
                            isSelected: model.showCursor,
                            tint: SlateTheme.warning
                        ) {
                            SlateToggleButton(isOn: showCursorBinding)
                        }

                        SlateRow(
                            title: "Notifications Overlay",
                            subtitle: model.enableGameNotifications ? "Clip start and finish toasts are enabled." : "Overlay notifications are muted.",
                            systemImage: "bell.badge.fill",
                            isSelected: model.enableGameNotifications,
                            tint: SlateTheme.warning
                        ) {
                            SlateToggleButton(isOn: notificationsBinding)
                        }

                        SlatePanelDivider()
                        SlateSectionCaption(title: "Share + Storage")

                        SlateRow(
                            title: "Discord Channel",
                            subtitle: "This build stays locked to one webhook so uploads always land in the same channel.",
                            systemImage: "paperplane.fill",
                            isSelected: model.hasDiscordWebhookConfigured,
                            tint: SlateTheme.accent
                        ) {
                            HStack(spacing: 8) {
                                SlateStatusBadge(title: "Webhook Locked", tint: SlateTheme.success)

                                Button {
                                    model.testDiscordWebhook()
                                } label: {
                                    SlateCapsuleButtonLabel(title: "Test Channel", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SlateRow(
                            title: "Save Folder",
                            subtitle: model.saveDirectoryPath,
                            systemImage: "folder.fill",
                            isSelected: true,
                            tint: SlateTheme.warning
                        ) {
                            VStack(alignment: .trailing, spacing: 8) {
                                SlateFieldChrome {
                                    TextField("Folder", text: $model.saveDirectoryPath)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(SlateTheme.textPrimary)
                                        .onSubmit {
                                            model.savePreferences()
                                            model.reloadClips()
                                        }
                                }
                                .frame(width: 320)

                                HStack(spacing: 8) {
                                    Button {
                                        model.pickSaveDirectory()
                                    } label: {
                                        SlateCapsuleButtonLabel(title: "Choose Folder", systemImage: "folder.badge.plus")
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        model.openClipsFolder()
                                    } label: {
                                        SlateCapsuleButtonLabel(title: "Open Folder", systemImage: "folder")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        SlatePanelDivider()
                        SlateSectionCaption(title: "Maintenance")

                        SlateRow(
                            title: "Updates",
                            subtitle: "\(model.updater.currentVersionDescription) • \(model.updater.statusText)",
                            systemImage: "arrow.triangle.2.circlepath",
                            isSelected: model.updater.availableUpdate != nil,
                            tint: SlateTheme.success
                        ) {
                            HStack(spacing: 8) {
                                Button {
                                    model.updater.checkForUpdates()
                                } label: {
                                    SlateCapsuleButtonLabel(title: model.updater.checkForUpdatesButtonTitle, systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.updater.canCheckForUpdates)
                            }
                        }

                        SlateRow(
                            title: "Automatic Update Checks",
                            subtitle: model.updater.automaticallyChecksForUpdates ? "MacClipper checks for updates quietly in the background." : "Updates only check when you trigger them manually.",
                            systemImage: "clock.badge.checkmark",
                            isSelected: model.updater.automaticallyChecksForUpdates,
                            tint: SlateTheme.success
                        ) {
                            SlateToggleButton(isOn: automaticUpdatesBinding, onTitle: "Auto", offTitle: "Manual")
                        }

                        SlateRow(
                            title: "Update On App Open",
                            subtitle: model.updater.checksForUpdatesOnLaunch ? "MacClipper runs a background update check every time the app opens." : "App launch will not trigger an update check.",
                            systemImage: "arrow.up.circle.fill",
                            isSelected: model.updater.checksForUpdatesOnLaunch,
                            tint: SlateTheme.success
                        ) {
                            SlateToggleButton(isOn: launchUpdateChecksBinding, onTitle: "On", offTitle: "Off")
                        }

                        AdvancedSettingsSection(model: model, isExpanded: $showAdvancedSettings)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
        .frame(width: 860, height: 900)
        .onAppear {
            model.refreshDiagnosticsLog()
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Button {
                    model.saveClip()
                } label: {
                    SlateToolbarButtonLabel(systemImage: "bolt.fill", tint: SlateTheme.accent, isHighlighted: true)
                }
                .buttonStyle(.plain)
                .disabled(!model.isRecording)

                Button {
                    model.openClipsFolder()
                } label: {
                    SlateToolbarButtonLabel(systemImage: "folder.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedCaptureDisplaySummary)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SlateTheme.textPrimary)

                Text(model.websiteUserID.isEmpty ? "App UUID: \(model.appUUID)" : "Website User ID: \(model.websiteUserID)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SlateTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                model.refreshDiagnosticsLog()
            } label: {
                SlateToolbarButtonLabel(systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Button {
                model.updater.checkForUpdates()
            } label: {
                SlateToolbarButtonLabel(systemImage: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .disabled(!model.updater.canCheckForUpdates)
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

private struct AdvancedSettingsSection: View {
    @ObservedObject var model: AppModel
    @Binding var isExpanded: Bool

    var body: some View {
        SlateInsetPanel {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        SlateStatusBadge(title: "Diagnostics", tint: SlateTheme.accent)
                        SlateStatusBadge(title: "Copy Ready", tint: SlateTheme.warning)
                    }

                    Text("Use this panel when capture or clipping fails. Refresh it, copy the log, and paste it directly into chat.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SlateTheme.textSecondary)

                    Text(model.diagnosticsLogStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SlateTheme.textSecondary)

                    HStack(spacing: 8) {
                        Button {
                            model.refreshDiagnosticsLog()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Refresh Logs", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.copyDiagnosticsLog()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Copy Logs", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.clearDiagnosticsLog()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Clear Logs", systemImage: "trash")
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.revealDiagnosticsLog()
                        } label: {
                            SlateCapsuleButtonLabel(title: "Reveal Log File", systemImage: "folder")
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log File")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SlateTheme.textPrimary)

                        Text(model.diagnosticsLogFilePath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SlateTheme.textSecondary)
                            .textSelection(.enabled)
                    }

                    ScrollView {
                        Text(model.diagnosticsLogText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SlateTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 260)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(SlateTheme.controlBorder, lineWidth: 1)
                    )
                }
                .padding(.top, 16)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced Diagnostics")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SlateTheme.textPrimary)

                    Text("View and copy the internal diagnostics log when you need to debug capture, clipping, or export failures.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SlateTheme.textSecondary)
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    model.refreshDiagnosticsLog()
                }
            }
        }
    }
}

private struct QualitySelector: View {
    @Binding var selection: VideoQualityPreset

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VideoQualityPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    Text(preset.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SlateTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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

private struct ShortcutEditor: View {
    @Binding var shortcutKey: String
    @Binding var useCommand: Bool
    @Binding var useShift: Bool
    @Binding var useOption: Bool
    @Binding var useControl: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                SlateFieldChrome {
                    TextField("Key", text: $shortcutKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SlateTheme.textPrimary)
                }
                .frame(width: 68)

                HStack(spacing: 6) {
                    ShortcutModifierChip(title: "⌘", isOn: $useCommand)
                    ShortcutModifierChip(title: "⇧", isOn: $useShift)
                    ShortcutModifierChip(title: "⌥", isOn: $useOption)
                    ShortcutModifierChip(title: "⌃", isOn: $useControl)
                }
            }
        }
    }
}

private struct ShortcutModifierChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SlateTheme.textPrimary)
                .frame(width: 30)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? SlateTheme.accentSoft : SlateTheme.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isOn ? SlateTheme.accent.opacity(0.42) : SlateTheme.controlBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
