import AppKit
import Combine
import SwiftUI

final class QueryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func panelFrameKeepingTop(
    currentFrame: NSRect,
    preferredHeight: CGFloat,
    width: CGFloat,
    topY: CGFloat,
    visibleFrame: NSRect
) -> NSRect {
    let availableHeight = max(1, topY - visibleFrame.minY)
    let height = min(preferredHeight, availableHeight)
    return NSRect(
        x: currentFrame.origin.x,
        y: topY - height,
        width: width,
        height: height
    )
}

func panelFrameKeepingBottom(
    currentFrame: NSRect,
    preferredHeight: CGFloat,
    width: CGFloat,
    bottomY: CGFloat,
    visibleFrame: NSRect
) -> NSRect {
    let availableHeight = max(1, visibleFrame.maxY - bottomY)
    let height = min(preferredHeight, availableHeight)
    return NSRect(
        x: currentFrame.origin.x,
        y: bottomY,
        width: width,
        height: height
    )
}

enum CursorPanelEdge: Equatable {
    case top
    case bottom
}

struct CursorPanelPosition: Equatable {
    let frame: NSRect
    let anchoredEdge: CursorPanelEdge
}

func panelPositionNearCursor(
    cursor: NSPoint,
    panelSize: NSSize,
    visibleFrame: NSRect,
    gap: CGFloat = 12
) -> CursorPanelPosition {
    let cursorX = min(max(cursor.x, visibleFrame.minX), visibleFrame.maxX)
    let cursorY = min(max(cursor.y, visibleFrame.minY), visibleFrame.maxY)
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
    let x = min(max(cursorX - panelSize.width / 2, visibleFrame.minX), maximumX)
    let topForPanelBelow = cursorY - gap
    let bottomForPanelAbove = cursorY + gap
    let spaceBelow = max(0, topForPanelBelow - visibleFrame.minY)
    let spaceAbove = max(0, visibleFrame.maxY - bottomForPanelAbove)

    if spaceBelow >= panelSize.height || spaceBelow >= spaceAbove {
        let height = min(panelSize.height, max(1, spaceBelow))
        return CursorPanelPosition(
            frame: NSRect(x: x, y: topForPanelBelow - height, width: panelSize.width, height: height),
            anchoredEdge: .top
        )
    }

    let height = min(panelSize.height, max(1, spaceAbove))
    return CursorPanelPosition(
        frame: NSRect(x: x, y: bottomForPanelAbove, width: panelSize.width, height: height),
        anchoredEdge: .bottom
    )
}

func panelFrameAtSavedPosition(
    anchorX: CGFloat,
    topY: CGFloat,
    panelSize: NSSize,
    visibleFrame: NSRect
) -> NSRect {
    let height = min(panelSize.height, visibleFrame.height)
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - height)
    let x = min(max(anchorX - panelSize.width / 2, visibleFrame.minX), maximumX)
    let y = min(max(topY - height, visibleFrame.minY), maximumY)
    return NSRect(x: x, y: y, width: panelSize.width, height: height)
}

func estimatedSubmittedMessageHeight(
    question: String,
    hasAttachments: Bool,
    contentWidth: CGFloat = 332
) -> CGFloat {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 3
    let textHeight: CGFloat
    if question.isEmpty {
        textHeight = 0
    } else {
        textHeight = ceil(
            (question as NSString).boundingRect(
                with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .paragraphStyle: paragraphStyle
                ]
            ).height
        )
    }
    let attachmentHeight: CGFloat = hasAttachments ? 48 : 0
    let contentSpacing: CGFloat = textHeight > 0 && hasAttachments ? 9 : 0
    return max(44, textHeight + attachmentHeight + contentSpacing + 20)
}

