import SwiftUI

struct QuickQueryView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var didCopy = false
    @State private var copyConfirmationGeneration = 0

    var body: some View {
        VStack(spacing: 10) {
            header
            editor
            phaseContent
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassSurface(radius: 30)
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                if model.configuredProviders.isEmpty {
                    Button("Configure providers in Settings…") {
                        NotificationCenter.default.post(name: .kvartzOpenSettings, object: nil)
                    }
                } else {
                    ForEach(model.configuredProviders) { provider in
                        Button {
                            model.selectedProvider = provider
                        } label: {
                            Label(provider.displayName, systemImage: provider.symbol)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(model.configuredProviders.isEmpty ? "Set up a provider" : model.selectedProvider.displayName)
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 30)
                .background(.white.opacity(0.065), in: Capsule())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .tint(.white)
            .environment(\.colorScheme, .dark)
            .fixedSize()

            Spacer()

            Button {
                NotificationCenter.default.post(name: .kvartzOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassIconButtonStyle())
            .help("Settings")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassIconButtonStyle())
            .help("Close")
        }
        .frame(height: 34)
    }

    private var editor: some View {
        ZStack(alignment: .leading) {
            if model.query.isEmpty {
                Text(model.configuredProviders.isEmpty ? "Configure a provider in Settings…" : "Ask anything…")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.horizontal, 13)
                    .allowsHitTesting(false)
            }
            GrowingTextEditor(
                text: $model.query,
                height: $model.editorHeight,
                onSubmit: model.submit,
                onEscapeWhenEmpty: onClose,
                isEnabled: !model.configuredProviders.isEmpty && model.conversation.isEmpty && model.phase != .loading
            )
                .frame(height: model.editorHeight)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if model.phase != .loading {
                Text("↩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .ready:
            if model.configuredProviders.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.075), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add an AI provider to get started")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                        Text("Open Settings, add your credentials, and click Save.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    Spacer()
                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .kvartzOpenSettings, object: nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(.white.opacity(0.075), in: Capsule())
                }
                .padding(10)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack {
                    Text("Return to ask  ·  Shift–Return for a new line")
                    Spacer()
                    Text(model.shortcut.displayString)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.34))
                .padding(.horizontal, 4)
            }
        case .loading:
            if model.conversation.isEmpty {
                ProcessingView()
                    .frame(height: 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                answerView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .answer:
            answerView
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .error:
            if model.conversation.isEmpty {
                errorView
            } else {
                answerView
            }
        }
    }

    private var answerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(model.conversation.enumerated()), id: \.element.id) { index, turn in
                                if index > 0 {
                                    submittedQuestion(turn.question)
                                }

                                Text(markdown: answerText(for: index, turn: turn))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.93))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !model.pendingQuestion.isEmpty {
                                submittedQuestion(model.pendingQuestion)
                                ProcessingView()
                                    .frame(height: 44)
                            }

                            Color.clear
                                .frame(height: 52)
                                .id("conversation-bottom")
                        }
                        .padding(.horizontal, 3)
                    }
                    .onChange(of: model.pendingQuestion) { _, question in
                        guard !question.isEmpty else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: model.displayedAnswer) { _, _ in
                        guard model.conversation.count > 1 else { return }
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.93)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 52)
                .allowsHitTesting(false)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Text("\(model.answer.count) characters")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.27))
                    .monospacedDigit()
                Spacer()
                Button {
                    copyAnswer()
                } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Image(systemName: "doc.on.doc")
                                .opacity(didCopy ? 0 : 1)
                                .scaleEffect(didCopy ? 0.25 : 1)
                                .blur(radius: didCopy ? 4 : 0)
                            Image(systemName: "checkmark")
                                .opacity(didCopy ? 1 : 0)
                                .scaleEffect(didCopy ? 1 : 0.25)
                                .blur(radius: didCopy ? 0 : 4)
                        }
                        .frame(width: 14, height: 14)

                        Text(didCopy ? "Copied" : "Copy")
                    }
                    .frame(minWidth: 82, minHeight: 40, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CopyButtonStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    didCopy
                        ? Color(red: 0.55, green: 0.92, blue: 0.68)
                        : .white.opacity(0.55)
                )
                .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.22), value: didCopy)
                .help(didCopy ? "Copied to clipboard" : "Copy answer")
            }

            if case .error = model.phase {
                errorView
            }

            if !model.conversation.isEmpty && model.phase != .loading && !model.isRevealingAnswer {
                followUpEditor
            }
        }
        .padding(.horizontal, 4)
    }

    private var followUpEditor: some View {
        ZStack(alignment: .leading) {
            if model.followUpQuery.isEmpty {
                Text("Ask a follow-up…")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.horizontal, 13)
                    .allowsHitTesting(false)
            }

            GrowingTextEditor(
                text: $model.followUpQuery,
                height: $model.followUpEditorHeight,
                onSubmit: model.submitFollowUp,
                onEscapeWhenEmpty: onClose,
                fontSize: 16,
                minimumHeight: 44,
                maximumHeight: 120,
                verticalTextInset: 12,
                focusNotification: .kvartzFocusFollowUp
            )
            .frame(height: model.followUpEditorHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .trailing) {
            Text("↩")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.trailing, 14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func submittedQuestion(_ question: String) -> some View {
        Text(question)
            .font(.system(size: 16))
            .foregroundStyle(.white.opacity(0.88))
            .lineSpacing(3)
            .textSelection(.enabled)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }

    private func answerText(for index: Int, turn: ConversationTurn) -> String {
        if index == model.conversation.count - 1, model.phase == .answer {
            return model.displayedAnswer
        }
        return turn.answer
    }

    private var errorView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            if case .error(let message) = model.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.82))
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func copyAnswer() {
        model.copyAnswer()
        copyConfirmationGeneration += 1
        let generation = copyConfirmationGeneration

        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
            didCopy = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard generation == copyConfirmationGeneration else { return }
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                didCopy = false
            }
        }
    }
}

private struct ProcessingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 7) {
            Text("Thinking")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 4, height: 4)
                        .scaleEffect(reduceMotion ? 1 : (animate ? 1 : 0.45))
                        .opacity(reduceMotion ? 0.4 : (animate ? 1 : 0.25))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.7).repeatForever().delay(Double(index) * 0.13),
                            value: animate
                        )
                }
            }
            Spacer()
        }
        .offset(x: reduceMotion ? 0 : (animate ? 12 : 0))
        .padding(.horizontal, 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct CopyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.95 : 0.52))
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.001), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension Text {
    init(markdown: String) {
        if var attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            for run in attributed.runs where run.link != nil {
                attributed[run.range].foregroundColor = .white
                attributed[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: .white)
            }
            self.init(attributed)
        } else {
            self.init(markdown)
        }
    }
}
