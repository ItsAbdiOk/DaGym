import Foundation
import OSLog
import Security

let walletLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "wallet")

/// Signs a pass manifest with the bundled Pass Type ID identity (`pass.p12`, imported once
/// into process memory — never the keychain). Immutable after `init`, and `SecKey` /
/// `SecCertificate` are thread-safe to use, so the builder can sign on a detached task.
final class WalletPassSigner: @unchecked Sendable {
    /// The pass certificate's DER.
    let certificateDER: Data
    /// The intermediates that ship alongside it (Apple WWDR).
    let chainDER: [Data]
    private let privateKey: SecKey
    private let publicKey: SecKey?

    /// Loads the identity from a PKCS#12 blob. `intermediatePEM` (the public WWDR cert) is a
    /// fallback for when the import doesn't hand the intermediate back in the chain.
    init(pkcs12: Data, passphrase: String, intermediatePEM: Data? = nil) throws {
        let options: [CFString: Any] = [kSecImportExportPassphrase: passphrase, kSecImportToMemoryOnly: true]
        var rawItems: CFArray?
        let status = SecPKCS12Import(pkcs12 as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess else { throw WalletPassError.identityImport(status) }
        guard let items = rawItems as? [[CFString: Any]], let first = items.first,
              let identityRef = first[kSecImportItemIdentity] as? AnyObject,
              CFGetTypeID(identityRef) == SecIdentityGetTypeID() else {
            throw WalletPassError.identityMissing
        }
        // A CF type can't be `as?`-cast (the compiler notes it "always succeeds"); the type-ID
        // check above is the real test, so the downcast is a plain pointer reinterpretation.
        let identity = unsafeDowncast(identityRef, to: SecIdentity.self)

        var certificateRef: SecCertificate?
        var keyRef: SecKey?
        guard SecIdentityCopyCertificate(identity, &certificateRef) == errSecSuccess,
              SecIdentityCopyPrivateKey(identity, &keyRef) == errSecSuccess,
              let certificate = certificateRef, let key = keyRef else {
            throw WalletPassError.identityMissing
        }
        let leafDER = SecCertificateCopyData(certificate) as Data
        privateKey = key
        publicKey = SecCertificateCopyKey(certificate)
        certificateDER = leafDER

        let chain = (first[kSecImportItemCertChain] as? [SecCertificate]) ?? []
        let intermediates = chain.map { SecCertificateCopyData($0) as Data }
            .filter { $0 != leafDER && !Self.isSelfSigned($0) }
        if intermediates.isEmpty, let pem = intermediatePEM, let fallback = Self.derFromPEM(pem) {
            chainDER = [fallback]
        } else {
            chainDER = intermediates
        }
        if chainDER.isEmpty {
            walletLogger.error("Pass identity loaded without an intermediate; Wallet will reject the pass")
        }
    }

    /// The detached CMS signature over `manifest`.
    func signature(forManifest manifest: Data, at date: Date = Date()) throws -> Data {
        let key = privateKey
        let signer = CMSSignature.Signer(certificateDER: certificateDER, chainDER: chainDER) { bytes in
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(
                key, .rsaSignatureMessagePKCS1v15SHA256, bytes as CFData, &error
            ) else {
                let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
                throw WalletPassError.signing(reason)
            }
            return signature as Data
        }
        return try CMSSignature.detached(message: manifest, signer: signer, signingTime: date)
    }

    /// Checks an RSA-SHA256 signature against the identity's own public key (tests).
    func verify(signature: Data, over bytes: Data) -> Bool {
        guard let publicKey else { return false }
        return SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, bytes as CFData, signature as CFData, nil
        )
    }

    /// The pass certificate's issuer + serial, as the CMS `SignerInfo` names it.
    func identity() throws -> CertificateIdentity {
        try CertificateIdentity(certificateDER: certificateDER)
    }

    private static func isSelfSigned(_ der: Data) -> Bool {
        guard let certificate = try? DERParser.parseOne([UInt8](der)),
              let tbs = certificate.children.first else { return false }
        var fields = tbs.children[...]
        if fields.first?.tag == DER.Tag.context(0) { fields = fields.dropFirst() }
        guard fields.count >= 6 else { return false }
        let issuer = fields[fields.startIndex + 2]
        let subject = fields[fields.startIndex + 4]
        return issuer.raw == subject.raw
    }

    /// The first certificate in a PEM file, base64-decoded.
    static func derFromPEM(_ pem: Data) -> Data? {
        guard let text = String(data: pem, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        var body: [String] = []
        var inside = false
        for line in lines {
            if line.hasPrefix("-----BEGIN CERTIFICATE-----") { inside = true; continue }
            if line.hasPrefix("-----END CERTIFICATE-----") { break }
            if inside { body.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        return Data(base64Encoded: body.joined())
    }
}

/// Everything that can stop a pass being minted, in words the sheet can show.
enum WalletPassError: LocalizedError, Equatable {
    case unavailable
    case identityImport(OSStatus)
    case identityMissing
    case iconUnavailable
    case valueNotEncodable
    case signing(String)
    case invalidPass

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Wallet isn't available on this device."
        case .identityImport, .identityMissing: "The pass signing certificate couldn't be loaded."
        case .iconUnavailable: "The pass artwork couldn't be drawn."
        case .valueNotEncodable: "This card's number has characters Wallet can't encode."
        case .signing: "The pass couldn't be signed."
        case .invalidPass: "Wallet didn't accept the generated pass."
        }
    }
}
