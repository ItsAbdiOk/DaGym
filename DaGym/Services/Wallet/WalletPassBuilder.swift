import CryptoKit
import Foundation

/// Assembles a `.pkpass`: `pass.json`, the artwork, `manifest.json` (SHA-1 of every file, as
/// the pass format still mandates) and the detached CMS `signature` over the manifest, zipped
/// uncompressed. Pure data in, `Data` out — runs on whatever task calls it.
struct WalletPassBuilder: Sendable {
    var signer: WalletPassSigner
    /// Pre-rendered artwork (`WalletPassImages.render`), file name → PNG.
    var images: [String: Data]
    var accent: DGAccent

    func pass(for card: GymCardInfo, now: Date = Date()) throws -> Data {
        var files = images
        files["pass.json"] = try WalletPassJSON(card: card, accent: accent).encoded()
        let manifest = try Self.manifest(files)
        let signature = try signer.signature(forManifest: manifest, at: now)

        var zip = ZipWriter()
        zip.modified = now
        for name in files.keys.sorted() {
            if let data = files[name] { zip.add(name, data) }
        }
        zip.add("manifest.json", manifest)
        zip.add("signature", signature)
        return zip.archive()
    }

    /// `{"file": "<sha1 hex>", …}` with sorted keys so two builds of one card match byte for byte.
    static func manifest(_ files: [String: Data]) throws -> Data {
        let hashes = files.mapValues { data in
            Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(hashes)
    }
}
