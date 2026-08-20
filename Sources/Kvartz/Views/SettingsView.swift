import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedProvider: ProviderKind = .openAI
    @State private var configuration = ProviderConfiguration.load(for: .openAI)
    @State private var codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
    @State private var saveMessage = ""
    @State private var isEnteringCustomModel = false

    var body: some View {
        TabView {
            providersTab
                .tabItem { Label("Providers", systemImage: "point.3.connected.trianglepath.dotted") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
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

    private var providersTab: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI PROVIDERS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)

                ForEach(ProviderKind.allCases) { provider in
                    Button {
                        select(provider)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: provider.symbol)
                                .frame(width: 18)
                            Text(provider.displayName)
                            Spacer()
                            if model.selectedProvider == provider {
                                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            }
                        }
                        .font(.system(size: 13, weight: selectedProvider == provider ? .semibold : .regular))
                        .foregroundStyle(selectedProvider == provider ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(
                            selectedProvider == provider ? Color.primary.opacity(0.075) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 175)
            .padding(.trailing, 16)

            Divider()

            providerDetail
                .padding(.leading, 22)
        }
        .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Global shortcut")
                    .font(.system(size: 17, weight: .semibold))
                Text("Press the shortcut from any app to bring Kvartz forward.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Shortcut")
                Spacer()
                ShortcutRecorder(shortcut: $model.shortcut)
                    .frame(width: 150, height: 34)
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
                Text("Response policy")
                    .font(.system(size: 13, weight: .semibold))
                Text(PromptPolicy.system)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()
            Text("Kvartz stores provider keys in Keychain. Model and URL choices stay in local preferences.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
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
    @Binding var shortcut: KeyboardShortcut

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
    var shortcut = KeyboardShortcut.default
    var onChange: ((KeyboardShortcut) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            isRecording = false
        } else if let value = KeyboardShortcut.from(event: event) {
            shortcut = value
            isRecording = false
            onChange?(value)
        } else {
            NSSound.beep()
        }
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press shortcut…" : shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
