import Foundation
import SwiftUI
import Combine

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var selectedRange: NSRange = .init(location: 0, length: 0)
    @Published var selectionRect: CGRect? = nil

    @Published var isBusy: Bool = false
    @Published var customPrompt: String = ""
    @Published var lastSelectionInstruction: String? = nil

    // MARK: - Text helpers

    func replace(range: NSRange, with replacement: String) {
        guard let r = Range(range, in: text) else {
            // fallback: insert at location if range is invalid
            let loc = max(0, min(range.location, (text as NSString).length))
            if let idx = text.index(text.startIndex, offsetBy: loc, limitedBy: text.endIndex) {
                text.insert(contentsOf: replacement, at: idx)
            }
            return
        }
        text.replaceSubrange(r, with: replacement)
    }

    func selectionString() -> String? {
        guard selectedRange.length > 0, let r = Range(selectedRange, in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - AI actions

    func aiRewriteSelection(instruction: String) async {
        guard let selected = selectionString() else { return }
        isBusy = true
        defer { isBusy = false }
        lastSelectionInstruction = instruction

        do {
            var buffer = ""
            let stream = try await OpenAIClient.shared.streamText(
                mode: "rewrite",
                prompt: instruction,
                selection: selected,
                system: "You edit text precisely. Only return the rewritten selection without extra commentary."
            )
            for try await chunk in stream {
                buffer += chunk
            }
            replace(range: selectedRange, with: buffer)
        } catch {
            print("AI rewrite error:", error.localizedDescription)
        }
    }

    func regenerateSelection() async {
        guard let instruction = lastSelectionInstruction else { return }
        await aiRewriteSelection(instruction: instruction)
    }

    func aiContinue(prompt: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            var buffer = ""
            let stream = try await OpenAIClient.shared.streamText(
                mode: "continue",
                prompt: prompt,
                selection: (nil as String?),
                system: "You continue the user's document seamlessly in the same tone and style."
            )
            for try await chunk in stream {
                buffer += chunk
            }

            // Insert at caret (or after selection)
            let insertLocation = selectedRange.location + selectedRange.length
            let insertAt = NSRange(location: insertLocation, length: 0)
            replace(range: insertAt, with: buffer)
        } catch {
            print("AI continue error:", error.localizedDescription)
        }
    }
}

