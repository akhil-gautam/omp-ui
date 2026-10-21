import Foundation

/// The shape of the omp-ui mark, shared by the title bar and the app icon.
///
/// The mark is a bar over two stems: omp's own glyph, squared and redrawn so
/// the app is clearly an omp thing without copying the brand. Everything is
/// measured in a 46×30 space with the origin at the top left, so the same
/// numbers can be drawn by SwiftUI and by the icon renderer.
enum BrandGeometry {
    /// A rounded bar.
    struct Bar {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let radius: Double
    }

    /// The bar and the two stems.
    static let bars: [Bar] = [
        Bar(x: 0, y: 0, width: 46, height: 7, radius: 3.5),
        Bar(x: 9, y: 0, width: 8, height: 30, radius: 4),
        Bar(x: 29, y: 0, width: 8, height: 30, radius: 4),
    ]

    /// The width of the mark.
    static let width: Double = 46

    /// The height of the mark.
    static let height: Double = 30
}
