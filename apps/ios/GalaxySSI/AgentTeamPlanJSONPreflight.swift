import Foundation

// Foundation normalizes duplicate keys and numeric lexemes. Check the bounded wire
// contract first, then leave typed JSON decoding and graph validation to existing APIs.
struct AgentTeamPlanJSONPreflight {
  private let bytes: [UInt8]
  private var cursor = 0
  private var nodes = 0
  init(_ text: String) { bytes = Array(text.utf8) }
  mutating func validate() throws {
    try value(depth: 0); whitespace()
    guard cursor == bytes.count else { throw AgentConversationalTeamProtocol.Failure.plan }
  }
  private mutating func whitespace() {
    while cursor < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[cursor]) { cursor += 1 }
  }
  private mutating func consume(_ byte: UInt8) -> Bool {
    whitespace()
    guard cursor < bytes.count, bytes[cursor] == byte else { return false }
    cursor += 1; return true
  }
  private mutating func value(depth: Int) throws {
    nodes += 1; whitespace()
    guard depth <= 5, nodes <= 100, cursor < bytes.count else { throw AgentConversationalTeamProtocol.Failure.plan }
    switch bytes[cursor] {
    case 123:
      cursor += 1
      if consume(125) { return }
      var keys = Set<String>()
      repeat {
        let key = try string()
        guard keys.insert(key).inserted, keys.count <= 10, consume(58) else { throw AgentConversationalTeamProtocol.Failure.plan }
        try value(depth: depth + 1)
        if consume(125) { return }
        guard consume(44) else { throw AgentConversationalTeamProtocol.Failure.plan }
      } while true
    case 91:
      cursor += 1
      if consume(93) { return }
      var entries = 0
      repeat {
        entries += 1
        guard entries <= 10 else { throw AgentConversationalTeamProtocol.Failure.plan }
        try value(depth: depth + 1)
        if consume(93) { return }
        guard consume(44) else { throw AgentConversationalTeamProtocol.Failure.plan }
      } while true
    case 34: _ = try string()
    default:
      let start = cursor
      while cursor < bytes.count && ![UInt8(9), 10, 13, 32, 44, 93, 125].contains(bytes[cursor]) { cursor += 1 }
      let token = String(decoding: bytes[start..<cursor], as: UTF8.self)
      // Parent references are the only numerical values in this protocol.
      guard ["true", "false", "null"].contains(token) || (Int(token).map { (1...10).contains($0) && String($0) == token } == true) else {
        throw AgentConversationalTeamProtocol.Failure.plan
      }
    }
  }
  private mutating func string() throws -> String {
    whitespace(); let start = cursor
    guard cursor < bytes.count, bytes[cursor] == 34 else { throw AgentConversationalTeamProtocol.Failure.plan }
    cursor += 1
    while cursor < bytes.count {
      let byte = bytes[cursor]; cursor += 1
      if byte == 92 {
        guard cursor < bytes.count else { throw AgentConversationalTeamProtocol.Failure.plan }
        cursor += 1
      } else if byte == 34 {
        let token = Data(bytes[start..<cursor])
        guard let value = try? JSONDecoder().decode(String.self, from: token), value.utf16.count <= 400 else {
          throw AgentConversationalTeamProtocol.Failure.plan
        }
        return value
      }
    }
    throw AgentConversationalTeamProtocol.Failure.plan
  }
}
