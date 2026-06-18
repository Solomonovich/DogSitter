import CoreGraphics

/// 8pt-based spacing scale. Use these instead of hardcoded padding values.
struct Spacing: Equatable {
    let xxs: CGFloat = 4
    let xs:  CGFloat = 8
    let sm:  CGFloat = 12
    let md:  CGFloat = 16
    let lg:  CGFloat = 24
    let xl:  CGFloat = 32
    let xxl: CGFloat = 40
    /// Standard horizontal inset for screen content.
    let screenH: CGFloat = 16

    static let standard = Spacing()
}
