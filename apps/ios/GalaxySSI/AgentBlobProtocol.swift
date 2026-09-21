import CryptoKit
import Foundation
import Security

enum AgentBlobFailure: Error, Equatable {
  case invalid(String)
  case http(String, Int)
}

struct AgentBlobChunk: Codable, Equatable {
  var sha256: String
  var size: Int
}

struct AgentBlobPrivateDescriptor: Codable, Equatable {
  var version = 1
  var blobId: String
  var key: String
  var noncePrefix: String
  var size: Int64
  var sha256: String
  var bindingSHA256: String
  var manifestSHA256: String

  enum CodingKeys: String, CodingKey {
    case version
    case blobId = "blob_id"
    case key
    case noncePrefix = "nonce_prefix"
    case size
    case sha256
    case bindingSHA256 = "binding_sha256"
    case manifestSHA256 = "manifest_sha256"
  }

  func payload() -> [String: Any] {
    [
      "version": version,
      "blob_id": blobId,
      "key": key,
      "nonce_prefix": noncePrefix,
      "size": size,
      "sha256": sha256,
      "binding_sha256": bindingSHA256,
      "manifest_sha256": manifestSHA256
    ]
  }
}

enum AgentBlobProtocol {
  static let version = 1
  static let chunkBytes = 1_024 * 1_024
  static let tagBytes = 16
  static let maximumFileBytes: Int64 = 1_024 * 1_024 * 1_024
  static let maximumChunks = 1_024
  static let maximumManifestBytes = 128 * 1_024
  private static let domain = Data("GalaxySSI-Blob-AEAD-v1\0".utf8)
  private static let bindingKeys = [
    "client_route_id", "conversation_id", "task_id", "turn_id",
    "attachment_id", "transfer_id", "contact_id"
  ]

  static func binding(for attachment: AgentPreparedOutboundAttachment) throws -> [String: String] {
    let payload = attachment.manifestPayload(resume: false)
    let binding = Dictionary(uniqueKeysWithValues: bindingKeys.map { ($0, payload.string($0)) })
    _ = try bindingHash(binding)
    return binding
  }

  static func bindingHash(_ binding: [String: String]) throws -> String {
    guard (1...16).contains(binding.count) else {
      throw AgentBlobFailure.invalid("invalid_transfer_binding")
    }
    for (key, value) in binding {
      guard key.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil,
            (1...256).contains(value.unicodeScalars.count) else {
        throw AgentBlobFailure.invalid("invalid_transfer_binding")
      }
    }
    let encoded = try canonicalJSON(binding)
    guard encoded.count <= 16 * 1_024 else {
      throw AgentBlobFailure.invalid("transfer_binding_too_large")
    }
    return sha256(encoded)
  }

  static func manifest(_ chunks: [AgentBlobChunk]) -> [String: Any] {
    [
      "version": version,
      "chunks": chunks.map { ["sha256": $0.sha256, "size": $0.size] }
    ]
  }

  static func validateManifest(_ payload: [String: Any]) throws -> [AgentBlobChunk] {
    guard Set(payload.keys) == ["version", "chunks"],
          payload["version"] as? Int == version,
          let rawChunks = payload["chunks"] as? [[String: Any]],
          (1...maximumChunks).contains(rawChunks.count) else {
      throw AgentBlobFailure.invalid("invalid_chunk_count")
    }
    return try rawChunks.enumerated().map { index, value in
      guard Set(value.keys) == ["sha256", "size"],
            let digest = value["sha256"] as? String,
            validHex(digest, bytes: 32),
            let size = value["size"] as? Int,
            (tagBytes...(chunkBytes + tagBytes)).contains(size),
            (index == rawChunks.count - 1 || size == chunkBytes + tagBytes),
            (rawChunks.count == 1 || index != rawChunks.count - 1 || size != tagBytes) else {
        throw AgentBlobFailure.invalid("invalid_chunk_descriptor")
      }
      return AgentBlobChunk(sha256: digest, size: size)
    }
  }

