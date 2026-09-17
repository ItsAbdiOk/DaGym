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
    static func render(icon: UIImage? = appIcon()) throws -> [String: Data] {
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

    /// The app icon as iOS actually ships it. `UIImage(named: "AppIcon")` is not reliable —
    /// the catalogue set is compiled into `AppIcon60x60@2x.png`-style files that Info.plist
    /// lists under CFBundleIcons — so read that list, and if nothing loads, draw a plain mark
    /// so a pass can always be built.
    @MainActor
    static func appIcon() -> UIImage? {
        if let named = UIImage(named: "AppIcon") { return named }
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String] ?? []
        for file in files.reversed() {
            if let image = UIImage(named: file) { return image }
        }
        return fallbackMark()
    }

    /// A coral square with "DG" — the pass still looks like the app when the icon files are
    /// not readable (they never are in a unit-test host).
    @MainActor
    static func fallbackMark() -> UIImage {
        let side: CGFloat = 180
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIColor(red: 0.89, green: 0.34, blue: 0.25, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let text = NSAttributedString(string: "DG", attributes: [
                .font: UIFont.systemFont(ofSize: side * 0.42, weight: .heavy),
                .foregroundColor: UIColor.white, .paragraphStyle: paragraph
            ])
            let height = text.size().height
            text.draw(in: CGRect(x: 0, y: (side - height) / 2, width: side, height: height))
        }
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
