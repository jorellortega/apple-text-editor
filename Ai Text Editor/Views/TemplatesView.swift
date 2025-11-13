import SwiftUI

struct TemplatesView: View {
    @EnvironmentObject var templateStore: TemplateStore
    @Environment(\.dismiss) private var dismiss

    let onSelect: (TextTemplate) -> Void
    let onSaveCurrentAsTemplate: () -> Void

    var body: some View {
        NavigationView {
            List {
                if templateStore.templates.isEmpty {
                    Section {
                        Text("No templates yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Templates") {
                        ForEach(templateStore.templates) { template in
                            Button {
                                onSelect(template)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.headline)

                                    Text(template.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete(perform: templateStore.delete)
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save Current") {
                        onSaveCurrentAsTemplate()
                    }
                }
            }
        }
    }
}