  static func seal(
    _ plaintext: Data,
    descriptor: AgentBlobPrivateDescriptor,
    index: Int
  ) throws -> Data {
    let keyData = try data(hex: descriptor.key, bytes: 32)
    let noncePrefix = try data(hex: descriptor.noncePrefix, bytes: 8)
    guard (0..<maximumChunks).contains(index), plaintext.count <= chunkBytes else {
      throw AgentBlobFailure.invalid("invalid_chunk_size")
    }
    let expected = min(chunkBytes, Int(descriptor.size) - index * chunkBytes)
    guard plaintext.count == expected else {
      throw AgentBlobFailure.invalid("invalid_chunk_size")
    }
    var nonceData = noncePrefix
    nonceData.append(bigEndian: Int32(index))
    let nonce = try AES.GCM.Nonce(data: nonceData)
    let sealed = try AES.GCM.seal(
      plaintext,
      using: SymmetricKey(data: keyData),
      nonce: nonce,
      authenticating: try aad(descriptor: descriptor, index: index, plaintextSize: plaintext.count)
    )
    return sealed.ciphertext + sealed.tag
  }

  static func open(
    _ encrypted: Data,
    descriptor: AgentBlobPrivateDescriptor,
    index: Int
  ) throws -> Data {
    let keyData = try data(hex: descriptor.key, bytes: 32)
    let noncePrefix = try data(hex: descriptor.noncePrefix, bytes: 8)
    guard (0..<maximumChunks).contains(index), encrypted.count >= tagBytes else {
      throw AgentBlobFailure.invalid("invalid_chunk_size")
    }
    let plaintextSize = encrypted.count - tagBytes
    let expected = min(chunkBytes, Int(descriptor.size) - index * chunkBytes)
    guard plaintextSize == expected else {
      throw AgentBlobFailure.invalid("invalid_chunk_size")
    }
    var nonceData = noncePrefix
    nonceData.append(bigEndian: Int32(index))
    let ciphertext = encrypted.prefix(plaintextSize)
    let tag = encrypted.suffix(tagBytes)
    do {
      return try AES.GCM.open(
        AES.GCM.SealedBox(
          nonce: AES.GCM.Nonce(data: nonceData),
          ciphertext: ciphertext,
          tag: tag
        ),
        using: SymmetricKey(data: keyData),
        authenticating: try aad(
          descriptor: descriptor,
          index: index,
          plaintextSize: plaintextSize
        )
      )
    } catch {
      throw AgentBlobFailure.invalid("chunk_authentication_failed")
    }
  }

  static func missingIndices(bitmap: String, count: Int) throws -> [Int] {
    guard (1...maximumChunks).contains(count) else {
      throw AgentBlobFailure.invalid("invalid_chunk_count")
    }
    let bits = try data(hex: bitmap, bytes: (count + 7) / 8)
    if count % 8 != 0, let last = bits.last, Int(last) >> (count % 8) != 0 {
      throw AgentBlobFailure.invalid("invalid_missing_bitmap")
    }
    return (0..<count).filter { index in
      bits[index / 8] & UInt8(1 << (index % 8)) != 0
    }
  }

  static func offer(
    relay: URL,
    readToken: String,
    descriptor: AgentBlobPrivateDescriptor
  ) -> [String: Any] {
    [
      "version": version,
      "relay": relay.absoluteString,
      "private": descriptor.payload(),
      "read_token": readToken
    ]
  }

  static func offerPayload(
    attachment: AgentPreparedOutboundAttachment,
    offer: [String: Any]
  ) throws -> [String: Any] {
    var payload = attachment.manifestPayload(resume: false)
    payload["type"] = "input_attachment_blob_offer"
    payload["blob_offer"] = offer
    payload.removeValue(forKey: "resume")
    payload.removeValue(forKey: "eager_chunks")
    payload.removeValue(forKey: "time")
    guard try canonicalJSON(payload).count <= 32 * 1_024 else {
      throw AgentBlobFailure.invalid("input_blob_offer_too_large")
    }
    return payload
  }

