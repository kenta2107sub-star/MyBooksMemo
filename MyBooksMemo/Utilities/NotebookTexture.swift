import SwiftUI

// basic_design.md 5.4.6（Phase 4モックレビュー追加フィードバック）：
// 「リング綴じノート風＋ざらついた紙質感」の演出。5.4.5の方眼罫線に加えて重ねる、
// あくまで追加の装飾レイヤー。既存のカラーパレット・カード角丸16pt・カード陰影・
// 方眼罫線の不透明度は変更しない。
//
// ① 綴じ穴（RingBindingHole）　② テープ留め風バッジ（stickyNoteBadgeStyle + tapedBadgeStyle）
// ③ 紙のざらつき（PaperNoisePattern）　の3要素をここにまとめる。

// MARK: - ① リング綴じの綴じ穴

/// カード左端に配置する「穴」1つ分。ページボーダーの縁取り＋内側の明暗グラデーションで
/// くぼんで見える表現にする（SwiftUIに真のinner shadowはないため、上が暗く下が明るい
/// グラデーションで疑似的な凹み感を出す）。
private struct RingBindingHole: View {
    var diameter: CGFloat = 9

    var body: some View {
        Circle()
            .fill(BookTheme.border.opacity(0.4))
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                BookTheme.textPrimary.opacity(0.22),
                                Color.clear,
                                BookTheme.cardBackground.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Circle().strokeBorder(BookTheme.border.opacity(0.85), lineWidth: 1)
            )
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

extension View {
    /// basic_design.md 5.4.6①：カード上部・下部（カード左端から6pt内側）に綴じ穴を1つずつ配置する。
    /// 呼び出し側の`.clipShape`より前に適用し、はみ出しをクリップさせること
    /// （`notebookCardStyle()`内で正しい順序に組み込み済み）。
    func ringBindingHoles(diameter: CGFloat = 9) -> some View {
        self
            .overlay(alignment: .topLeading) {
                RingBindingHole(diameter: diameter)
                    .padding(.leading, 6)
                    .padding(.top, 10)
            }
            .overlay(alignment: .bottomLeading) {
                RingBindingHole(diameter: diameter)
                    .padding(.leading, 6)
                    .padding(.bottom, 10)
            }
    }
}

// MARK: - ③ ざらついた紙のテクスチャ

/// 決定的な擬似乱数生成器。Canvasの`body`は再描画のたびに呼ばれるため、
/// 毎回`Double.random`で新しい点を打つとノイズがちらついて見えてしまう。
/// 固定シードのLCG（線形合同法）で同じ点列を再現し、テクスチャを静止させる。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// プライマリカラー系統の極薄ドットパターン（basic_design.md 5.4.6③）。
/// カード背景・方眼罫線の上、コンテンツの下に重ねる追加レイヤー。
struct PaperNoisePattern: View {
    var color: Color = BookTheme.primary.opacity(0.04)
    var dotCount: Int = 220

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 20260807)
            guard size.width > 0, size.height > 0 else { return }
            for _ in 0..<dotCount {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let d = CGFloat.random(in: 0.5...1.4, using: &rng)
                let rect = CGRect(x: x, y: y, width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ② テープ留め風の日付バッジ

extension View {
    /// basic_design.md Section 4 SCR-05：付箋風バッジ本体（既定角丸4pt＝日付バッジ）。
    /// 「今日のアドバイス」付箋（FR-09）はブックブラウン背景・白文字（コントラスト比約5.84:1、
    /// Section 5.2参照）・角丸10pt（Section 5.4、日付バッジの4ptとは別定義。2026-08-13追加）に
    /// するため、`backgroundColor`・`cornerRadius`を上書きする。呼び出し側で文字色とフォントを
    /// 設定してから使うこと。
    func stickyNoteBadgeStyle(
        backgroundColor: Color = BookTheme.secondary,
        cornerRadius: CGFloat = 4,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// basic_design.md 5.4.6②：付箋風バッジに「テープ留め」の質感を加える。
    /// バッジ本体を-2〜2度の範囲でわずかに傾け、上端に半透明の白いテープ状矩形を
    /// バッジとは異なる角度で重ねる。文字色・コントラスト比は変更しない。
    /// テープはバッジ上端のみにかかり、中央のテキストは隠さない。
    /// `rotation`は日付バッジ既定-1.5度。「今日のアドバイス」付箋は幅が広く同じ角度だと
    /// 傾きが目立ちすぎるため、呼び出し側でより控えめな値を指定してよい。
    func tapedBadgeStyle(rotation: Double = -1.5) -> some View {
        self
            .rotationEffect(.degrees(rotation))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 28, height: 9)
                    .rotationEffect(.degrees(5))
                    .offset(y: -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

#Preview("綴じ穴・紙テクスチャ・テープ留めバッジ") {
    VStack(alignment: .leading, spacing: 24) {
        Text("2026/07/28")
            .font(BookTheme.caption)
            .foregroundStyle(BookTheme.textPrimary)
            .stickyNoteBadgeStyle()
            .tapedBadgeStyle()

        Text("方眼罫線＋紙テクスチャ＋綴じ穴のプレビュー")
            .font(BookTheme.body)
            .foregroundStyle(BookTheme.textPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notebookCardStyle()
    }
    .padding()
    .background(BookTheme.background)
}
