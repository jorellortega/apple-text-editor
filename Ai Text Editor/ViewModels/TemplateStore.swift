import Foundation
import Combine

final class TemplateStore: ObservableObject {
    @Published private(set) var templates: [TextTemplate] = []

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("templates.json")

        load()
    }

    // MARK: - Public API

    func addTemplate(name: String, body: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let template = TextTemplate(name: trimmed, body: body)
        templates.insert(template, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        // Manually remove indices without needing SwiftUI
        for index in offsets.sorted(by: >) {
            templates.remove(at: index)
        }
        save()
    }

    func markUsed(_ template: TextTemplate) {
        guard let idx = templates.firstIndex(of: template) else { return }
        templates[idx].lastUsedAt = Date()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            templates = try decoder.decode([TextTemplate].self, from: data)
        } catch {
            print("⚠️ Failed to load templates:", error)
            templates = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(templates)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("⚠️ Failed to save templates:", error)
        }
    }
}

