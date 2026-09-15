import UIKit

/// The pass artwork, drawn from the app icon at runtime so nothing extra ships in the bundle:
/// `icon` at 29 pt (1×/2×/3×) for the Wallet list and notifications, `logo` at 50 pt (1×/2×)
/// for the pass header next to `logoText`. Wallet caps logos at 160 × 50 pt; a square
/// 50 pt mark keeps "DaGym" tight against it instead of pushing it to the far edge.
enum WalletPassImages {
    static let iconPoints: CGFloat = 29
    static let logoPoints: CGFloat = 50

    /// File name → PNG bytes for every image the manifest lists.
    @MainActor
    static func render(icon: UIImage? = UIImage(named: "AppIcon")) throws -> [String: Data] {
        guard let icon else { throw WalletPassError.iconUnavailable }
        var files: [String: Data] = [:]
        for (name, scale) in [("icon.png", 1), ("icon@2x.png", 2), ("icon@3x.png", 3)] {
            files[name] = try png(icon, side: iconPoints * CGFloat(scale))
        }
        for (name, scale) in [("logo.png", 1), ("logo@2x.png", 2)] {
            files[name] = try png(icon, side: logoPoints * CGFloat(scale))
        }
        return files
    }

    /// The icon drawn into a `side`-pixel square with the same continuous corner radius iOS
    /// gives app icons (~22 % of the side), on a transparent ground.
    private static func png(_ icon: UIImage, side: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.22).addClip()
            icon.draw(in: rect)
        }
        guard let data = image.pngData() else { throw WalletPassError.iconUnavailable }
        return data
    }
}
