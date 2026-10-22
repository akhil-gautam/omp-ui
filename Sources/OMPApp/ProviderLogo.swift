import AppKit
import SwiftUI
import OMPCore

/// Provider logos from models.dev, loaded once each and kept for the life of
/// the app.
@MainActor
@Observable
final class Logos {
    static let shared = Logos()

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    /// The logo, if it has arrived; asking starts it arriving.
    func image(for provider: String) -> NSImage? {
        if let image = images[provider] { return image }
        if asked.insert(provider).inserted {
            Task {
                guard let data = await ModelsDev.logo(for: provider), let image = NSImage(data: data) else { return }
                // Drawn in the colour of the text around it, as models.dev
                // draws them in `currentColor`.
                image.isTemplate = true
                images[provider] = image
            }
        }
        return nil
    }
}

/// A provider's logo, in the colour of the text beside it; a quiet blank of
/// the same size until it arrives.
struct ProviderLogo: View {
    @Environment(\.palette) private var palette
    let provider: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let image = Logos.shared.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(palette.inkDim)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.raised)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
