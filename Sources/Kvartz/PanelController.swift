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

@MainActor
final class QueryPanelController: NSWindowController {
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private let panelWidth: CGFloat = 420
    private let topInset: CGFloat = 64
    private let savedAnchorXKey = "panelAnchorX"
    private let savedTopYKey = "panelTopY"
    private var resizeAnchorTopY: CGFloat?
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

        Publishers.Merge(
            model.$editorHeight.dropFirst().map { _ in () },
            model.$followUpEditorHeight.dropFirst().map { _ in () }
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
        resizeAnchorTopY = panel.frame.maxY
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .kvartzFocusQuery, object: nil)
    }

    private func closePanel() {
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
        let requestedTop = panel.isVisible ? (resizeAnchorTopY ?? oldFrame.maxY) : fallbackTop
        let anchoredTop = min(requestedTop, visibleFrame.maxY)
        let target = panelFrameKeepingTop(
            currentFrame: oldFrame,
            preferredHeight: targetHeight,
            width: panelWidth,
            topY: anchoredTop,
            visibleFrame: visibleFrame
        )

        resizeAnchorTopY = anchoredTop
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
        let queryAreaHeight = model.conversation.isEmpty && model.pendingQuestion.isEmpty
            ? model.editorHeight + QuickQueryLayout.activeEditorVerticalPadding
            : QuickQueryLayout.submittedQueryHeight
        // Includes the outer and inner 12pt insets, the 30pt header, and both
        // 6pt root-stack gaps. The query area's own height is added separately.
        let base = QuickQueryLayout.rootChromeHeight + queryAreaHeight
        switch model.phase {
        case .ready:
            return base + (model.configuredProviders.isEmpty ? 48 : 0)
        case .loading:
            if model.conversation.isEmpty { return base + 58 }
            return conversationPanelHeight(base: base, additionalChrome: 88)
        case .error:
            if model.conversation.isEmpty { return min(base + 104, 380) }
            return conversationPanelHeight(base: base, additionalChrome: model.followUpEditorHeight + 136)
        case .answer:
            let chrome = model.isRevealingAnswer ? 52 : model.followUpEditorHeight + 64
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
        let contentHeight = min(max(92, max(CGFloat(explicitLines), wrappedLines) * 24 + 28), 560)
        let screenHeight = window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        return min(base + contentHeight + additionalChrome, screenHeight - 64)
    }

    private func positionForOpening(_ panel: NSWindow) {
        let defaults = UserDefaults.standard
        let savedX = defaults.object(forKey: savedAnchorXKey) as? Double
        let savedTop = defaults.object(forKey: savedTopYKey) as? Double
        let savedPoint = savedX.flatMap { x in savedTop.map { NSPoint(x: x, y: $0 - 1) } }
        guard let screen = savedPoint.flatMap({ point in NSScreen.screens.first { $0.frame.contains(point) } })
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main else { return }

        var frame = panel.frame
        if let savedX, let savedTop {
            frame.origin.x = savedX - frame.width / 2
            frame.origin.y = savedTop - frame.height
        } else {
            frame.origin.x = screen.visibleFrame.midX - frame.width / 2
            frame.origin.y = screen.visibleFrame.maxY - topInset - frame.height
        }
        frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        panel.setFrame(frame, display: false)
        resizeAnchorTopY = frame.maxY
    }
}

extension QueryPanelController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel.isVisible else { return }
        guard !isApplyingContentFrame else { return }
        resizeAnchorTopY = panel.frame.maxY
        UserDefaults.standard.set(panel.frame.midX, forKey: savedAnchorXKey)
        UserDefaults.standard.set(panel.frame.maxY, forKey: savedTopYKey)
    }
}

extension Notification.Name {
    static let kvartzFocusQuery = Notification.Name("kvartzFocusQuery")
    static let kvartzFocusFollowUp = Notification.Name("kvartzFocusFollowUp")
}
