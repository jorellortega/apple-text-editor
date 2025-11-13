import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    /// Called when selection changes. Supplies the range and a CGRect anchor (or nil if no selection).
    var onSelectionChange: (NSRange, CGRect?) -> Void = { _, _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.delegate = context.coordinator
        tv.text = text
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.textColor = UIColor.label
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only push diffs to avoid publish-during-render warnings
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
            uiView.scrollRangeToVisible(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView
        init(_ parent: SelectableTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if newText != parent.text {
                // Publish after this render pass
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let newRange = textView.selectedRange
            // Compute an anchor rect for the selection if any
            var anchor: CGRect? = nil
            if let tr = textView.selectedTextRange, !tr.isEmpty {
                let rect = textView.firstRect(for: tr)
                // place the bar slightly above the selection
                anchor = CGRect(x: rect.midX, y: max(0, rect.minY - 8), width: 0, height: 0)
            }
            // Publish after this render pass
            DispatchQueue.main.async {
                if newRange != self.parent.selectedRange {
                    self.parent.selectedRange = newRange
                }
                self.parent.onSelectionChange(newRange, anchor)
            }
        }
    }
}

