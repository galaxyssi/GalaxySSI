import CryptoKit
import Foundation
import Security

enum AgentIOSRuntimePackTrust {
  static func verify(
    manifest: AgentRuntimePackManifest,
    bundle: Bundle = .main
  ) -> Bool {
    guard let signature = Data(
      base64Encoded: manifest.signature,
      options: [.ignoreUnknownCharacters]
    ), !signature.isEmpty,
    let documentURL = bundle.url(forResource: "trust-anchors", withExtension: "json"),
    let documentData = try? Data(contentsOf: documentURL),
    let document = try? JSONDecoder().decode(TrustAnchorDocument.self, from: documentData),
    document.formatVersion == 1 else {
      return false
    }

    return document.certificates.prefix(maxTrustAnchors).contains { certificateBase64 in
      guard let certificateData = Data(base64Encoded: certificateBase64),
            let certificate = SecCertificateCreateWithData(nil, certificateData as CFData),
            let publicKey = SecCertificateCopyKey(certificate) else {
        return false
      }
      let keyId = SHA256.hash(data: Data(SecCertificateCopyData(certificate) as Data))
        .map { String(format: "%02x", $0) }
        .joined()
      guard keyId.caseInsensitiveCompare(manifest.signatureKeyId) == .orderedSame else {
        return false
      }
      return verifySignature(
        signature,
        payload: manifest.signingPayload(),
        with: publicKey
      )
    }
  }

  private static func verifySignature(
    _ signature: Data,
    payload: Data,
    with key: SecKey
  ) -> Bool {
    let algorithms: [SecKeyAlgorithm] = [
      .rsaSignatureMessagePKCS1v15SHA256,
      .ecdsaSignatureMessageX962SHA256
    ]
    return algorithms.contains { algorithm in
      guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else { return false }
      var error: Unmanaged<CFError>?
      let valid = SecKeyVerifySignature(
        key,
        algorithm,
        payload as CFData,
        signature as CFData,
        &error
      )
      error?.release()
      return valid
    }
  }

  private struct TrustAnchorDocument: Decodable {
    var formatVersion: Int
    var certificates: [String]

    enum CodingKeys: String, CodingKey {
      case formatVersion = "format_version"
      case certificates
    }
  }

  private static let maxTrustAnchors = 8
}
