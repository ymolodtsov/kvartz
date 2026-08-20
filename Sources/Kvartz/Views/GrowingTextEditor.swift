import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let onSubmit: () -> Void
    let onEscapeWhenEmpty: () -> Void
    var isEnabled = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onEscapeWhenEmpty = onEscapeWhenEmpty
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 17, weight: .regular)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 2, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.autoresizingMask = [.width]
        textView.string = text
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .kvartzFocusQuery,
            object: nil,
            queue: .main
        ) { [weak textView] _ in
            guard textView?.isEditable == true else { return }
            textView?.window?.makeFirstResponder(textView)
        }
        DispatchQueue.main.async { context.coordinator.recalculateHeight() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        if textView.string != text { textView.string = text }
        textView.onSubmit = onSubmit
        textView.onEscapeWhenEmpty = onEscapeWhenEmpty
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        if !isEnabled, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
        DispatchQueue.main.async { context.coordinator.recalculateHeight() }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.focusObserver { NotificationCenter.default.removeObserver(observer) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: NSTextView?
        var focusObserver: NSObjectProtocol?

        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
            let next = min(max(50, ceil(used)), 184)
            if abs(parent.height - next) > 0.5 { parent.height = next }
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscapeWhenEmpty: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Return), !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        if event.keyCode == UInt16(kVK_Escape), string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onEscapeWhenEmpty?()
            return
        }
        super.keyDown(with: event)
    }
}
