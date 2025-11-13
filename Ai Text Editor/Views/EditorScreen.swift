import SwiftUI

struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var templateStore: TemplateStore
    @Binding var document: TextDoc

    @StateObject private var vm = EditorViewModel()
    @State private var showTemplates = false
    @State private var showSaveAsTemplate = false
    @State private var newTemplateName = ""
    @State private var useDark = false

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Top header + main controls
            VStack(alignment: .leading, spacing: 8) {

                // Row 1: Title + primary actions (Export / Light)
                HStack(spacing: 8) {
                    Text("AI Text Editor")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    ToolbarPillButton(
                        title: "Export",
                        systemName: "square.and.arrow.up"
                    ) {
                        // TODO: hook up export later
                    }

                    ToolbarPillButton(
                        title: useDark ? "Light" : "Dark",
                        systemName: useDark ? "sun.max" : "moon"
                    ) {
                        useDark.toggle()
                    }
                }

                // Row 2: Navigation + Save (Documents / Templates / Save)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ToolbarPillButton(
                            title: "Documents",
                            systemName: "folder"
                        ) {
                            dismiss() // back to document browser
                        }

                        ToolbarPillButton(
                            title: "Templates",
                            systemName: "doc.on.doc"
                        ) {
                            showTemplates = true
                        }

                        ToolbarPillButton(
                            title: "Save",
                            systemName: "square.and.arrow.down"
                        ) {
                            document.text = vm.text
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // MARK: Formatting row (visual only for now)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Menu {
                        Button("Sans Serif", action: {})
                        Button("Serif", action: {})
                        Button("Monospace", action: {})
                    } label: {
                        Chip(label: "Sans Serif", systemName: "textformat")
                    }

                    Menu {
                        Button("Small", action: {})
                        Button("Medium", action: {})
                        Button("Large", action: {})
                        Button("Title", action: {})
                    } label: {
                        Chip(label: "Large", systemName: "textformat.size")
                    }

                    Chip(label: "B", systemName: "bold") {}
                    Chip(label: "I", systemName: "italic") {}
                    Chip(label: "U", systemName: "underline") {}

                    Chip(label: "", systemName: "text.alignleft") {}
                    Chip(label: "", systemName: "text.aligncenter") {}
                    Chip(label: "", systemName: "text.alignright") {}
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground).opacity(0.8))

            // MARK: Editor
            ZStack(alignment: .topLeading) {
                SelectableTextView(
                    text: $vm.text,
                    selectedRange: $vm.selectedRange,
                    onSelectionChange: { range, rect in
                        // Safe to mutate (SelectableTextView calls this on the next runloop turn)
                        vm.selectedRange = range
                        vm.selectionRect = rect
                    }
                )
                .onChange(of: vm.text) { _, newValue in
                    document.text = newValue
                }
                .onAppear { vm.text = document.text }

                if vm.isBusy {
                    ProgressView().controlSize(.regular)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding()
                }
            }
        }
        // MARK: Bottom area: Selection toolbar + AI prompt bar
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if vm.selectedRange.length > 0 {
                    SelectionActionBar(
                        onRegenerate: {
                            Task { await vm.regenerateSelection() }
                        },
                        onImprove: {
                            Task {
                                await vm.aiRewriteSelection(
                                    instruction:
"""
Correct only grammar, spelling, and basic punctuation errors. Keep the wording and tone as close to the original as possible. Preserve all existing line breaks and blank lines; do not merge paragraphs or change the surrounding spacing. Return only the corrected text, with no quotes, brackets, markers, or additional commentary.
"""
                                )
                            }
                        },
                        onShorten: {
                            Task {
                                await vm.aiRewriteSelection(
                                    instruction:
"""
Rewrite this so it is more concise but keeps all important information and the same tone. Preserve the current paragraph and line-break structure; do not remove blank lines between paragraphs or change surrounding spacing. Return only the rewritten text, with no quotes, brackets, markers, or additional commentary.
"""
                                )
                            }
                        },
                        onExpand: {
                            Task {
                                await vm.aiRewriteSelection(
                                    instruction:
"""
Expand this text with more detail and explanation while keeping the same tone and key ideas. Preserve all existing line breaks and blank lines so the spacing between this and surrounding paragraphs stays the same. Return only the expanded text, with no quotes, brackets, markers, or additional commentary.
"""
                                )
                            }
                        },
                        onClose: {
                            vm.selectionRect = nil
                            vm.selectedRange = NSRange(
                                location: vm.selectedRange.location + vm.selectedRange.length,
                                length: 0
                            )
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }

                PromptBar(
                    text: $vm.customPrompt,
                    isBusy: vm.isBusy,
                    onGenerate: {
                        let hasSelection = vm.selectedRange.length > 0
                        Task {
                            if hasSelection {
                                // Custom instruction on highlighted text
                                await vm.aiRewriteSelection(instruction: vm.customPrompt)
                            } else {
                                // No selection: continue writing after the cursor
                                await vm.aiContinue(prompt: vm.customPrompt)
                            }
                            vm.customPrompt = ""
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatesView(
                onSelect: { template in
                    // Insert template text at the current selection/caret
                    let range = vm.selectedRange
                    vm.replace(range: range, with: template.body)
                    templateStore.markUsed(template)
                },
                onSaveCurrentAsTemplate: {
                    newTemplateName = ""
                    showSaveAsTemplate = true
                }
            )
            .environmentObject(templateStore)
        }
        .alert("Save as template",
               isPresented: $showSaveAsTemplate) {
            TextField("Template name", text: $newTemplateName)

            Button("Save") {
                templateStore.addTemplate(name: newTemplateName, body: vm.text)
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save the current document as a reusable template.")
        }
        .preferredColorScheme(useDark ? .dark : .light)
    }
}

// MARK: - Floating action bar

struct SelectionActionBar: View {
    var onRegenerate: () -> Void
    var onImprove: () -> Void
    var onShorten: () -> Void
    var onExpand: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ActionChip(label: "Regenerate", systemName: "arrow.triangle.2.circlepath", action: onRegenerate)
            ActionChip(label: "Improve",    systemName: "wand.and.stars",            action: onImprove)
            ActionChip(label: "Shorten",    systemName: "arrow.left.and.right",      action: onShorten)
            ActionChip(label: "Expand",     systemName: "arrow.up.right.square",     action: onExpand)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12)
    }
}

struct ActionChip: View {
    var label: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                if !label.isEmpty { Text(label) }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var label: String
    var systemName: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                if !label.isEmpty { Text(label) }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ToolbarPillButton: View {
    var title: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom prompt bar

struct PromptBar: View {
    @Binding var text: String
    var isBusy: Bool
    var onGenerate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
            TextField("Describe what you want to write…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)

            Button {
                onGenerate()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text(isBusy ? "Working…" : "Generate")
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.tint, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

