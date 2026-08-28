import SwiftUI
import SwiftData

@main
struct MyBooksMemoApp: App {
    let modelContainer: ModelContainer

    init() {
        NavigationBarAppearanceConfigurator.configure()
        do {
            modelContainer = try ModelContainer(
                for: Schema([Book.self, MemoEntry.self, ConversationLog.self])
            )
        } catch {
            fatalError("ModelContainerの初期化に失敗しました: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            BookshelfView(modelContext: modelContainer.mainContext)
                // basic_design.md Section 0：ダークモード対応は不要。ライトモードに固定する
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
