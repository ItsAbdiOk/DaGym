import CryptoKit
import Foundation
import Security

/// The OIDs a detached CMS signature is built from.
enum CMSOID {
    static let data = "1.2.840.113549.1.7.1"
    static let signedData = "1.2.840.113549.1.7.2"
    static let sha256 = "2.16.840.1.101.3.4.2.1"
    static let rsaEncryption = "1.2.840.113549.1.1.1"
    static let contentType = "1.2.840.113549.1.9.3"
    static let messageDigest = "1.2.840.113549.1.9.4"
    static let signingTime = "1.2.840.113549.1.9.5"
}

/// Builds the detached CMS / PKCS#7 `SignedData` Wallet expects in a pass's `signature` file:
/// one RSA-SHA256 signer over `manifest.json`, the pass certificate and the WWDR intermediate
/// carried in `certificates`, no encapsulated content. `sign(attributes:)` is the only step
/// that touches a private key, so the structure is testable against any RSA key.
enum CMSSignature {
    struct Signer {
        /// The signing certificate's DER (goes in `certificates`, names the signer).
        var certificateDER: Data
        /// Intermediates to ship alongside — Apple WWDR for a pass.
        var chainDER: [Data]
        /// RSA PKCS#1 v1.5 / SHA-256 over the given bytes.
        var sign: (Data) throws -> Data
    }

    /// The signed attributes as they are hashed: a plain SET (tag 0x31), per RFC 5652 §5.4.
    static func signedAttributes(messageDigest: Data, signingTime: Date) -> [UInt8] {
        DER.set([
            attribute(CMSOID.contentType, DER.oid(CMSOID.data)),
            attribute(CMSOID.signingTime, DER.time(signingTime)),
            attribute(CMSOID.messageDigest, DER.octetString(messageDigest))
        ])
    }

    /// The whole `ContentInfo { id-signedData, [0] SignedData }` as DER.
    static func detached(message: Data, signer: Signer, signingTime: Date = Date()) throws -> Data {
        let digest = Data(SHA256.hash(data: message))
        let attributes = signedAttributes(messageDigest: digest, signingTime: signingTime)
        let signature = try signer.sign(Data(attributes))
        let identity = try CertificateIdentity(certificateDER: signer.certificateDER)

        let signerInfo = DER.sequence([
            DER.integer(1),
            DER.sequence([identity.issuerDER, identity.serialDER]),
            DER.algorithm(CMSOID.sha256),
            implicitAttributes(attributes),
            DER.algorithm(CMSOID.rsaEncryption),
            DER.octetString(signature)
        ])
        let certificates = ([signer.certificateDER] + signer.chainDER).map { [UInt8]($0) }
        let signedData = DER.sequence([
            DER.integer(1),
            DER.set([DER.algorithm(CMSOID.sha256)]),
            DER.sequence([DER.oid(CMSOID.data)]),
            DER.implicitSet(0, certificates),
            DER.set([signerInfo])
        ])
        let contentInfo = DER.sequence([DER.oid(CMSOID.signedData), DER.explicit(0, signedData)])
        return Data(contentInfo)
    }

    private static func attribute(_ oid: String, _ value: [UInt8]) -> [UInt8] {
        DER.sequence([DER.oid(oid), DER.set([value])])
    }

    /// Re-tags the hashed SET as `[0] IMPLICIT` for its place in `SignerInfo`.
    private static func implicitAttributes(_ set: [UInt8]) -> [UInt8] {
        var retagged = set
        retagged[0] = DER.Tag.context(0)
        return retagged
    }
}
