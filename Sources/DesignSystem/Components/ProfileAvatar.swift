import SwiftUI

/// Themed profile avatar. Shows the user's remote photo when `photoURL` is a real
/// http(s) URL, otherwise a person icon on a tinted surface. The clip shape follows
/// the user's `avatarShape` preference (circle vs. rounded square).
/// Visual only — does not add any upload behavior.
struct ProfileAvatar: View {
    @Environment(\.theme) private var theme
    let photoURL: String?
    var size: CGFloat = 96

    private var isRemote: Bool {
        (photoURL?.hasPrefix("http")) ?? false
    }

    var body: some View {
        let shape = theme.avatarShape.clipShape(for: size)
        return Group {
            if isRemote {
                CachedAsyncImage(photoURL, contentMode: .fill, targetSize: size * 2) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(theme.color.separator, lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            theme.color.surfaceSecondary
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.26)
                .foregroundStyle(theme.color.textSecondary)
        }
    }
}
