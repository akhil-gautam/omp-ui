import SwiftUI

/// The mark omp-ui wears: omp's glyph, squared.
struct BrandMark: View {
    @Environment(\.palette) private var palette
    /// The width of the mark.
    var width: CGFloat = 17

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / BrandGeometry.width
            for bar in BrandGeometry.bars {
                let rect = CGRect(
                    x: CGFloat(bar.x) * unit,
                    y: CGFloat(bar.y) * unit,
                    width: CGFloat(bar.width) * unit,
                    height: CGFloat(bar.height) * unit
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: CGFloat(bar.radius) * unit, style: .continuous),
                    with: .color(palette.accent)
                )
            }
        }
        .frame(width: width, height: width * BrandGeometry.height / BrandGeometry.width)
    }
}
