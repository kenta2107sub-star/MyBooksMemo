import SwiftUI
import UIKit

// basic_design.md 5.5：「書影が取得できない場合、ページクリーム背景に本のシルエットアイコン
// （ブックブラウン、線画）を配置したシンプルな画像を表示する」を、
// 外部画像アセットを追加せずコード（Shape）で描画して実現する。
//
// 5.0で「イラストは追加しない／書影画像のみでシンプルに構成する」と確定しているため、
// 装飾的なイラストにはせず、あくまで「本」そのものを表す線画＋しおり（ブランドカラー）に留める。
// 本ごとに背景トーンを変える（タイトル文字列から決定的に選択）ことで、
// 書影なしの本棚でも「同じカードの繰り返し」に見えないようにしている。

/// 本の輪郭・背表紙の区切り線・タイトル帯を表す線画シェイプ
private struct BookGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        let bookRect = CGRect(
            x: rect.minX + inset,
            y: rect.minY + rect.height * 0.14,
            width: rect.width - inset * 2,
            height: rect.height * 0.72
        )
        let corner = rect.width * 0.05

        path.addRoundedRect(in: bookRect, cornerSize: CGSize(width: corner, height: corner))

        // 背表紙の折り返し線（表紙の少し内側の縦線）
        let spineX = bookRect.minX + bookRect.width * 0.18
        path.move(to: CGPoint(x: spineX, y: bookRect.minY + corner * 0.5))
        path.addLine(to: CGPoint(x: spineX, y: bookRect.maxY - corner * 0.5))

        // タイトルを思わせる2本の帯線
        let lineX = bookRect.minX + bookRect.width * 0.36
        let lineWidth = bookRect.width * 0.46
        let line1Y = bookRect.minY + bookRect.height * 0.58
        let line2Y = bookRect.minY + bookRect.height * 0.72
        path.move(to: CGPoint(x: lineX, y: line1Y))
        path.addLine(to: CGPoint(x: lineX + lineWidth, y: line1Y))
        path.move(to: CGPoint(x: lineX, y: line2Y))
        path.addLine(to: CGPoint(x: lineX + lineWidth * 0.6, y: line2Y))

        return path
    }
}

/// 表紙にかかる「しおり」。ブックマークアンバーで塗りつぶし、ブランドの色をワンポイントで効かせる
private struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let ribbonWidth = rect.width * 0.12
        let x = rect.minX + rect.width * 0.6
        let topY = rect.minY + rect.height * 0.14
        let bottomY = topY + rect.height * 0.34
        let notch = rect.height * 0.055

        path.move(to: CGPoint(x: x, y: topY))
        path.addLine(to: CGPoint(x: x + ribbonWidth, y: topY))
        path.addLine(to: CGPoint(x: x + ribbonWidth, y: bottomY))
        path.addLine(to: CGPoint(x: x + ribbonWidth / 2, y: bottomY - notch))
        path.addLine(to: CGPoint(x: x, y: bottomY))
        path.closeSubpath()
        return path
    }
}

/// 書影ビュー。`imageData`が渡された場合は実画像を表示し（SCR-03のPhotosPicker選択結果等）、
/// `nil`の場合（basic_design.mdのダミーデータは全てnil）は線画プレースホルダーを表示する。
struct BookCoverView: View {
    let title: String
    var imageData: Data? = nil
    var cornerRadius: CGFloat = BookTheme.cardCornerRadius

    /// タイトル文字列から決定的に0〜3を選び、背景トーンにささやかなバリエーションを持たせる
    private var variantIndex: Int {
        var hasher = Hasher()
        hasher.combine(title)
        return abs(hasher.finalize()) % 4
    }

    private var backgroundGradient: LinearGradient {
        switch variantIndex {
        case 0:
            return LinearGradient(colors: [BookTheme.background, BookTheme.border.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
        case 1:
            return LinearGradient(colors: [BookTheme.secondary.opacity(0.20), BookTheme.background],
                                   startPoint: .top, endPoint: .bottom)
        case 2:
            return LinearGradient(colors: [BookTheme.border, BookTheme.cardBackground],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [BookTheme.primary.opacity(0.16), BookTheme.background],
                                   startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        ZStack {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                backgroundGradient
                BookGlyph()
                    .stroke(BookTheme.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                BookmarkRibbon()
                    .fill(BookTheme.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(BookTheme.border, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        BookCoverView(title: "嫌われる勇気")
        BookCoverView(title: "7つの習慣")
        BookCoverView(title: "人を動かす")
    }
    .frame(height: 160)
    .padding()
    .background(BookTheme.background)
}
