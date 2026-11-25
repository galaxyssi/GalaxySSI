import Foundation

enum AgentKnowledgeNativeError: Error {
  case invalidRecord
  case nativeFailure
  case closed
}

struct AgentKnowledgeNativeEvent: Equatable {
  var sequence: Int64
  var previous: Int64
  var key: String
  var revision: String
  var chunks: Int64
  var removed: Bool

  init(change: AgentKnowledgeVectorChange) {
    sequence = change.sequence
    previous = change.previousSequence
    key = change.itemHash
    revision = change.sourceRevisionHash
    chunks = Int64(change.chunkCount)
    removed = change.operation == .removal
  }

  init(sequence: Int64, previous: Int64, key: String, revision: String, chunks: Int64, removed: Bool) {
    self.sequence = sequence; self.previous = previous; self.key = key
    self.revision = revision; self.chunks = chunks; self.removed = removed
  }
}

struct AgentKnowledgeNativeCheckpoint: Equatable {
  struct Pending: Equatable {
    var event: AgentKnowledgeNativeEvent
    var next: Int64
  }
  var epoch: String
  var last: AgentKnowledgeNativeEvent?
  var pending: Pending?
  var sequence: Int64 { last?.sequence ?? 0 }
}

struct AgentKnowledgeNativeMatch: Equatable {
  var key: String
  var revision: String
  var sequence: Int64
  var ordinal: Int64
  var startUTF16: Int
  var endUTF16: Int
  var similarity: Float
}

enum AgentKnowledgeNativeWire {
  static func event(_ event: AgentKnowledgeNativeEvent) throws -> Data {
    guard event.previous >= 0, event.sequence > event.previous, event.chunks >= 0 else {
      throw AgentKnowledgeNativeError.invalidRecord
    }
    var data = Data("GSE1".utf8)
    append(event.sequence, to: &data)
    append(event.previous, to: &data)
    data.append(try hex(event.key, bytes: 32))
    data.append(try hex(event.revision, bytes: 32))
    append(event.chunks, to: &data)
    data.append(event.removed ? 1 : 0)
    return data
  }

  static func epoch(_ text: String) throws -> Data {
    guard var uuid = UUID(uuidString: text)?.uuid else { throw AgentKnowledgeNativeError.invalidRecord }
    return withUnsafeBytes(of: &uuid) { Data($0) }
  }

  static func checkpoint(_ data: Data) throws -> AgentKnowledgeNativeCheckpoint {
    guard (22...208).contains(data.count) else { throw AgentKnowledgeNativeError.invalidRecord }
    var reader = Reader(data)
    try reader.magic("GSC1")
    let epoch = try reader.hash(16)
    let last: AgentKnowledgeNativeEvent?
    if try reader.flag() { last = try reader.event() } else { last = nil }
    let pending: AgentKnowledgeNativeCheckpoint.Pending?
    if try reader.flag() {
      pending = try AgentKnowledgeNativeCheckpoint.Pending(event: reader.event(), next: reader.number())
    } else { pending = nil }
    try reader.finish()
    let result = AgentKnowledgeNativeCheckpoint(epoch: epoch, last: last, pending: pending)
    if let pending {
      guard !pending.event.removed, pending.event.previous == result.sequence,
        pending.next < pending.event.chunks else { throw AgentKnowledgeNativeError.invalidRecord }
    }
    return result
  }

  static func matches(_ data: Data) throws -> [AgentKnowledgeNativeMatch] {
    guard (8...(8 + 256 * 104)).contains(data.count) else { throw AgentKnowledgeNativeError.invalidRecord }
    var reader = Reader(data)
    try reader.magic("GSM1")
    let count = try reader.unsigned(bytes: 4)
    guard count <= 256, data.count == 8 + Int(count) * 104 else { throw AgentKnowledgeNativeError.invalidRecord }
    var result: [AgentKnowledgeNativeMatch] = []
    for _ in 0..<Int(count) {
      try reader.magic("GSN1")
      let key = try reader.hash(32), revision = try reader.hash(32)
      let sequence = try reader.number(), ordinal = try reader.number()
      let start = try reader.number(), end = try reader.number()
      let similarity = Float(bitPattern: UInt32(try reader.unsigned(bytes: 4)))
      guard sequence > 0, start < end, similarity.isFinite, (-1...1).contains(similarity) else {
        throw AgentKnowledgeNativeError.invalidRecord
      }
      result.append(AgentKnowledgeNativeMatch(key: key, revision: revision, sequence: sequence,
        ordinal: ordinal, startUTF16: Int(start), endUTF16: Int(end), similarity: similarity))
    }
    try reader.finish()
    return result
  }

  private static func hex(_ text: String, bytes: Int) throws -> Data {
    let chars = Array(text.utf8)
    guard chars.count == bytes * 2 else { throw AgentKnowledgeNativeError.invalidRecord }
    func digit(_ byte: UInt8) throws -> UInt8 {
      if (48...57).contains(byte) { return byte - 48 }
      if (97...102).contains(byte) { return byte - 87 }
      throw AgentKnowledgeNativeError.invalidRecord
    }
    return try Data((0..<bytes).map { try digit(chars[$0 * 2]) * 16 + digit(chars[$0 * 2 + 1]) })
  }

  private static func append(_ value: Int64, to data: inout Data) {
    var number = UInt64(value).littleEndian
    withUnsafeBytes(of: &number) { data.append(contentsOf: $0) }
  }

  private struct Reader {
    private var bytes: [UInt8]
    private var index = 0
    init(_ data: Data) { bytes = Array(data) }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
      guard count >= 0, count <= bytes.count - index else { throw AgentKnowledgeNativeError.invalidRecord }
      let start = index
      index += count
      return bytes[start..<index]
    }
    mutating func magic(_ text: String) throws {
      guard Array(try take(text.utf8.count)) == Array(text.utf8) else { throw AgentKnowledgeNativeError.invalidRecord }
    }
    mutating func unsigned(bytes count: Int) throws -> UInt64 {
      try take(count).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
    }
    mutating func number() throws -> Int64 {
      let value = try unsigned(bytes: 8)
      guard value <= UInt64(Int64.max) else { throw AgentKnowledgeNativeError.invalidRecord }
      return Int64(value)
    }
    mutating func hash(_ count: Int) throws -> String {
      try take(count).map { String(format: "%02x", $0) }.joined()
    }
    mutating func flag() throws -> Bool {
      let byte = try take(1).first!
      guard byte <= 1 else { throw AgentKnowledgeNativeError.invalidRecord }
      return byte == 1
    }
    mutating func event() throws -> AgentKnowledgeNativeEvent {
      let event = try AgentKnowledgeNativeEvent(sequence: number(), previous: number(), key: hash(32),
        revision: hash(32), chunks: number(), removed: flag())
      guard event.sequence > event.previous else { throw AgentKnowledgeNativeError.invalidRecord }
      return event
    }
    func finish() throws {
      guard index == bytes.count else { throw AgentKnowledgeNativeError.invalidRecord }
    }
  }
}
