import AppKit
import Combine
import CoreBluetooth
import SwiftUI

struct OnboardingTranscriptFocusSnapshot: Equatable {
    let editorMounted: Bool
    let windowKey: Bool
    let firstResponder: Bool
}

struct OnboardingTranscriptEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let isActive: Bool
    let commitRequest: Int
    let onTextStateChanged: (String) -> Void
    let onFocusStateChanged: (OnboardingTranscriptFocusSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = OnboardingTranscriptScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: OnboardingTranscriptEditor
        private weak var scrollView: OnboardingTranscriptScrollView?
        private weak var textView: NSTextView?
        private var appliedFocusRequest: Int?
        private var appliedCommitRequest: Int?
        private var lastPublishedSnapshot: OnboardingTranscriptFocusSnapshot?

        init(parent: OnboardingTranscriptEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFocusChanged),
                name: NSWindow.didBecomeKeyNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFocusChanged),
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        fileprivate func attach(scrollView: OnboardingTranscriptScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            scrollView.didMoveToWindowHandler = { [weak self] in
                self?.applyFocusRequestIfPossible()
                self?.publishFocusSnapshot()
            }
            applyFocusRequestIfPossible()
            publishFocusSnapshot()
        }

        func update(parent: OnboardingTranscriptEditor) {
            self.parent = parent
            if appliedCommitRequest != parent.commitRequest {
                appliedCommitRequest = parent.commitRequest
                commitMarkedTextIfNeeded()
            }
            if let textView,
               !textView.hasMarkedText(),
               textView.string != parent.text {
                textView.string = parent.text
            }
            applyFocusRequestIfPossible()
            publishFocusSnapshot()
        }

        func detach() {
            textView?.delegate = nil
            scrollView?.didMoveToWindowHandler = nil
            scrollView = nil
            textView = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let updatedText = textView.string
            parent.onTextStateChanged(updatedText)
            guard parent.text != updatedText else { return }
            parent.text = updatedText
        }

        func textDidBeginEditing(_ notification: Notification) {
            publishFocusSnapshot()
        }

        func textDidEndEditing(_ notification: Notification) {
            publishFocusSnapshot()
        }

        @objc private func windowFocusChanged(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === scrollView?.window else { return }
            applyFocusRequestIfPossible()
            publishFocusSnapshot()
        }

        private func applyFocusRequestIfPossible() {
            guard parent.isActive,
                  appliedFocusRequest != parent.focusRequest,
                  let textView,
                  let window = textView.window else { return }
            if window.makeFirstResponder(textView) {
                appliedFocusRequest = parent.focusRequest
            }
        }

        private func commitMarkedTextIfNeeded() {
            guard let textView, textView.hasMarkedText() else { return }
            textView.unmarkText()
            let committedText = textView.string
            parent.onTextStateChanged(committedText)
            if parent.text != committedText {
                parent.text = committedText
            }
            AppLogger.shared.write(
                "ONBOARDING TRANSCRIPT marked_text_commit=true"
            )
        }

        private func publishFocusSnapshot() {
            let snapshot = OnboardingTranscriptFocusSnapshot(
                editorMounted: textView?.window != nil,
                windowKey: textView?.window?.isKeyWindow == true,
                firstResponder: textView?.window?.firstResponder === textView
            )
            guard snapshot != lastPublishedSnapshot else { return }
            lastPublishedSnapshot = snapshot
            DispatchQueue.main.async { [weak self] in
                self?.parent.onFocusStateChanged(snapshot)
            }
        }
    }
}

private final class OnboardingTranscriptScrollView: NSScrollView {
    var didMoveToWindowHandler: (() -> Void)?

    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }
        var frame = textView.frame
        let targetWidth = contentSize.width
        let targetHeight = max(frame.height, contentSize.height)
        guard frame.width != targetWidth || frame.height != targetHeight else { return }
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        textView.frame = frame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didMoveToWindowHandler?()
    }
}
