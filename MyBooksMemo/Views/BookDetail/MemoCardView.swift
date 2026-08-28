import SwiftUI

// SCR-05：メモ一覧タブの1枚。付箋風の日付バッジ＋本文プレビュー（箇条書き）＋
// 右上の常設アイコン3つ（振り返り・編集・削除）で構成する。
// Listの行として使うため、カードらしい見た目（余白・角丸・陰影・方眼罫線）を自前で描く。
struct MemoCardView: View {
    let memo: MemoEntry
    /// 同一book・同一dateのConversationLog。nilの場合は振り返りアイコンを非活性にする（FR-08）
    let conversationLog: ConversationLog?
    /// FR-09：「今日のアドバイス」の表示状態。detailed_design.md 1-4によりモデルからは除去され、
    /// BookDetailViewModel.adviceDisplayState(for:)から呼び出し側（MemoListView）経由で渡される
    let adviceDisplayState: AdviceDisplayState
    /// 「今日のアドバイス」付箋の背景色（basic_design.md 5.2、2026-08-18更新：メモ一覧の表示順に
    /// 応じた4色ローテーション）。呼び出し側（MemoListView）がインデックスから算出して渡す
    var adviceBackgroundColor: Color = BookTheme.adviceColorRotation[0]
    var onReflect: (ConversationLog) -> Void
    var onEdit: () -> Void
    var onDeleteRequested: () -> Void
    /// FR-09：付箋内「再試行」ボタンタップ時に呼ばれる
    var onRetryAdvice: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: memo.date)
    }

    private var hasConversationLog: Bool { conversationLog != nil }

    var body: some View {
        // basic_design.md Section 4 SCR-05：メモ本文プレビューと「今日のアドバイス」付箋の間隔を
        // 24pt（8pt→16pt→24ptと段階的に拡大。2026-08-13再確定）にするため、カード内の縦spacingを24ptにする
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 8) {
                dateBadge

                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    iconButton(
                        systemName: "bubble.left.and.bubble.right",
                        isEnabled: hasConversationLog,
                        accessibilityLabel: hasConversationLog ? "AI対話ログを振り返る" : "この日はAI対話ログがありません"
                    ) {
                        if let conversationLog {
                            onReflect(conversationLog)
                        }
                    }

                    iconButton(systemName: "pencil", accessibilityLabel: "このメモを編集") {
                        onEdit()
                    }

                    iconButton(systemName: "trash", accessibilityLabel: "このメモを削除") {
                        onDeleteRequested()
                    }
                }
            }

            contentPreview

            adviceNote
                // basic_design.md：付箋の横幅はカード幅いっぱいに広げず、カード内側の左右それぞれに
                // 12ptの余白を追加した幅にする（付箋がカードより一回り小さく見えるように。2026-08-13再確定）
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .notebookCardStyle()
    }

    // MARK: - 本文プレビュー（箇条書き、2026-08-18更新・再調整）

    // basic_design.md Section 4 SCR-05：`contentItems`の各要素を先頭に「・」を付けた箇条書きで
    // リスト表示する。各項目は省略せず全文表示し、横幅を超える場合は折り返して複数行表示する
    // （省略記号による切り詰めは行わない）。カード全体の高さは項目数・文字量に応じて可変とする
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(memo.contentItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("・")
                        .font(BookTheme.body)
                        .foregroundStyle(BookTheme.textPrimary)
                    Text(item)
                        .font(BookTheme.body)
                        .foregroundStyle(BookTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 「今日のアドバイス」付箋（FR-09。開閉トグルを持たず常時表示する）

    // basic_design.md Section 4 SCR-05・5.4.6：日付バッジと傾き・テープ留め装飾は共通のビジュアル
    // デザインを踏襲するが、角丸は日付バッジ4ptとは別に10ptとする（メモ本文を主役にするため付箋
    // 自体の主張をやや弱める。2026-08-13追加）。配色は日付バッジと差別化し、背景はメモ一覧の表示順
    // に応じた4色ローテーション（`adviceBackgroundColor`、呼び出し側から渡される。2026-08-18更新。
    // 従来の単色`#A8825A`から変更。5.2参照）、文字は白のまま（いずれもAA基準4.5:1をクリア）。
    // 綴じ穴・紙テクスチャはカード全体にすでに適用済みのため付箋自体には重ねない。
    private var adviceNote: some View {
        // 実機確認により見出し・本文とも中央揃えに変更（従来は左揃え。2026-08-13再調整）
        VStack(alignment: .center, spacing: 4) {
            // 見出しラベル：caption相当・roundedデザイン（丸ゴシック）。5.3参照
            Text("今日のアドバイス")
                .font(BookTheme.button(.caption))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            adviceBody
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // 内側パディング：左右は先行の縮小値（10pt）を維持、上下のみ実機確認で窮屈だったため再拡大
        .stickyNoteBadgeStyle(backgroundColor: adviceBackgroundColor, cornerRadius: 10, horizontalPadding: 10, verticalPadding: 14)
        // 日付バッジ（幅の狭い矩形）と異なり付箋はカード幅いっぱいに広がるため、
        // 同じ-1.5度では傾きが目立ちすぎる。より控えめな-1度にする（5.4.6の-2〜2度の範囲内）
        .tapedBadgeStyle(rotation: -1)
    }

    @ViewBuilder
    private var adviceBody: some View {
        // 本文（アドバイス文章／空状態文言／スピナー横テキスト／エラー文言）はいずれも
        // subheadline相当・roundedデザイン（丸ゴシック）で統一する（5.3参照。footnote相当から
        // 1段階拡大。2026-08-13再々調整）。下線は「生成成功」のアドバイス本文にのみ付与し、
        // 未生成・生成中・生成失敗の3状態には付けない
        switch adviceDisplayState {
        case .notTriggered:
            // basic_design.md Section 4 SCR-05：未生成状態の文言をそのまま使用（下線なし）
            Text("今日のアドバイスはまだありません")
                .font(BookTheme.button(.subheadline))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("生成中…")
                    .font(BookTheme.button(.subheadline))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .success(let text):
            // 4状態のうち下線が付くのはこの「生成成功」のみ
            Text(text)
                .font(BookTheme.button(.subheadline))
                .foregroundStyle(.white)
                .underline()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

        case .failed(let reason):
            VStack(alignment: .center, spacing: 8) {
                // ERR-15〜17（basic_design.md Section 7）の文言をそのまま使用（下線なし）
                Text(reason.message)
                    .font(BookTheme.button(.subheadline))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if reason.showsRetryButton {
                    // basic_design.md：既存のSecondaryButtonStyle（背景ページホワイト・文字ブックブラウン・
                    // 角丸12pt）はそのまま使用するが、横幅はテキスト幅に合わせて縮小し、
                    // 垂直パディングも縮小して高さをコンパクトにする（色・角丸は変更しない）。
                    // SecondaryButtonStyle自体には水平パディングがなく`.frame(maxWidth: .infinity)`のみで
                    // 幅を確保しているため、ラベル側に水平パディングを持たせてから.fixedSizeで
                    // テキスト幅に固定する
                    Button {
                        onRetryAdvice()
                    } label: {
                        Text("再試行")
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(SecondaryButtonStyle(verticalPadding: 8))
                    .fixedSize(horizontal: true, vertical: false)
                    // 見た目のパディングは縮小しつつ、タップ領域は44pt以上を維持する
                    // （アクセシビリティガードレール。視覚上のピルはコンパクトなまま、
                    // 実際のヒットテスト領域だけをこのframeで拡張する）
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // basic_design.md Section 4 SCR-05：付箋風の日付バッジ（テープ留め風装飾つき、5.4.6②）。
    // 背景ブックブラウン×文字白でコントラスト比約5.84:1（AA基準4.5:1をクリア）。
    // 2026-08-13再確定：従来のアンバー背景×インクブラウン文字から、「今日のアドバイス」付箋と
    // 配色を入れ替えた（5.2参照）。
    private var dateBadge: some View {
        Text(dateText)
            .font(BookTheme.caption)
            .foregroundStyle(.white)
            .stickyNoteBadgeStyle(backgroundColor: BookTheme.primary)
            .tapedBadgeStyle()
    }

    private func iconButton(
        systemName: String,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? BookTheme.primary : BookTheme.textSecondary.opacity(0.35))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("振り返り活性（対話ログあり）") {
    let book = PreviewData.makeBooks()[1]
    return MemoCardView(
        memo: book.memoEntries[1],
        conversationLog: book.conversationLogs.first,
        adviceDisplayState: .success(book.memoEntries[1].dailyAdvice ?? ""),
        onReflect: { _ in },
        onEdit: {},
        onDeleteRequested: {},
        onRetryAdvice: {}
    )
    .padding()
    .background(BookTheme.background)
}

#Preview("振り返り非活性（対話ログなし・アドバイス生成失敗）") {
    let book = PreviewData.makeBooks()[1]
    return MemoCardView(
        memo: book.memoEntries[0],
        conversationLog: nil,
        adviceDisplayState: .failed(.apiFailure),
        onReflect: { _ in },
        onEdit: {},
        onDeleteRequested: {},
        onRetryAdvice: {}
    )
    .padding()
    .background(BookTheme.background)
}

#Preview("今日のアドバイス：生成中") {
    let book = PreviewData.makeBooks()[1]
    return MemoCardView(
        memo: book.memoEntries[2],
        conversationLog: nil,
        adviceDisplayState: .generating,
        onReflect: { _ in },
        onEdit: {},
        onDeleteRequested: {},
        onRetryAdvice: {}
    )
    .padding()
    .background(BookTheme.background)
}

#Preview("今日のアドバイス：未生成") {
    let book = PreviewData.makeBooks()[1]
    let memo = book.memoEntries[0]
    return MemoCardView(
        memo: memo,
        conversationLog: nil,
        adviceDisplayState: .notTriggered,
        onReflect: { _ in },
        onEdit: {},
        onDeleteRequested: {},
        onRetryAdvice: {}
    )
    .padding()
    .background(BookTheme.background)
}
