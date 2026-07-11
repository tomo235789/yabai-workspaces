import SwiftUI
import AppKit

/// Renders the menu-bar UI to a PNG without a GUI session, using SwiftUI's
/// `ImageRenderer`. This is what lets the test/report tooling capture real
/// screenshots of the themed interface headlessly.
@MainActor
public enum MenuRenderer {
    public static func png(model: MenuViewModel, theme: Theme, width: CGFloat = 280, scale: CGFloat = 2) -> Data? {
        let view = MenuContentView(model: model, theme: theme, staticField: true)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }
}
