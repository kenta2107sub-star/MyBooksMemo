import SwiftUI

// SCR-01：本カードUI。2列グリッドの1マス分。
// basic_design.mdでは「本カードを左スワイプすると赤背景の『削除』ボタンが現れる」とあるが、
// LazyVGridはList標準のswipeActionsを使えないため、DragGestureでカードをオフセットさせ
// 背後の削除ボタンを露出させる独自実装で表現する。
struct BookCardView: View {
    let book: Book
    var onTap: () -> Void
    var onDeleteRequested: () -> Void

    @State private var dragOffset: CGFloat = 0
    private let revealWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
                .opacity(dragOffset < -4 ? 1 : 0)

            cardContent
                .offset(x: dragOffset)
                .gesture(dragGesture)
                .onTapGesture { handleTap() }
        }
        .animation(.reduceMotionAware(.easeOut(duration: 0.2)), value: dragOffset < -4)
    }

    private var deleteAction: some View {
        Button {
            withAnimation(.reduceMotionAware(.easeOut(duration: 0.18))) { dragOffset = 0 }
            onDeleteRequested()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                Text("削除")
                    .font(BookTheme.caption)
            }
            .foregroundStyle(.white)
            .frame(width: revealWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .background(BookTheme.error)
        .clipShape(RoundedRectangle(cornerRadius: BookTheme.cardCornerRadius, style: .continuous))
        .accessibilityLabel("『\(book.title)』を削除")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverView(title: book.title, imageData: book.coverImageData)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

            Text(book.title)
                .font(BookTheme.heading(.subheadline))
                .foregroundStyle(BookTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(book.author)
                .font(BookTheme.caption)
                .foregroundStyle(BookTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BookTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: BookTheme.cardCornerRadius, style: .continuous))
        .bookCardShadow()
        .contentShape(Rectangle())
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = max(-revealWidth, min(0, value.translation.width))
            }
            .onEnded { _ in
                let shouldReveal = dragOffset < -revealWidth / 2
                withAnimation(.reduceMotionAware(.spring(response: 0.32, dampingFraction: 0.85))) {
                    dragOffset = shouldReveal ? -revealWidth : 0
                }
            }
    }

    private func handleTap() {
        if dragOffset != 0 {
            withAnimation(.reduceMotionAware(.easeOut(duration: 0.2))) { dragOffset = 0 }
        } else {
            onTap()
        }
    }
}

#Preview {
    BookCardView(book: PreviewData.makeBooks()[0], onTap: {}, onDeleteRequested: {})
        .frame(width: 165)
        .padding()
        .background(BookTheme.background)
}
