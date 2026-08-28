import SwiftUI
import UIKit

extension Animation {
    /// 「視差効果を減らす」（prefers-reduced-motion相当）がオンの場合はアニメーションを無効化する。
    /// basic_design.md 5.6の「独自の凝った演出は追加しない」という静かなトーンとも整合する形で、
    /// スワイプ削除・タブ切り替え・要約更新のクロスフェードに共通適用する。
    static func reduceMotionAware(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}

// basic_design.md Section 5「デザイン方針」で確定した値をそのまま定数化する。
// アプリの本質＝「本から得た気づきを、自分の言葉で日常の行動に変換する、
// 静かで丁寧な対話の時間」に沿い、生成り紙のような温かい背景と
// 本の背表紙を思わせる落ち着いた茶系のアクセントで統一する。

extension Color {
    /// HEX文字列からColorを生成する（Assets.xcassetsにカラーセットを増やさず
    /// Section 5.2の値をコード上で一元管理するための小さなユーティリティ）
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

enum BookTheme {
    // MARK: - カラーパレット（basic_design.md 5.2）

    /// 背景（ベース）：ページクリーム
    static let background = Color(hex: "FBF3E7")
    /// カード背景：ページホワイト
    static let cardBackground = Color(hex: "FFFDF8")
    /// プライマリ：ブックブラウン
    static let primary = Color(hex: "8B5A2B")
    /// セカンダリ：ブックマークアンバー
    static let secondary = Color(hex: "D98B3D")
    /// 本文テキスト：インクブラウン
    static let textPrimary = Color(hex: "3A2E25")
    /// 補助テキスト：フェイドブラウン
    /// basic_design.md 5.2で `#8C7B6B` から更新（背景クリームで5.99:1、カード背景で6.48:1。WCAG AA 4.5:1を確保）
    static let textSecondary = Color(hex: "6B5A4A")
    /// 罫線：ページボーダー
    static let border = Color(hex: "E6D5BE")
    /// エラー・削除：ブリックレッド
    static let error = Color(hex: "B3452C")

    /// 「今日のアドバイス」付箋の背景色ローテーション（basic_design.md 5.2、2026-08-18更新）。
    /// メモ一覧の表示順（日付降順のインデックス、0始まり）に応じて4色を周期的に適用する。
    /// 従来の単色`#A8825A`（アドバイスベージュ）から変更。文字は白のまま、いずれもコントラスト比
    /// AA基準4.5:1をクリア（セージグリーン5.10:1／インディゴネイビー8.81:1／
    /// ディープティール6.20:1／プラムモーブ7.31:1）
    static let adviceColorRotation: [Color] = [
        Color(hex: "5B7553"), // セージグリーン（1件目・5件目・9件目…）
        Color(hex: "3C4A6B"), // インディゴネイビー（2件目・6件目・10件目…）
        Color(hex: "2D6A6A"), // ディープティール（3件目・7件目・11件目…）
        Color(hex: "6B4C6B")  // プラムモーブ（4件目・8件目・12件目…）
    ]

    /// メモ一覧のインデックス（0始まり）に応じたローテーション色を返す（4件周期でループする）
    static func adviceColor(at index: Int) -> Color {
        adviceColorRotation[index % adviceColorRotation.count]
    }

    // MARK: - フォント方針（basic_design.md 5.3）

    /// 見出し・本のタイトル表示
    static func heading(_ style: Font.TextStyle = .title3) -> Font {
        .system(style, design: .serif)
    }
    /// ボタンラベル・タブ・数値表示
    static func button(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .rounded)
    }
    /// 本文（メモ本文・チャット・要約文）
    static let body = Font.system(.body, design: .default)
    /// キャプション・日付
    static let caption = Font.system(.caption, design: .default)
    /// 「今日のアドバイス」付箋の本文（basic_design.md 5.4.6、2026-08-13追加）
    static let footnote = Font.system(.footnote, design: .default)

    // MARK: - 角丸・余白・陰影（basic_design.md 5.4）

    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 12
    static let textFieldCornerRadius: CGFloat = 10
    static let chatBubbleCornerRadius: CGFloat = 18

    static let spacingUnit: CGFloat = 8
    static let screenMargin: CGFloat = 16
    static let sectionSpacing: CGFloat = 28

    /// カード陰影：プライマリカラーの8%程度の不透明度・blur 8pt・y-offset 2pt
    static let shadowColor = primary.opacity(0.08)
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2
}

extension View {
    /// basic_design.md 5.4のカード陰影を統一的に適用する
    func bookCardShadow() -> some View {
        self.shadow(color: BookTheme.shadowColor, radius: BookTheme.shadowRadius, x: 0, y: BookTheme.shadowY)
    }
}

/// プライマリボタン（ブックブラウン地・白文字・角丸12pt）
/// basic_design.md 5.6：タップ時は標準ButtonStyleによるわずかな縮小フィードバック（scaleEffect 0.97程度）
struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BookTheme.button())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? BookTheme.primary.opacity(0.35) : BookTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// セカンダリボタン（アウトライン・ブックブラウン文字）。
/// `verticalPadding`は既定14pt。「今日のアドバイス」付箋内の「再試行」ボタン（FR-09）のみ、
/// 背景色・文字色・角丸12ptは変更せず高さだけコンパクトにするため小さい値を指定する
/// （2026-08-13追加・実機確認による再調整）。
struct SecondaryButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BookTheme.button())
            .foregroundStyle(BookTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(BookTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius, style: .continuous)
                    .strokeBorder(BookTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