@MainActor
final class QueryPanelController: NSWindowController {
    private enum ResizeAnchor {
        case top(CGFloat)
        case bottom(CGFloat)
    }

    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private let panelWidth: CGFloat = 420
    private let topInset: CGFloat = 64
    private let savedAnchorXKey = "panelAnchorX"
    private let savedTopYKey = "panelTopY"
    private var resizeAnchor: ResizeAnchor?
    private var isApplyingContentFrame = false
    private var resizeGeneration = 0

    init(model: AppModel) {
        self.model = model
        let panel = QueryPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 138),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A native shadow follows the panel's rectangular backing store and leaves a
        // visible frame around transparent content. The SwiftUI surface draws its own.
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: QuickQueryView(model: model) { [weak self] in self?.closePanel() }
        )

        Publishers.Merge4(
            model.$editorHeight.dropFirst().map { _ in () },
            model.$followUpEditorHeight.dropFirst().map { _ in () },
            model.$draftAttachments.dropFirst().map { _ in () },
            model.$pendingAttachments.dropFirst().map { _ in () }
        )
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] in self?.resizeToContent(animated: true) }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            model.$conversation,
            model.$pendingQuestion,
            model.$phase,
            model.$isRevealingAnswer
        )
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToContent(animated: true) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func toggle() {
        if window?.isVisible == true {
            closePanel()
        } else {
            show()
        }
    }

    func show() {
        guard let panel = window else { return }
        resizeToContent(animated: false)
        positionForOpening(panel)
        savePosition(of: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .kvartzFocusQuery, object: nil)
    }

    private func closePanel() {
        if let panel = window { savePosition(of: panel) }
        model.reset()
        window?.orderOut(nil)
    }

    private func resizeToContent(animated: Bool) {
        guard let panel = window else { return }
        let targetHeight = preferredHeight()
        let oldFrame = panel.frame
        let screen = panel.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: panelWidth, height: 800)
        let fallbackTop = visibleFrame.maxY - topInset
        let anchor = panel.isVisible ? (resizeAnchor ?? .top(oldFrame.maxY)) : .top(fallbackTop)
        let target: NSRect
        switch anchor {
        case .top(let requestedTop):
            let anchoredTop = min(max(requestedTop, visibleFrame.minY + 1), visibleFrame.maxY)
            target = panelFrameKeepingTop(
                currentFrame: oldFrame,
                preferredHeight: targetHeight,
                width: panelWidth,
                topY: anchoredTop,
                visibleFrame: visibleFrame
            )
            resizeAnchor = .top(anchoredTop)
        case .bottom(let requestedBottom):
            let anchoredBottom = max(min(requestedBottom, visibleFrame.maxY - 1), visibleFrame.minY)
            target = panelFrameKeepingBottom(
                currentFrame: oldFrame,
                preferredHeight: targetHeight,
                width: panelWidth,
                bottomY: anchoredBottom,
                visibleFrame: visibleFrame
            )
            resizeAnchor = .bottom(anchoredBottom)
        }
        guard !oldFrame.equalTo(target) else { return }

        resizeGeneration += 1
        let generation = resizeGeneration
        isApplyingContentFrame = true

        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(target, display: true)
                },
                completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, generation == self.resizeGeneration else { return }
                        self.isApplyingContentFrame = false
                    }
                }
            )
        } else {
            panel.setFrame(target, display: true)
            isApplyingContentFrame = false
        }
    }

    private func preferredHeight() -> CGFloat {
        let isShowingInitialEditor = model.conversation.isEmpty
            && model.pendingQuestion.isEmpty
            && model.pendingAttachments.isEmpty
        let draftAttachmentHeight = model.draftAttachments.isEmpty
            ? 0
            : QuickQueryLayout.attachmentTrayHeight
        // The initial editor has two root-stack gaps. Once the conversation starts,
        // user messages live in the scroll view and only one root-stack gap remains.
        let base = isShowingInitialEditor
            ? QuickQueryLayout.rootChromeHeight
                + model.editorHeight
                + draftAttachmentHeight
                + QuickQueryLayout.activeEditorVerticalPadding
            : QuickQueryLayout.conversationChromeHeight
        switch model.phase {
        case .ready:
            return base + (model.configuredProviders.isEmpty ? 48 : 0)
        case .loading:
            if model.conversation.isEmpty {
                let pendingMessageHeight = estimatedSubmittedMessageHeight(
                    question: model.pendingQuestion,
                    hasAttachments: !model.pendingAttachments.isEmpty
                )
                // Preserve the existing 60pt loader/chrome allowance while sizing
                // the submitted message from its actual wrapped text and images.
                return base + pendingMessageHeight + 60
            }
            return conversationPanelHeight(base: base, additionalChrome: 88)
        case .error:
            if model.conversation.isEmpty { return min(base + 104, 380) }
            return conversationPanelHeight(
                base: base,
                additionalChrome: model.followUpEditorHeight + draftAttachmentHeight + 136
            )
        case .answer:
            let chrome = model.isRevealingAnswer
                ? 52
                : model.followUpEditorHeight + draftAttachmentHeight + 64
            return conversationPanelHeight(base: base, additionalChrome: chrome)
        }
    }

    private func conversationPanelHeight(base: CGFloat, additionalChrome: CGFloat) -> CGFloat {
        let widthInCharacters: CGFloat = 46
        let text = model.conversation
            .map { "\($0.question)\n\($0.answer)" }
            .joined(separator: "\n") + model.pendingQuestion
        let explicitLines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let wrappedLines = ceil(CGFloat(text.count) / widthInCharacters)
        let attachmentTurns = model.conversation.filter { !$0.attachments.isEmpty }.count
            + (model.pendingAttachments.isEmpty ? 0 : 1)
        let attachmentHeight = CGFloat(attachmentTurns * 62)
        let contentHeight = min(
            max(92, max(CGFloat(explicitLines), wrappedLines) * 24 + 28 + attachmentHeight),
            560
        )
        let screenHeight = window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        return min(base + contentHeight + additionalChrome, screenHeight - 64)
    }

    private func positionForOpening(_ panel: NSWindow) {
        if model.panelOpeningPosition == .lastPosition,
           positionAtLastLocation(panel) {
            return
        }

        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main else { return }

        let position = panelPositionNearCursor(
            cursor: cursor,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(position.frame, display: false)
        switch position.anchoredEdge {
        case .top:
            resizeAnchor = .top(position.frame.maxY)
        case .bottom:
            resizeAnchor = .bottom(position.frame.minY)
        }
    }

    private func positionAtLastLocation(_ panel: NSWindow) -> Bool {
        let defaults = UserDefaults.standard
        guard let savedX = defaults.object(forKey: savedAnchorXKey) as? Double,
              let savedTop = defaults.object(forKey: savedTopYKey) as? Double else {
            return false
        }
        let savedPoint = NSPoint(x: savedX, y: savedTop - 1)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(savedPoint) }) else {
            return false
        }
        let frame = panelFrameAtSavedPosition(
            anchorX: savedX,
            topY: savedTop,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(frame, display: false)
        resizeAnchor = .top(frame.maxY)
        return true
    }

    private func savePosition(of panel: NSWindow) {
        UserDefaults.standard.set(panel.frame.midX, forKey: savedAnchorXKey)
        UserDefaults.standard.set(panel.frame.maxY, forKey: savedTopYKey)
    }
}

extension QueryPanelController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel.isVisible else { return }
        guard !isApplyingContentFrame else { return }
        switch resizeAnchor {
        case .bottom:
            resizeAnchor = .bottom(panel.frame.minY)
        case .top, .none:
            resizeAnchor = .top(panel.frame.maxY)
        }
        savePosition(of: panel)
    }
}

extension Notification.Name {
    static let kvartzFocusQuery = Notification.Name("kvartzFocusQuery")
    static let kvartzFocusFollowUp = Notification.Name("kvartzFocusFollowUp")
}
