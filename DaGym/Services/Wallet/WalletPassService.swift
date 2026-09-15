import Foundation
import PassKit
import UIKit

/// "Add to Apple Wallet" for a saved gym card. The pass is built and signed on the phone with
/// the bundled Pass Type ID identity — no server, nothing leaves the device. The identity is
/// an optional resource, so a checkout without it simply reports `isAvailable == false` and
/// the sheet hides the button.
@MainActor
@Observable
final class WalletPassService {
    nonisolated static let passphrase = "dagym-pass"

    private let library: PKPassLibrary
    private let identityURL: URL?
    /// The public Apple WWDR G4 intermediate, committed as `Resources/AppleWWDRG4.pem` — used
    /// only if the PKCS#12 import doesn't return it in the chain.
    private let intermediateURL: URL?
    // Not observed: `isAvailable` is read inside view bodies and loads the identity on first
    // use, and a tracked write during a body evaluation would re-render in a loop.
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var signer: WalletPassSigner?
    /// Signed passes by card, so re-checking `isAlreadyAdded` after an add doesn't re-sign.
    @ObservationIgnored private var built: [GymCardInfo: Data] = [:]

    init(
        identityURL: URL? = Bundle.main.url(forResource: "pass", withExtension: "p12"),
        intermediateURL: URL? = Bundle.main.url(forResource: "AppleWWDRG4", withExtension: "pem"),
        library: PKPassLibrary = PKPassLibrary()
    ) {
        self.identityURL = identityURL
        self.intermediateURL = intermediateURL
        self.library = library
    }

    /// Wallet exists on this device and the signing identity loaded.
    var isAvailable: Bool {
        PKPassLibrary.isPassLibraryAvailable() && loadSigner() != nil
    }

    /// The signed `.pkpass` bytes for `card`, built off the main actor.
    func pass(for card: GymCardInfo) async throws -> Data {
        if let data = built[card] { return data }
        guard PKPassLibrary.isPassLibraryAvailable(), let signer = loadSigner() else {
            throw WalletPassError.unavailable
        }
        let images = try WalletPassImages.render()
        let builder = WalletPassBuilder(signer: signer, images: images, accent: DGColor.current)
        let data = try await Task.detached(priority: .userInitiated) {
            try builder.pass(for: card)
        }.value
        built[card] = data
        return data
    }

    /// A `PKPass` Wallet can show or add, from the signed bytes.
    func wrap(_ data: Data) throws -> PKPass {
        do {
            return try PKPass(data: data)
        } catch {
            let reason = error.localizedDescription
            walletLogger.error("PKPass rejected generated pass: \(reason, privacy: .public)")
            throw WalletPassError.invalidPass
        }
    }

    /// True once this card's pass is in the lifter's Wallet. Needs the built pass (Wallet
    /// matches on type + serial inside it), so call after `pass(for:)`.
    func isAlreadyAdded(card: GymCardInfo) -> Bool {
        guard let data = built[card], let pass = try? wrap(data) else { return false }
        return library.containsPass(pass)
    }

    /// Jumps to the pass in Wallet via its `passURL` (the only route that needs no pass-type
    /// entitlement — `PKPassLibrary` has no "open" call).
    func openInWallet(card: GymCardInfo) {
        guard let data = built[card], let pass = try? wrap(data), let url = pass.passURL else { return }
        UIApplication.shared.open(url)
    }

    private func loadSigner() -> WalletPassSigner? {
        if loaded { return signer }
        loaded = true
        guard let identityURL, let pkcs12 = try? Data(contentsOf: identityURL) else {
            walletLogger.info("No pass.p12 in the bundle; Add to Wallet hidden")
            return nil
        }
        let intermediate = intermediateURL.flatMap { try? Data(contentsOf: $0) }
        do {
            signer = try WalletPassSigner(
                pkcs12: pkcs12, passphrase: Self.passphrase, intermediatePEM: intermediate
            )
        } catch {
            let reason = error.localizedDescription
            walletLogger.error("Pass identity failed to load: \(reason, privacy: .public)")
        }
        return signer
    }
}
