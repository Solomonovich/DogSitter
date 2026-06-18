import SwiftUI

/// Type scale. All tokens map to a Dynamic Type text style so they scale with
/// the user's accessibility text size. Set `customFontName` to swap in a custom
/// font app-wide while keeping Dynamic Type scaling.
struct Typography: Equatable {
    var customFontName: String? = nil

    private func font(_ size: CGFloat,
                      _ weight: Font.Weight,
                      _ design: Font.Design = .default,
                      relativeTo style: Font.TextStyle) -> Font {
        if let name = customFontName {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight, design: design)
    }

    /// Big rounded brand/splash title.
    var display:     Font { font(40, .heavy,    .rounded, relativeTo: .largeTitle) }
    var largeTitle:  Font { font(34, .bold,     .default, relativeTo: .largeTitle) }
    var title:       Font { font(28, .bold,     .default, relativeTo: .title) }
    var title2:      Font { font(22, .bold,     .default, relativeTo: .title2) }
    var title3:      Font { font(20, .semibold, .default, relativeTo: .title3) }
    var headline:    Font { font(17, .semibold, .default, relativeTo: .headline) }
    var body:        Font { font(17, .regular,  .default, relativeTo: .body) }
    var bodyBold:    Font { font(17, .semibold, .default, relativeTo: .body) }
    var callout:     Font { font(16, .regular,  .default, relativeTo: .callout) }
    var subheadline: Font { font(15, .regular,  .default, relativeTo: .subheadline) }
    var footnote:    Font { font(13, .regular,  .default, relativeTo: .footnote) }
    var caption:     Font { font(12, .regular,  .default, relativeTo: .caption) }
    var captionBold: Font { font(12, .bold,     .default, relativeTo: .caption) }

    static let standard = Typography()
}
