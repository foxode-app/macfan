import AppKit
import SwiftUI

/// The menu bar item itself: the selected metrics, or a fan icon when none are selected.
struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @AppStorage(MenuBarItems.storageKey) private var items = MenuBarItems.default
    @AppStorage(MenuBarStyle.storageKey) private var style = MenuBarStyle.default

    var body: some View {
        if items.isEmpty {
            Image(systemName: "fan")
        } else {
            Image(nsImage: MenuBarImage.draw(items.segments(for: monitor.snapshot), style: style))
        }
    }
}

/// Draws the metrics side by side, each in a block as wide as its widest text with the value right-aligned, so
/// changing readings move neither the other metrics nor the menu bar items to the left. With meters, each block's
/// background is a meter of the reading. The text is drawn here because a menu bar extra's label ignores fonts and
/// layout: its `Text` keeps proportional digits even with `monospacedDigit()`.
private enum MenuBarImage {
    static let height: CGFloat = 18
    static let cornerRadius: CGFloat = 4
    /// Evens out the wallpaper behind the menu bar, so the text and the meters read the same on any picture.
    static let blockBackground = NSColor(name: nil) { appearance in
        appearance.isDark ? .black.withAlphaComponent(0.5) : .white.withAlphaComponent(0.5)
    }

    static func draw(_ segments: [MenuBarSegment], style: MenuBarStyle) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        let layout = Layout(style, font: font)
        let blockWidths = segments.map { max(width($0.text), width($0.widestText)) + 2 * layout.padding }
        let contentWidth = blockWidths.reduce(0, +) + layout.spacing * CGFloat(segments.count - 1)
        let size = NSSize(width: ceil(contentWidth) + 2 * layout.margin, height: height)
        // Plain text is a template image, which the menu bar colors like its own text; meters bring their own colors.
        let textColor: NSColor = style == .meters ? .labelColor : .black
        // AppKit calls this whenever the image is drawn, possibly on another thread, with the menu bar's appearance
        // current, so the colors suit a light or dark menu bar. It only reads the values above.
        let image = NSImage(size: size, flipped: false) { _ in
            var x = layout.margin
            for (segment, blockWidth) in zip(segments, blockWidths) {
                let block = NSRect(x: x, y: 0, width: blockWidth, height: height)
                if style == .meters {
                    drawMeter(segment.meter, in: block)
                }
                // Without `usesLineFragmentOrigin`, the text is drawn on one line with its baseline at the origin.
                let origin = NSPoint(x: block.maxX - layout.padding - width(segment.text), y: layout.baseline)
                (segment.text as NSString).draw(
                    with: NSRect(origin: origin, size: .zero), attributes: [.font: font, .foregroundColor: textColor],
                    context: nil)
                x += blockWidth + layout.spacing
            }
            return true
        }
        image.isTemplate = style == .text
        image.accessibilityDescription = segments.map(\.text).joined(separator: ", ")
        return image
    }

    /// Fills the block from the left as far as the reading goes, in the color of its level, and tints the rest of the
    /// block with that color. A block without a reading is gray.
    private static func drawMeter(_ meter: Double?, in block: NSRect) {
        let shape = NSBezierPath(roundedRect: block, xRadius: cornerRadius, yRadius: cornerRadius)
        blockBackground.setFill()
        shape.fill()
        guard let meter else {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            shape.fill()
            return
        }
        let color = MeterLevel(meter).color
        color.withAlphaComponent(0.3).setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        color.setFill()
        NSRect(x: block.minX, y: block.minY, width: block.width * meter, height: block.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Where the blocks and their text go in the image.
    private struct Layout {
        /// Room around the text inside each block.
        let padding: CGFloat
        /// Room between blocks.
        let spacing: CGFloat
        /// Transparent room at either side of the image.
        let margin: CGFloat
        /// The text's baseline, above the bottom of the image.
        let baseline: CGFloat

        init(_ style: MenuBarStyle, font: NSFont) {
            switch style {
            case .text:
                // Where a status item's own text title would be: a status bar button pads a title 2 pt more on each
                // side than an image, and sets it 1 pt higher than it centers an image. Metrics are two spaces apart.
                padding = 0
                spacing = ("  " as NSString).size(withAttributes: [.font: font]).width
                margin = 2
                baseline = 5
            case .meters:
                // Capitals and digits are centered in the block, with the baseline on a half point.
                padding = 4
                spacing = 4
                margin = 0
                baseline = (MenuBarImage.height - font.capHeight).rounded() / 2
            }
        }
    }
}

/// How close a reading is to its limit: green below 70 %, amber from 70 % and red from 90 %.
private enum MeterLevel {
    case normal, high, critical

    init(_ meter: Double) {
        self =
            switch meter {
            case ..<0.7: .normal
            case ..<0.9: .high
            default: .critical
            }
    }

    /// The system's green, amber (between its yellow and orange) and red: at 75 % over white for black text in a light
    /// menu bar, and darkened in a dark one until white text has about 4:1 contrast. Darker would turn amber brown.
    var color: NSColor {
        let (light, dark) =
            switch self {
            case .normal: (0x67d583, 0x1d8e39)
            case .high: (0xffc14f, 0xab770c)
            case .critical: (0xff6a6d, 0xe0393b)
            }
        return NSColor(light: light, dark: dark)
    }
}
