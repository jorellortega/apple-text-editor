import SwiftUI

@main
struct AiTextEditorApp: App {
    @StateObject private var templateStore = TemplateStore()

    var body: some Scene {
        DocumentGroup(newDocument: TextDoc()) { file in
            EditorScreen(document: file.$document)
                .environmentObject(templateStore)
        }
    }
}
