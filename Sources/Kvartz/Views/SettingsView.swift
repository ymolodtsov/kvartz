import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Pane: Equatable {
        case general
        case provider(ProviderKind)
    }

    @ObservedObject var model: AppModel
    @State private var selectedPane: Pane = .general
    @State private var selectedProvider: ProviderKind = .openAI
    @State private var configuration = ProviderConfiguration.load(for: .openAI)
    @State private var codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
    @State private var saveMessage = ""
    @State private var isEnteringCustomModel = false

    var body: some View {
        HStack(spacing: 0) {
            settingsNavigation

            Divider()

            Group {
                switch selectedPane {
                case .general:
                    generalTab
                case .provider:
                    providerDetail
                }
            }
            .padding(.leading, 22)
        }
        .padding(18)
        .onAppear {
            selectedProvider = model.selectedProvider
            configuration = .load(for: model.selectedProvider)
            codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
            refreshCodex()
            model.refreshLaunchAtLoginStatus()
        }
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SETTINGS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 5)

            navigationButton(
                title: "General",
                symbol: "gearshape",
                pane: .general
            )

            ForEach(providerTabOrder) { provider in
                navigationButton(
                    title: provider.displayName,
                    symbol: provider.symbol,
                    pane: .provider(provider),
                    provider: provider
                )
            }
            Spacer()
        }
        .frame(width: 175)
        .padding(.top, 8)
        .padding(.trailing, 16)
    }

    private var providerTabOrder: [ProviderKind] {
        [.codex, .openAI] + ProviderKind.allCases.filter { $0 != .codex && $0 != .openAI }
    }

    private func navigationButton(
        title: String,
        symbol: String,
        pane: Pane,
        provider: ProviderKind? = nil
    ) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            selectedPane = pane
            if let provider {
                select(provider)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let provider, model.selectedProvider == provider {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                isSelected ? Color.primary.opacity(0.075) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var providerDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProvider.displayName)
                        .font(.system(size: 20, weight: .semibold))
                    Text(providerDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use") { activateProvider() }
                    .disabled(model.selectedProvider == selectedProvider)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Model").font(.system(size: 12, weight: .medium))
                ModelSelector(
                    model: modelBinding,
                    suggestions: modelSuggestions,
                    placeholder: selectedProvider.defaultModel,
                    isEnteringCustomModel: $isEnteringCustomModel
                )
                Text(selectedProvider == .codex && model.isLoadingCodexModels
                     ? "Loading models available to this Codex account…"
                     : isEnteringCustomModel
                        ? "Type any model ID, then click Save."
                        : "Click anywhere on the field to choose a model. Manual entry is available in the menu.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if selectedProvider == .codex {
                codexSettings
            } else {
                if selectedProvider.needsAPIKey {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("API key").font(.system(size: 12, weight: .medium))
                        SecureField("Stored in your Mac Keychain", text: $configuration.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Base URL").font(.system(size: 12, weight: .medium))
                    TextField(selectedProvider.defaultBaseURL, text: $configuration.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                saveRow
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var codexSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Codex executable").font(.system(size: 12, weight: .medium))
                TextField("Auto-detect, or enter an absolute path", text: $codexExecutable)
                .textFieldStyle(.roundedBorder)
                Text("Kvartz uses the supported local Codex app-server. Its browser sign-in is managed and refreshed by Codex.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            saveRow

            HStack(spacing: 10) {
                Circle()
                    .fill(model.codexStatus.hasPrefix("Connected") ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(model.codexStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(model.isConnectingCodex ? "Connecting…" : "Connect ChatGPT") {
                    saveConfiguration()
                    model.connectCodex()
                }
                .disabled(model.isConnectingCodex)
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var saveRow: some View {
        HStack {
            Text(saveMessage)
                .font(.system(size: 11))
                .foregroundStyle(saveMessage.hasPrefix("Saved") ? Color.green : Color.red)
            Spacer()
            Button("Save") { saveConfiguration() }
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Global shortcut")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Press the shortcut from any app to bring Kvartz forward.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorder(shortcut: $model.activationShortcut)
                            .frame(width: 180, height: 34)
                    }

                    Text("Click the field, then press a key combination, double-tap a modifier, or hold its left and right keys together.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if model.activationShortcut.mode != .keyboard {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Modifier-only triggers require Input Monitoring permission. Relaunch Kvartz after granting it.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Privacy Settings") { model.openInputMonitoringSettings() }
                                .font(.system(size: 10))
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Text("Open panel")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Picker("Open panel", selection: $model.panelOpeningPosition) {
                            ForEach(PanelOpeningPosition.allCases) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    Text(model.panelOpeningPosition.helpText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch on login")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Start Kvartz automatically when you sign in to this Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                    }

                    if !model.launchAtLoginMessage.isEmpty {
                        HStack(spacing: 8) {
                            Text(model.launchAtLoginMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(model.launchAtLoginNeedsApproval ? Color.secondary : Color.red)
                            Spacer()
                            if model.launchAtLoginNeedsApproval {
                                Button("Open Login Items") { model.openLoginItemsSettings() }
                                    .font(.system(size: 11))
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Response prompt")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Reset to Default") { model.resetSystemPrompt() }
                            .font(.system(size: 11))
                            .disabled(model.systemPrompt == PromptPolicy.defaultSystem)
                    }
                    TextEditor(text: $model.systemPrompt)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 138)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                    Text("Used as system instructions for every request. Changes save automatically.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Text("Kvartz stores provider keys in Keychain. Model and URL choices stay in local preferences.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Link(
                        "Check for Updates",
                        destination: URL(string: "https://github.com/ymolodtsov/kvartz/releases/latest")!
                    )
                    .frame(minHeight: 40)
                    Button("Quit Kvartz", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                    .frame(minWidth: 104, minHeight: 40)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, 12)
    }

    private var providerDescription: String {
        switch selectedProvider {
        case .openAI: "Responses API"
        case .anthropic: "Messages API"
        case .gemini: "Generate Content API"
        case .qwen: "Alibaba Cloud Model Studio"
        case .kimi: "Moonshot AI Open Platform"
        case .glm: "Z.AI chat completions"
        case .openRouter: "One key for many models"
        case .ollama: "Local models on this Mac"
        case .codex: "Use your ChatGPT subscription through Codex"
        }
    }

    private func select(_ provider: ProviderKind) {
        selectedProvider = provider
        configuration = .load(for: provider)
        if provider == .codex {
            codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
        }
        isEnteringCustomModel = false
        saveMessage = ""
        refreshCodex()
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { configuration.model },
            set: { value in
                configuration.model = value
                configuration.saveModel()
                saveMessage = "Saved automatically"
            }
        )
    }

    private var modelSuggestions: [String] {
        if selectedProvider == .codex, !model.codexModels.isEmpty {
            return model.codexModels
        }
        return selectedProvider.suggestedModels
    }

    private func activateProvider() {
        do {
            try configuration.save()
            if configuration.provider == .codex {
                UserDefaults.standard.set(codexExecutable, forKey: "codexExecutable")
            }
            model.selectedProvider = selectedProvider
            model.refreshConfiguredProviders()
            saveMessage = "Saved"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func refreshCodex() {
        guard selectedProvider == .codex else { return }
        model.refreshCodexStatus()
        Task { await model.refreshCodexModels() }
    }

    private func saveConfiguration() {
        do {
            try configuration.save()
            if configuration.provider == .codex {
                UserDefaults.standard.set(codexExecutable, forKey: "codexExecutable")
            }
            model.refreshConfiguredProviders()
            saveMessage = "Saved"
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

private struct ModelSelector: View {
    @Binding var model: String
    let suggestions: [String]
    let placeholder: String
    @Binding var isEnteringCustomModel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        model = suggestion
                        isEnteringCustomModel = false
                    } label: {
                        if model == suggestion {
                            Label(suggestion, systemImage: "checkmark")
                        } else {
                            Text(suggestion)
                        }
                    }
                }

                Divider()

                Button {
                    isEnteringCustomModel = true
                } label: {
                    Label("Enter model ID manually…", systemImage: "pencil")
                }
            } label: {
                HStack(spacing: 10) {
                    Text(model.isEmpty ? placeholder : model)
                        .foregroundStyle(model.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Model")

            if isEnteringCustomModel {
                HStack(spacing: 8) {
                    TextField("Enter a model ID", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)

                    Button("Done") {
                        isEnteringCustomModel = false
                    }
                    .frame(minWidth: 64, minHeight: 40)
                }
            }
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: ActivationShortcut

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.onChange = { shortcut = $0 }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.needsDisplay = true
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut = ActivationShortcut.default
    var onChange: ((ActivationShortcut) -> Void)?
    private var isRecording = false
    private var captureRecognizer = ShortcutCaptureRecognizer()

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            endRecording()
        } else if let value = KeyboardShortcut.from(event: event) {
            captureRecognizer.interrupt()
            complete(with: ActivationShortcut(mode: .keyboard, keyboardShortcut: value))
        } else {
            NSSound.beep()
        }
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording,
              let modifier = PhysicalModifier(rawValue: event.keyCode) else {
            super.flagsChanged(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifierIsActive: Bool
        switch modifier.kind {
        case .command: modifierIsActive = flags.contains(.command)
        case .option: modifierIsActive = flags.contains(.option)
        case .control: modifierIsActive = flags.contains(.control)
        case .shift: modifierIsActive = flags.contains(.shift)
        }
        if let mode = captureRecognizer.flagsChanged(
            key: modifier,
            modifierIsActive: modifierIsActive,
            timestamp: event.timestamp
        ) {
            complete(with: ActivationShortcut(mode: mode, keyboardShortcut: shortcut.keyboardShortcut))
        }
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    private func beginRecording() {
        captureRecognizer = ShortcutCaptureRecognizer()
        guard !isRecording else {
            needsDisplay = true
            return
        }
        isRecording = true
        NotificationCenter.default.post(name: .kvartzShortcutRecordingChanged, object: true)
        needsDisplay = true
    }

    private func complete(with value: ActivationShortcut) {
        shortcut = value
        onChange?(value)
        endRecording()
    }

    private func endRecording() {
        captureRecognizer = ShortcutCaptureRecognizer()
        guard isRecording else { return }
        isRecording = false
        NotificationCenter.default.post(name: .kvartzShortcutRecordingChanged, object: false)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press or double-tap…" : shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
