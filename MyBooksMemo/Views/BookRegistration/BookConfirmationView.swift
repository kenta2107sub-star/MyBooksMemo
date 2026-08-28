import SwiftUI

// SCR-04：書誌情報確認画面。
// 対応FR：FR-01
// NDL APIから取得した想定の書誌情報（モックではSection 0のBook 1ダミー値固定）を確認し、
// そのまま登録するか、SCR-03（手入力）で修正するかを選ぶ。
struct BookConfirmationView: View {
    let draft: BookDraft
    var onRegister: (BookDraft) -> Void
    var onEdit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: BookTheme.sectionSpacing) {
            Spacer()

            BookCoverView(title: draft.title, imageData: draft.coverImageData)
                .frame(width: 140, height: 140 * 4 / 3)
                .bookCardShadow()

            VStack(spacing: 6) {
                Text(draft.title)
                    .font(BookTheme.heading())
                    .foregroundStyle(BookTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(draft.author)
                    .font(BookTheme.body)
                    .foregroundStyle(BookTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: BookTheme.spacingUnit) {
                Button("この本を登録する") { onRegister(draft) }
                    .buttonStyle(PrimaryButtonStyle())

                Button("情報を修正する") { onEdit() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(BookTheme.screenMargin)
        .background(BookTheme.background.ignoresSafeArea())
        .navigationTitle("書誌情報の確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("キャンセル") { onCancel() }
                    .foregroundStyle(BookTheme.primary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BookConfirmationView(
            draft: BookDraft(title: "嫌われる勇気", author: "岸見一郎, 古賀史健"),
            onRegister: { _ in },
            onEdit: {},
            onCancel: {}
        )
    }
}
