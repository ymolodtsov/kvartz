import KvartzUI
import SwiftUI
import UniformTypeIdentifiers

enum QuickQueryLayout {
    static let activeEditorVerticalPadding: CGFloat = 8
    static let attachmentTrayHeight: CGFloat = 46
    static let rootChromeHeight: CGFloat = 90
    static let conversationChromeHeight: CGFloat = 84
}

struct QuickQueryView: View {
    private enum SendTransition {
        static let initial = "initial-user-message"
        static let followUp = "follow-up-user-message"
    }

    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sendTransitionNamespace
    @State private var didCopy = false
    @State private var copyConfirmationGeneration = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            header
            editor
            phaseContent
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassSurface(radius: 30)
        .overlay {
            if isDropTargeted {
                dropTargetOverlay
                    .transition(.opacity)
            }
        }
        .onDrop(
            of: [UTType.image.identifier, UTType.fileURL.identifier],
            isTargeted: $isDropTargeted,
            perform: importDroppedImages
        )
        .animation(.easeOut(duration: reduceMotion ? 0.01 : 0.15), value: isDropTargeted)
        .padding(12)
        .environment(\.colorScheme, .dark)
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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 40)
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
        .frame(height: 30)
    }

    @ViewBuilder
    private var editor: some View {
        if !isQuerySubmitted {
            queryEditor
                .matchedGeometryEffect(
                    id: SendTransition.initial,
                    in: sendTransitionNamespace,
                    properties: .frame,
                    isSource: true
                )
        }
    }

    private var queryEditor: some View {
        VStack(spacing: 0) {
            if !model.draftAttachments.isEmpty {
                draftAttachmentStrip
            }

            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    Text(model.configuredProviders.isEmpty ? "Configure a provider in Settings…" : "Ask anything…")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.leading, 20)
                        .padding(.trailing, 13)
                        .allowsHitTesting(false)
                }
                GrowingTextEditor(
                    text: $model.query,
                    height: $model.editorHeight,
                    onSubmit: submitInitialQuery,
                    onEscapeWhenEmpty: onClose,
                    onPasteAttachments: { model.importAttachments(from: $0) },
                    isEnabled: !model.configuredProviders.isEmpty && model.conversation.isEmpty && model.phase != .loading
                )
                .frame(height: model.editorHeight)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
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

    private var isQuerySubmitted: Bool {
        !model.pendingQuestion.isEmpty || !model.pendingAttachments.isEmpty || !model.conversation.isEmpty
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
            }
        case .loading:
            answerView
                .transition(.opacity)
        case .answer:
            answerView
                .transition(.opacity)
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
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(Array(model.conversation.enumerated()), id: \.element.id) { index, turn in
                                if shouldPinConversationTurn(at: index) {
                                    Section {
                                        conversationAnswer(
                                            for: index,
                                            turn: turn,
                                            fadesUnderPinnedHeader: true
                                        )
                                    } header: {
                                        userMessageHeader(
                                            turn.question,
                                            attachments: turn.attachments,
                                            index: index,
                                            isPending: false
                                        )
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                        userMessageHeader(
                                            turn.question,
                                            attachments: turn.attachments,
                                            index: index,
                                            isPending: false
                                        )
                                        conversationAnswer(
                                            for: index,
                                            turn: turn,
                                            fadesUnderPinnedHeader: false
                                        )
                                    }
                                }
                            }

                            if !model.pendingQuestion.isEmpty || !model.pendingAttachments.isEmpty {
                                Section {
                                    ProcessingView()
                                        .frame(height: 44)
                                        .frame(
                                            minHeight: max(44, viewport.size.height - 52),
                                            alignment: .top
                                        )
                                        .padding(.top, 4)
                                        .padding(.bottom, 52)
                                        .mask {
                                            PinnedHeaderContentMask(
                                                headerHeight: estimatedSubmittedMessageHeight(
                                                    question: model.pendingQuestion,
                                                    hasAttachments: !model.pendingAttachments.isEmpty
                                                )
                                            )
                                        }
                                } header: {
                                    userMessageHeader(
                                        model.pendingQuestion,
                                        attachments: model.pendingAttachments,
                                        index: model.conversation.count,
                                        isPending: true
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 3)
                    }
                    .coordinateSpace(name: AnswerScrollCoordinateSpace.name)
                    .mask {
                        VStack(spacing: 0) {
                            Color.white

                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 28)
                        }
                    }
                    .onChange(of: pendingMessageKey) { _, messageKey in
                        guard !messageKey.isEmpty else { return }
                        let anchor = userMessageAnchor(index: model.conversation.count)
                        DispatchQueue.main.async {
                            withAnimation(sendAnimation) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: model.conversation.count) { previousCount, count in
                        guard count > previousCount, count > 1 else { return }
                        let anchor = userMessageAnchor(index: count - 1)
                        DispatchQueue.main.async {
                            withAnimation(sendAnimation) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                    .transaction { transaction in
                        // SwiftUI otherwise keeps an edge anchored while the streaming
                        // answer changes size, which overrides an in-progress user scroll.
                        if #available(macOS 15.0, *) {
                            transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if !model.conversation.isEmpty {
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
        VStack(spacing: 0) {
            if !model.draftAttachments.isEmpty {
                draftAttachmentStrip
            }

            ZStack(alignment: .leading) {
                if model.followUpQuery.isEmpty {
                    Text("Ask a follow-up…")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.leading, 20)
                        .padding(.trailing, 13)
                        .allowsHitTesting(false)
                }

                GrowingTextEditor(
                    text: $model.followUpQuery,
                    height: $model.followUpEditorHeight,
                    onSubmit: submitFollowUpQuery,
                    onEscapeWhenEmpty: onClose,
                    onPasteAttachments: { model.importAttachments(from: $0) },
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
        .matchedGeometryEffect(
            id: SendTransition.followUp,
            in: sendTransitionNamespace,
            properties: .frame,
            isSource: true
        )
    }

    private func submittedQuestion(_ question: String, attachments: [QueryAttachment]) -> some View {
        VStack(alignment: .leading, spacing: question.isEmpty || attachments.isEmpty ? 0 : 9) {
            if !question.isEmpty {
                Text(question)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            if !attachments.isEmpty {
                SubmittedAttachmentStrip(attachments: attachments)
            }
        }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
            .accessibilityLabel("Sent message")
            .accessibilityValue(
                [question, attachments.isEmpty ? "" : "\(attachments.count) attached image(s)"]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            )
    }

    @ViewBuilder
    private func userMessageHeader(
        _ question: String,
        attachments: [QueryAttachment],
        index: Int,
        isPending: Bool
    ) -> some View {
        let message = submittedQuestion(question, attachments: attachments)
            .id(userMessageAnchor(index: index))
            .zIndex(1)

        if isPending {
            message.matchedGeometryEffect(
                id: index == 0 ? SendTransition.initial : SendTransition.followUp,
                in: sendTransitionNamespace,
                properties: .frame,
                isSource: false
            )
        } else {
            message
        }
    }

    private func answerBottomPadding(for index: Int) -> CGFloat {
        let isFinalSection = model.pendingQuestion.isEmpty
            && model.pendingAttachments.isEmpty
            && index == model.conversation.count - 1
        return isFinalSection ? 52 : 14
    }

    private func shouldPinConversationTurn(at index: Int) -> Bool {
        let hasPendingMessage = !model.pendingQuestion.isEmpty || !model.pendingAttachments.isEmpty
        return !hasPendingMessage && index == model.conversation.count - 1
    }

    @ViewBuilder
    private func conversationAnswer(
        for index: Int,
        turn: ConversationTurn,
        fadesUnderPinnedHeader: Bool
    ) -> some View {
        let content = renderedAnswer(for: index, turn: turn)
            .padding(.top, 14)
            .padding(.bottom, answerBottomPadding(for: index))

        if fadesUnderPinnedHeader {
            content.mask {
                PinnedHeaderContentMask(
                    headerHeight: estimatedSubmittedMessageHeight(
                        question: turn.question,
                        hasAttachments: !turn.attachments.isEmpty
                    )
                )
            }
        } else {
            content
        }
    }

    private var pendingMessageKey: String {
        guard !model.pendingQuestion.isEmpty || !model.pendingAttachments.isEmpty else { return "" }
        return model.pendingQuestion + model.pendingAttachments.map(\.id.uuidString).joined()
    }

    private var draftAttachmentStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 9, weight: .semibold))
                Text(
                    model.attachmentError.isEmpty
                        ? "\(model.draftAttachments.count) image\(model.draftAttachments.count == 1 ? "" : "s") attached"
                        : model.attachmentError
                )
                .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(model.attachmentError.isEmpty ? .white.opacity(0.44) : Color.orange.opacity(0.86))
            .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                ForEach(model.draftAttachments) { attachment in
                    DraftAttachmentTile(attachment: attachment) {
                        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.15)) {
                            model.removeDraftAttachment(id: attachment.id)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: QuickQueryLayout.attachmentTrayHeight)
        .animation(
            .timingCurve(0.2, 0, 0, 1, duration: reduceMotion ? 0.01 : 0.2),
            value: model.draftAttachments.map(\.id)
        )
    }

    private var dropTargetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }

            HStack(spacing: 9) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                Text("Drop images to attach")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.leading, 15)
            .padding(.trailing, 17)
            .frame(height: 42)
            .background(Color.white.opacity(0.09), in: Capsule())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func importDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        var acceptedDrop = false

        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                acceptedDrop = true
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async {
                        model.addAttachment(image, suggestedName: provider.suggestedName ?? "Dropped image")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                acceptedDrop = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let itemURL = item as? URL {
                        url = itemURL
                    } else if let data = item as? Data,
                              let path = String(data: data, encoding: .utf8) {
                        url = URL(string: path)
                    } else {
                        url = nil
                    }
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async {
                        model.addAttachment(from: url)
                    }
                }
            }
        }
        return acceptedDrop
    }

    private func userMessageAnchor(index: Int) -> String {
        "user-message-\(index)"
    }

    private var sendAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    private func submitInitialQuery() {
        withAnimation(sendAnimation) {
            model.submit()
        }
    }

    private func submitFollowUpQuery() {
        withAnimation(sendAnimation) {
            model.submitFollowUp()
        }
    }

    private func answerText(for index: Int, turn: ConversationTurn) -> String {
        if index == model.conversation.count - 1, model.phase == .answer {
            return model.displayedAnswer
        }
        return turn.answer
    }

    private func renderedAnswer(for index: Int, turn: ConversationTurn) -> some View {
        ZStack(alignment: .topLeading) {
            if index == model.conversation.count - 1, model.isRevealingAnswer {
                formattedAnswer(turn.answer)
                    .hidden()
                    .accessibilityHidden(true)
            }

            formattedAnswer(answerText(for: index, turn: turn))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedAnswer(_ answer: String) -> some View {
        Text(markdown: answer)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white.opacity(0.93))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
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

private enum AnswerScrollCoordinateSpace {
    static let name = "answer-scroll"
}

private struct PinnedHeaderContentMask: View {
    let headerHeight: CGFloat

    var body: some View {
        GeometryReader { content in
            let contentMinY = content.frame(in: .named(AnswerScrollCoordinateSpace.name)).minY
            let fadeStart = headerHeight
            let fadeEnd = headerHeight + 12

            Canvas { context, size in
                let localFadeStart = fadeStart - contentMinY
                let localFadeEnd = fadeEnd - contentMinY

                if localFadeEnd <= 0 {
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.white)
                    )
                    return
                }

                guard localFadeStart < size.height else { return }

                let gradientTop = max(0, localFadeStart)
                let gradientBottom = min(size.height, localFadeEnd)
                if gradientBottom > gradientTop {
                    context.fill(
                        Path(
                            CGRect(
                                x: 0,
                                y: gradientTop,
                                width: size.width,
                                height: gradientBottom - gradientTop
                            )
                        ),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white]),
                            startPoint: CGPoint(x: 0, y: localFadeStart),
                            endPoint: CGPoint(x: 0, y: localFadeEnd)
                        )
                    )
                }

                if localFadeEnd < size.height {
                    context.fill(
                        Path(
                            CGRect(
                                x: 0,
                                y: max(0, localFadeEnd),
                                width: size.width,
                                height: size.height - max(0, localFadeEnd)
                            )
                        ),
                        with: .color(.white)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DraftAttachmentTile: View {
    let attachment: QueryAttachment
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            AttachmentPreviewImage(attachment: attachment)
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 14, height: 14)
                        .background(Color.black.opacity(0.74), in: Circle())
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.13), lineWidth: 1)
                        }
                        .offset(x: 3, y: -3)
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(AttachmentRemoveButtonStyle())
        .help("Remove \(attachment.name)")
        .accessibilityLabel("Remove attached image, \(attachment.name)")
    }
}

private struct SubmittedAttachmentStrip: View {
    let attachments: [QueryAttachment]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(attachments) { attachment in
                    AttachmentPreviewImage(attachment: attachment)
                        .frame(width: 64, height: 48)
                        .help(attachment.name)
                        .accessibilityLabel("Attached image, \(attachment.name)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct AttachmentPreviewImage: View {
    let attachment: QueryAttachment

    var body: some View {
        Group {
            if let image = QueryAttachmentImageCache.shared.image(for: attachment) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.05))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct AttachmentRemoveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
