import CryptoKit
import Foundation

enum AgentKnowledgeIndexKeyMemoError: Error { case invalidCapacity, closed }

// Owned by one serialized database operation. Only opaque per-operation lookup
// tokens and existing keyed index digests are retained, never the input strings.
final class AgentKnowledgeIndexKeyMemo {
  private let capacity: Int
  private var tokenKey: SymmetricKey? = SymmetricKey(size: .bits256)
  private var values: [String: String] = [:]
  private var recency: [String] = []
  var count: Int { values.count }

  init(capacity: Int = 64) throws {
    guard (1...256).contains(capacity) else { throw AgentKnowledgeIndexKeyMemoError.invalidCapacity }
    self.capacity = capacity
  }
  deinit { close() }
  func key(_ input: String, calculate: () throws -> String) throws -> String {
    guard let tokenKey else { throw AgentKnowledgeIndexKeyMemoError.closed }
    let token = Self.hex(HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: tokenKey))
    if let value = values[token] { touch(token); return value }
    let value = try calculate()
    guard self.tokenKey != nil else { throw AgentKnowledgeIndexKeyMemoError.closed }
    values[token] = value; touch(token)
    if recency.count > capacity { values.removeValue(forKey: recency.removeFirst()) }
    return value
  }
  func close() {
    values.removeAll(keepingCapacity: false); recency.removeAll(keepingCapacity: false); tokenKey = nil
  }
  private func touch(_ token: String) {
    if let index = recency.firstIndex(of: token) { recency.remove(at: index) }
    recency.append(token)
  }
  private static let digits = Array("0123456789abcdef".utf8)
  static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    String(decoding: bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }, as: UTF8.self)
  }
}
