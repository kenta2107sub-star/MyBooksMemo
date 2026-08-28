import SwiftUI

/// SCR-02〜SCR-04の間の遷移先を表す（basic_design.md Section 3 画面遷移図）。
private enum RegistrationRoute: Hashable {
    case confirmation(BookDraft)
    case manualEntry(BookDraft)
}

/// 本登録フロー（SCR-01の「＋」から始まる一連の.sheet）をまとめるコンテナ。
/// basic_design.mdはSCR-02/03/04をそれぞれ独立画面として定義しているが、
/// いずれも「1回のsheet提示の中でpushして進む」フローのため、
/// このコンテナが内部にNavigationStackを持ち、入口（スキャン or 手入力）に応じて
/// ルート画面を出し分ける。「✕ キャンセル」はスタックの深さによらず
/// フロー全体（sheet）を閉じてSCR-01へ戻る（basic_design.mdの各画面の記述に準拠）。
struct RegistrationFlowView: View {
    enum EntryPoint: Identifiable {
        case scan
        case manual

        var id: Self { self }
    }

    let entryPoint: EntryPoint
    var onComplete: (Book) -> Void

    @State private var path: [RegistrationRoute] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: RegistrationRoute.self) { route in
                    switch route {
                    case .confirmation(let draft):
                        BookConfirmationView(
                            draft: draft,
                            onRegister: { finalDraft in complete(with: finalDraft) },
                            onEdit: { path.append(.manualEntry(draft)) },
                            onCancel: { dismiss() }
                        )
                    case .manualEntry(let draft):
                        ManualEntryFormView(
                            initialDraft: draft,
                            onSaved: { finalDraft in complete(with: finalDraft) },
                            onCancel: { dismiss() }
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        switch entryPoint {
        case .scan:
            BarcodeScannerView(
                onDetected: { draft in path.append(.confirmation(draft)) },
                onManualEntryFallback: { path.append(.manualEntry(BookDraft())) },
                onCancel: { dismiss() }
            )
        case .manual:
            ManualEntryFormView(
                onSaved: { finalDraft in complete(with: finalDraft) },
                onCancel: { dismiss() }
            )
        }
    }

    private func complete(with draft: BookDraft) {
        let book = Book(
            title: draft.title,
            author: draft.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "著者不明" : draft.author,
            coverImageData: draft.coverImageData,
            createdAt: .now
        )
        onComplete(book)
        dismiss()
    }
}