  static func receiptMatches(
    attachment: AgentPreparedOutboundAttachment,
    receipt: [String: Any]
  ) -> Bool {
    let manifest = attachment.manifestPayload(resume: false)
    guard receipt.string("status") == "stored",
          receipt.int64("size_bytes") == manifest.int64("size_bytes") else { return false }
    for key in bindingKeys + ["sha256"] {
      guard !manifest.string(key).isEmpty, manifest.string(key) == receipt.string(key) else { return false }
    }
    let clientMessageId = manifest.string("client_message_id")
    return clientMessageId.isEmpty || clientMessageId == receipt.string("source_message_id")
  }

  static func canonicalJSON(_ value: Any) throws -> Data {
    Data(try canonicalString(value).utf8)
  }

  static func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }

  static func randomHex(bytes: Int) throws -> String {
    var value = Data(count: bytes)
    let result = value.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, bytes, buffer.baseAddress!)
    }
    guard result == errSecSuccess else {
      throw AgentBlobFailure.invalid("secure_random_unavailable")
    }
    return value.hexString()
  }

  static func validHex(_ value: String, bytes: Int) -> Bool {
    value.count == bytes * 2 &&
      value.range(of: "^[a-f0-9]+$", options: .regularExpression) != nil
  }

  private static func aad(
    descriptor: AgentBlobPrivateDescriptor,
    index: Int,
    plaintextSize: Int
  ) throws -> Data {
    var result = domain
    result.append(try data(hex: descriptor.blobId, bytes: 16))
    result.append(try data(hex: descriptor.bindingSHA256, bytes: 32))
    result.append(bigEndian: descriptor.size)
    result.append(bigEndian: Int32(chunkBytes))
    result.append(try data(hex: descriptor.sha256, bytes: 32))
    result.append(bigEndian: Int32(index))
    result.append(bigEndian: Int32(plaintextSize))
    return result
  }

  private static func data(hex: String, bytes: Int) throws -> Data {
    guard validHex(hex, bytes: bytes) else {
      throw AgentBlobFailure.invalid("invalid_identifier")
    }
    var result = Data(capacity: bytes)
    var cursor = hex.startIndex
    for _ in 0..<bytes {
      let end = hex.index(cursor, offsetBy: 2)
      guard let byte = UInt8(hex[cursor..<end], radix: 16) else {
        throw AgentBlobFailure.invalid("invalid_identifier")
      }
      result.append(byte)
      cursor = end
    }
    return result
  }

  private static func canonicalString(_ value: Any) throws -> String {
    switch value {
    case let object as [String: Any]:
      return try object.keys.sorted().map { key in
        "\(quoted(key)):\(try canonicalString(object[key]!))"
      }.joined(separator: ",").wrapped(prefix: "{", suffix: "}")
    case let object as [String: String]:
      return try canonicalString(object.mapValues { $0 as Any })
    case let array as [Any]:
      return try array.map(canonicalString).joined(separator: ",").wrapped(prefix: "[", suffix: "]")
    case let value as String:
      return quoted(value)
    case let value as Bool:
      return value ? "true" : "false"
    case let value as Int:
      return String(value)
    case let value as Int64:
      return String(value)
    default:
      throw AgentBlobFailure.invalid("invalid_canonical_json")
    }
  }

  private static func quoted(_ value: String) -> String {
    var result = "\""
    for unit in value.utf16 {
      switch unit {
      case 0x22: result += "\\\""
      case 0x5c: result += "\\\\"
      case 0x08: result += "\\b"
      case 0x0c: result += "\\f"
      case 0x0a: result += "\\n"
      case 0x0d: result += "\\r"
      case 0x09: result += "\\t"
      case 0x20..<0x7f: result.unicodeScalars.append(UnicodeScalar(unit)!)
      default: result += String(format: "\\u%04x", unit)
      }
    }
    return result + "\""
  }
}

private extension Data {
  mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
    var encoded = value.bigEndian
    Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
  }
}

private extension String {
  func wrapped(prefix: String, suffix: String) -> String { prefix + self + suffix }
}

extension Dictionary where Key == String, Value == Any {
  func int64(_ key: String) -> Int64 {
    if let value = self[key] as? Int64 { return value }
    if let value = self[key] as? Int { return Int64(value) }
    if let value = self[key] as? NSNumber { return value.int64Value }
    return 0
  }
}
