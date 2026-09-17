import CryptoKit
import Foundation
import PassKit
import Testing

@testable import DaGym

/// The pass itself: `pass.json` mapping, the CMS `SignedData` shape, and the service's
/// "no identity, no button" contract. Signature tests need the bundled `pass.p12`, which is
/// gitignored — they run only where it is present.
@Suite("Wallet pass")
struct WalletPassTests {
    private static let identityURL = Bundle.main.url(forResource: "pass", withExtension: "p12")
    private static let intermediateURL = Bundle.main.url(forResource: "AppleWWDRG4", withExtension: "pem")

    private func card(_ symbology: GymCardSymbology, value: String = "1234567890128") -> GymCardInfo {
        GymCardInfo(id: UUID(), name: "PureGym", value: value, symbology: symbology, lastUsedAt: nil)
    }

    @Test("Wallet-native symbologies keep their format; every other one becomes Code 128 with altText")
    func symbologyMapping() throws {
        let expected: [GymCardSymbology: (WalletBarcodeFormat, Bool)] = [
            .qr: (.qr, true), .aztec: (.aztec, true), .pdf417: (.pdf417, true), .code128: (.code128, true),
            .ean13: (.code128, false), .ean8: (.code128, false), .upce: (.code128, false),
            .code39: (.code128, false), .code93: (.code128, false), .itf14: (.code128, false),
            .dataMatrix: (.qr, false)
        ]
        for symbology in GymCardSymbology.allCases {
            let (format, native) = try #require(expected[symbology])
            let json = try WalletPassJSON(card: card(symbology), accent: .coral)
            #expect(json.barcode.format == format, "\(symbology)")
            #expect(symbology.isWalletNative == native, "\(symbology)")
            #expect(json.barcode.altText == (native ? nil : "1234567890128"), "\(symbology)")
            #expect(json.barcodes == [json.barcode])
            #expect(json.barcode.messageEncoding == "iso-8859-1")
        }
    }

    @Test("serial is the card id; colours come from the accent; fields carry name and number")
    func passJSONContents() throws {
        let info = card(.qr, value: "AB-42")
        let json = try WalletPassJSON(card: info, accent: .ice)
        #expect(json.serialNumber == info.id.uuidString)
        #expect(json.passTypeIdentifier == "pass.dev.abdirahmanmohamed.dagym")
        #expect(json.teamIdentifier == "5AF2LBU5A3")
        #expect(json.description == "PureGym membership")
        #expect(json.backgroundColor == WalletPassStyle.rgb(DGAccent.ice.baseHex(dark: true)))
        #expect(json.backgroundColor.hasPrefix("rgb("))
        #expect(json.foregroundColor == "rgb(18, 18, 19)")
        #expect(json.generic.primaryFields.first?.value == "PureGym")
        #expect(json.generic.secondaryFields.first?.value == "AB-42")
        let text = try #require(String(data: json.encoded(), encoding: .utf8))
        #expect(text.contains("\"formatVersion\":1"))
        #expect(text.contains("\"organizationName\":\"DaGym\""))
        #expect(throws: WalletPassError.valueNotEncodable) {
            try WalletPassJSON(card: card(.code128, value: "€"), accent: .coral)
        }
    }

    @Test("manifest lists the SHA-1 of every file")
    func manifestHashes() throws {
        let manifest = try WalletPassBuilder.manifest(["pass.json": Data("{}".utf8)])
        let decoded = try JSONDecoder().decode([String: String].self, from: manifest)
        #expect(decoded == ["pass.json": "bf21a9e8fbc5a3846fb05b4fa0859e0917b2202f"])
    }

    @Test("SignedData carries id-data, sha256, both certificates and a messageDigest of the manifest")
    func cmsStructure() throws {
        let intermediate = try #require(Self.intermediateURL.flatMap { try? Data(contentsOf: $0) })
        let certificate = try #require(WalletPassSigner.derFromPEM(intermediate))
        let manifest = Data("{\"pass.json\":\"00\"}".utf8)
        let signer = CMSSignature.Signer(certificateDER: certificate, chainDER: [certificate]) { _ in
            Data([0xDE, 0xAD])
        }
        let signature = try CMSSignature.detached(message: manifest, signer: signer)

        let contentInfo = try DERParser.parseOne([UInt8](signature))
        #expect(contentInfo.children.first?.oidString == CMSOID.signedData)
        let signedData = try #require(contentInfo.children.last?.children.first)
        let fields = signedData.children
        #expect(fields.count == 5)
        #expect(fields[0].integerValue == 1)
        #expect(fields[1].children.first?.children.first?.oidString == CMSOID.sha256)
        #expect(fields[2].children == [try DERParser.parseOne(DER.oid(CMSOID.data))])
        #expect(fields[3].tag == DER.Tag.context(0))
        #expect(fields[3].children.count == 2)

        let signerInfo = try #require(fields[4].children.first).children
        #expect(signerInfo[0].integerValue == 1)
        let identity = try CertificateIdentity(certificateDER: certificate)
        #expect(signerInfo[1].children.map(\.raw) == [identity.issuerDER, identity.serialDER])
        let attributes = signerInfo[3].children
        let digestAttribute = try #require(
            attributes.first { $0.children.first?.oidString == CMSOID.messageDigest }
        )
        let digest = [UInt8](SHA256.hash(data: manifest))
        #expect(digestAttribute.children.last?.children.first?.content == digest)
        #expect(attributes.contains { $0.children.first?.oidString == CMSOID.contentType })
        #expect(attributes.contains { $0.children.first?.oidString == CMSOID.signingTime })
        #expect(signerInfo[4].children.first?.oidString == CMSOID.rsaEncryption)
        #expect(signerInfo[5].content == [0xDE, 0xAD])
    }

    @Test("the bundled identity signs signedAttrs so its own public key verifies them",
          .enabled(if: identityURL != nil))
    func signatureVerifies() throws {
        let pkcs12 = try Data(contentsOf: #require(Self.identityURL))
        let intermediate = Self.intermediateURL.flatMap { try? Data(contentsOf: $0) }
        let signer = try WalletPassSigner(
            pkcs12: pkcs12, passphrase: WalletPassService.passphrase, intermediatePEM: intermediate
        )
        #expect(signer.chainDER.count == 1)
        let manifest = Data("{\"pass.json\":\"00\"}".utf8)
        let signature = try signer.signature(forManifest: manifest)

        let signedData = try #require(DERParser.parseOne([UInt8](signature)).children.last?.children.first)
        let signerInfo = try #require(signedData.children[4].children.first).children
        var attributes = signerInfo[3].raw
        attributes[0] = DER.Tag.set
        #expect(signer.verify(signature: Data(signerInfo[5].content), over: Data(attributes)))
        #expect(!signer.verify(signature: Data(signerInfo[5].content), over: manifest))
    }

    @Test("service is unavailable without the identity resource")
    @MainActor
    func serviceUnavailableWithoutIdentity() async {
        let service = WalletPassService(identityURL: nil, intermediateURL: nil)
        #expect(!service.isAvailable)
        await #expect(throws: WalletPassError.unavailable) {
            try await service.pass(for: card(.qr))
        }
    }
}
