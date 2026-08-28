import SwiftUI

// basic_design.md 5.4.5（Phase 4モックレビューフィードバックにより追加）：
// 方眼罫線背景（グリッド質感）。SCR-05のMemoCardView・SCR-08の要約カード／空状態カード・
// SCR-06のテキストエリアに、方眼ノートのような背景質感を持たせる。カード背景色（ページホワイト）・
// カード角丸・カード陰影（5.4）はそのまま維持し、方眼罫線はその上に重ねる追加の背景レイヤーとする。
//
// 2026-08-07 追加フィードバック：不透明度18%では実機でほとんど視認できなかったため、
// SCR-05／SCR-08は40〜50%（既定45%）に引き上げて「はっきり見える方眼ノート風」にする。
// SCR-06のTextEditorは入力文字の可読性を最優先し、やや薄い値（既定28%）を使う
// （5.4.5「入力文字が読みにくくなる場合はSCR-05／SCR-08より薄めの値まで下げてよい」に基づく）。
// いずれの濃さでも本文テキスト（インクブラウン）とのコントラスト比は計算上10:1超を維持しており、
// 可読性そのものは損なわれない（濃さの違いはあくまで「入力中の視覚的な主張の強さ」の調整）。
//
// 5.4.6（Phase 4追加フィードバック）：綴じ穴・紙テクスチャ（NotebookTexture.swift参照）を
// 「カード背景色 → 方眼罫線 → 紙テクスチャ → コンテンツ」の順で重ねる。SCR-06のテキストエリアは
// 紙テクスチャのみ適用し、綴じ穴は適用しない（入力欄には不要なため）。

/// 縦横の格子線を`Canvas`で描画するテクスチャ層。
/// 罫線色はページボーダーの不透明度を上げた値、線の太さ0.5pt、間隔24pt程度を既定値とする。
struct GridPaperPattern: View {
    var lineColor: Color = BookTheme.border.opacity(0.45)
    var spacing: CGFloat = 24
    var lineWidth: CGFloat = 0.5

    var body: some View {
        Canvas { context, size in
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// カード背景（ページホワイト）＋角丸＋柔らかい陰影に、方眼罫線・紙テクスチャ（5.4.5／5.4.6③）・
    /// 綴じ穴（5.4.6①）を重ねた「ノート風カード」の共通スタイル。MemoCardView（SCR-05）・
    /// 要約カード／空状態カード（SCR-08）で共用する。すべてカードの角丸に合わせてクリップされ、
    /// カード外にはみ出さない。`gridOpacity`は既定45%（5.4.5の40〜50%目安の中央値）、
    /// `noiseOpacity`は既定4%（5.4.6③の3〜5%目安の中央値）。
    func notebookCardStyle(
        cornerRadius: CGFloat = BookTheme.cardCornerRadius,
        gridOpacity: Double = 0.45,
        noiseOpacity: Double = 0.04
    ) -> some View {
        self
            .background(PaperNoisePattern(color: BookTheme.primary.opacity(noiseOpacity)))
            .background(GridPaperPattern(lineColor: BookTheme.border.opacity(gridOpacity)))
            .background(BookTheme.cardBackground)
            .ringBindingHoles()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .bookCardShadow()
    }

    /// SCR-06のTextEditor背景専用。カード陰影・綴じ穴は付けず、罫線＋紙テクスチャ＋
    /// ページホワイトの背景のみをテキストエリアの角丸（10pt）に合わせて敷く。
    /// 既定28%（罫線）・4%（紙テクスチャ）はいずれも入力文字の可読性を優先した設定。
    func notebookTextFieldBackground(
        cornerRadius: CGFloat = BookTheme.textFieldCornerRadius,
        gridOpacity: Double = 0.28,
        noiseOpacity: Double = 0.04
    ) -> some View {
        self
            .background(PaperNoisePattern(color: BookTheme.primary.opacity(noiseOpacity)))
            .background(GridPaperPattern(lineColor: BookTheme.border.opacity(gridOpacity)))
            .background(BookTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

#Preview("カード用（45%）") {
    VStack(spacing: 16) {
        Text("ノート風カードのプレビュー")
            .font(BookTheme.body)
            .foregroundStyle(BookTheme.textPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notebookCardStyle()
    }
    .padding()
    .background(BookTheme.background)
}

#Preview("テキストエリア用（28%）") {
    Text("方眼罫線つきテキストエリアのプレビュー\n入力文字の可読性を確認する")
        .font(BookTheme.body)
        .foregroundStyle(BookTheme.textPrimary)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .notebookTextFieldBackground()
        .padding()
        .background(BookTheme.background)
}
