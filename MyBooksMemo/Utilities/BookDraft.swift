import Foundation

// 本登録フロー（SCR-02→SCR-04→SCR-03）の間で受け渡す入力途中の値。
// architecture.md 6.1のBookプロパティ名に合わせているが、
// 登録完了前は`Book`インスタンス化前の「下書き」のため、値型として別に定義する。
struct BookDraft: Hashable {
    var title: String = ""
    var author: String = ""
    var coverImageData: Data? = nil
}
