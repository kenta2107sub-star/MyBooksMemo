import SwiftUI
import UIKit

// SwiftUIのnavigationTitleは既定でシステムフォント（サンセリフ）になるため、
// basic_design.md 5.3の「見出しはserifデザインバリアント」をナビゲーションバーの
// タイトルにも反映させるためにUINavigationBarAppearanceを1箇所で設定する。
// あわせて背景をページクリームにし、白いiOS標準ナビバーが並ぶ「よくあるアプリ」感を消す。
enum NavigationBarAppearanceConfigurator {
    static func configure() {
        let serifTitleFont = UIFont(descriptor: UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body),
            size: UIFont.preferredFont(forTextStyle: .body).pointSize + 1)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(BookTheme.background)
        appearance.shadowColor = UIColor(BookTheme.border)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(BookTheme.textPrimary),
            .font: serifTitleFont
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(BookTheme.primary)
    }
}
