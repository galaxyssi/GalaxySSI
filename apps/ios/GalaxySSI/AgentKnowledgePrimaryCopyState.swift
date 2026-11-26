import CryptoKit
import Foundation

enum AgentKnowledgeStorageYield: Error { case exhausted }

struct AgentKnowledgePrimaryCopyState: Codable {
  static let framePage = 16
  static let emptyHash = String(repeating: "0", count: 64)
  var version = 1
  var entry = UUID().uuidString.lowercased()
  var copied = 0
  var copiedPlainBytes: Int64 = 0
  var storedBytes: Int64 = 0
  var copiedHash = emptyHash
  var verified = 0
  var verifiedPlainBytes: Int64 = 0
  var verifiedHash = emptyHash

  func validate(_ source: AgentKnowledgePrimaryPartitions.Reference) throws {
    guard version == 1, UUID(uuidString: entry)?.uuidString.lowercased() == entry, entry != source.entry,
          source.frames > 0, (0...source.frames).contains(copied), (0...copied).contains(verified),
          copiedPlainBytes == (try Self.bytes(copied, source)), verifiedPlainBytes == (try Self.bytes(verified, source)),
          storedBytes >= Int64(copied), verified == 0 || copied == source.frames,
          Self.digest(copiedHash), Self.digest(verifiedHash), copied != 0 || copiedHash == Self.emptyHash,
          verified != 0 || verifiedHash == Self.emptyHash else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let upper = Int64(copied).multipliedReportingOverflow(by: 192 * 1_024)
    guard upper.overflow || storedBytes <= upper.partialValue else { throw AgentKnowledgeDatabaseError.corruptRecord }
  }
  private static func bytes(_ frames: Int, _ source: AgentKnowledgePrimaryPartitions.Reference) throws -> Int64 {
    if frames == source.frames { return source.plainBytes }
    let value = Int64(frames).multipliedReportingOverflow(by: Int64(AgentKnowledgePrimaryFrameCodec.maximumPlainBytes))
    guard !value.overflow, value.partialValue < source.plainBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return value.partialValue
  }
  static func chain(_ previous: String, ordinal: Int, encoded: Data) throws -> String {
    guard digest(previous), ordinal >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let chars = Array(previous.utf8)
    var bytes = Data(capacity: 40 + encoded.count)
    for offset in stride(from: 0, to: 64, by: 2) {
      guard let value = UInt8(String(decoding: chars[offset...offset + 1], as: UTF8.self), radix: 16) else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      bytes.append(value)
    }
    var number = UInt64(ordinal).bigEndian
    withUnsafeBytes(of: &number) { bytes.append(contentsOf: $0) }
    bytes.append(encoded)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  private static func digest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
