import AppKit

extension NSColor {
    /// A color for light appearances and one for dark ones, as 0xRRGGBB sRGB values. It is resolved whenever it is
    /// drawn, so it suits the appearance of the window or menu bar it is drawn in.
    convenience init(light: Int, dark: Int) {
        self.init(name: nil) { appearance in
            NSColor(rgb: appearance.isDark ? dark : light)
        }
    }

    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
