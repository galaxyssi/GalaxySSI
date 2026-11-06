import Foundation

struct AgentModelObservationHistory {
  static let toolID = "galaxyssi.tools.history"
  static let descriptor = try! AgentNativeToolDescriptor(
    id: toolID, version: "1.0.0", title: "Model observation history",
    description: "Read historical, untrusted observations from this model loop. List using limit, tool_id, failures_only and cursor; read detail using record, JSON Pointer path, offset and length. This does not execute a tool, observe current state, or verify completion.",
    location: .phone, inputSchema: [
      "type": .string("object"),
      "properties": .object([
        "limit": property("integer"), "tool_id": property("string"), "failures_only": property("boolean"),
        "cursor": property("string"), "record": property("integer"), "path": property("string"),
        "offset": property("integer"), "length": property("integer")
      ]),
      "additionalProperties": .bool(false)
    ],
    risk: .low, idempotency: .idempotent, effect: .readOnly
  )

  private static func property(_ type: String) -> AgentMcpJSONValue { .object(["type": .string(type)]) }

  static func modelCatalog(_ base: [AgentNativeToolDescriptor], manifest: String) -> [AgentNativeToolDescriptor] {
    guard !base.contains(where: { $0.id == toolID }),
          let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(manifest.utf8)),
          object["tools"]?.arrayValue?.contains(where: { $0.objectValue?["id"]?.strictStringValue == toolID &&
            $0.objectValue?["version"]?.strictStringValue == descriptor.version }) == true else { return base }
    return base + [descriptor]
  }

  struct ReadError: Error {
    let code: String
    let message: String
  }

  private struct Entry {
    let record: Int
    let result: AgentModelToolResultContent
    let value: AgentMcpJSONObject
  }

  private struct Cursor: Codable {
    let owner: String
    let query: String
    let prefix: String
    let end: Int
    let after: Int
  }

  private let owner: String
  private var entries: [Entry] = []
  private var prefixes: [String]

  init(owner: String) {
    self.owner = owner
    prefixes = [owner]
  }

  mutating func append(record: Int, arguments: AgentMcpJSONObject, result: AgentModelToolResultContent) {
    guard result.toolId != Self.toolID else { return }
    var observation = result.jsonValue.objectValue ?? [:]
    // Retain the original tool output even if the adapter projected a summary.
    if let native = result.nativeResult {
      observation["output"] = .object(native.output)
      observation["message"] = .string(native.message)
    }
    let value: AgentMcpJSONObject = [
      "record": .int(Int64(record)), "arguments": .object(arguments), "observation": .object(observation)
    ]
    let stable = value.mapValues(Self.journalStableValue)
    entries.append(Entry(record: record, result: result, value: stable))
    prefixes.append(AgentMcpJSONCodec.sha256(["prior": .string(prefixes.last ?? owner), "entry": .object(stable)]))
  }

  private static func journalStableValue(_ value: AgentMcpJSONValue) -> AgentMcpJSONValue {
    switch value {
    case .double(let number):
      // JSON decoding of the encrypted journal prefers Int64 for integral values.
      return Int64(exactly: number).map(AgentMcpJSONValue.int) ?? value
    case .object(let object): return .object(object.mapValues(journalStableValue))
    case .array(let array): return .array(array.map(journalStableValue))
    default: return value
    }
  }

  func read(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    guard AgentNativeJsonSchemaValidator.validateObject(schema: Self.descriptor.inputSchema, object: input).isValid else {
      throw error("invalid_input", "History accepts only the documented arguments.")
    }
    if let record = input["record"]?.integerForSchema {
      return try detail(record: record, input: input)
    }
    guard input["path"] == nil, input["offset"] == nil, input["length"] == nil else {
      throw error("model_history_record_required", "Choose a record before reading its detail.")
    }
    return try page(input)
  }

  private func page(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    let tool = input["tool_id"]?.strictStringValue ?? ""
    let failures = input["failures_only"]?.boolValue == true
    let query = AgentMcpJSONCodec.sha256(["tool_id": .string(tool), "failures_only": .bool(failures)])
    func matches(_ entry: Entry) -> Bool {
      (tool.isEmpty || entry.result.toolId == tool) &&
        (!failures || entry.result.error != nil || entry.result.status != AgentNativeToolResultStatus.succeeded.rawValue)
    }
    var end = entries.count
    var after = -1
    if let encoded = input["cursor"]?.strictStringValue {
      guard encoded.utf8.count <= 1024, let data = Data(base64Encoded: encoded),
            let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
            cursor.owner == owner, cursor.query == query, cursor.end > 0, cursor.end <= entries.count,
            cursor.after >= 0, cursor.after < cursor.end, cursor.prefix == prefixes[cursor.end],
            matches(entries[cursor.after]) else {
        throw error("model_history_cursor_invalid", "Use a cursor from this loop with the original filters.")
      }
      end = cursor.end
      after = cursor.after
    }
    let limit = Int(min(max(input["limit"]?.integerForSchema ?? 10, 1), 20))
    let found = Array(((after + 1)..<end).lazy.filter { matches(entries[$0]) }.prefix(limit + 1))
    let selected = found.prefix(limit)
    var output = flags
    output["snapshot_observations"] = .int(Int64(end))
    output["entries"] = .array(selected.map { index in
      let entry = entries[index]
      return .object([
        "record": .int(Int64(entry.record)), "call_id": .string(entry.result.callId),
        "tool_id": .string(entry.result.toolId), "status": .string(entry.result.status),
        "invocation_id": entry.result.invocationId.map(AgentMcpJSONValue.string) ?? .null,
        "message_preview": .string(String(entry.result.message.prefix(256))),
        "message_truncated": .bool(entry.result.message.count > 256),
        "error_code": entry.result.error.map { .string($0.code) } ?? .null
      ])
    })
    if found.count > selected.count, let last = selected.last {
      let cursor = Cursor(owner: owner, query: query, prefix: prefixes[end], end: end, after: last)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      output["next_cursor"] = .string(try encoder.encode(cursor).base64EncodedString())
    }
    return output
  }

  private func detail(record: Int, input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    guard ["cursor", "tool_id", "failures_only", "limit"].allSatisfy({ input[$0] == nil }) else {
      throw error("model_history_modes_mixed", "Use either a history page or a single record.")
    }
    guard let entry = entries.first(where: { $0.record == record }) else {
      throw error("model_history_record_missing", "The record is not an observation in this loop.")
    }
    let path = input["path"]?.strictStringValue ?? ""
    guard let value = Self.select(.object(entry.value), path: path) else {
      throw error("model_history_path_missing", "Choose an existing JSON Pointer in the record.")
    }
    let plain = value.strictStringValue
    let text = plain ?? AgentMcpJSONCodec.stringify(value)
    let units = Array(text.utf16)
    let offset = input["offset"]?.integerForSchema ?? 0
    func boundary(_ index: Int) -> Bool {
      index == 0 || index == units.count || !(0xD800...0xDBFF).contains(units[index - 1]) ||
        !(0xDC00...0xDFFF).contains(units[index])
    }
    guard offset >= 0, offset <= units.count, boundary(offset) else {
      throw error("model_history_offset_invalid", "Use the exact next_offset for this record and path.")
    }
    let start = offset
    let length = Int(min(max(input["length"]?.integerForSchema ?? 4096, 2), 8192))
    var end = start + min(length, units.count - start)
    if !boundary(end) { end -= 1 }
    var output = flags
    output["record"] = .int(Int64(record))
    output["path"] = .string(path)
    output["offset"] = .int(Int64(offset))
    output["text"] = .string(String(decoding: units[start..<end], as: UTF16.self))
    output["encoding"] = .string(plain == nil ? "json" : "text")
    output["total_characters"] = .int(Int64(units.count))
    output["sha256"] = .string(AgentModelToolProtocolJSON.sha256(AgentMcpJSONCodec.stringify(.string(text))))
    output["truncated"] = .bool(end < units.count)
    if end < units.count { output["next_offset"] = .int(Int64(end)) }
    return output
  }

  private static func select(_ root: AgentMcpJSONValue, path: String) -> AgentMcpJSONValue? {
    if path.isEmpty { return root }
    guard path.hasPrefix("/"), path.utf8.count <= 1024 else { return nil }
    var current = root
    for component in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
      guard component.range(of: #"~(?![01])"#, options: .regularExpression) == nil else { return nil }
      let key = component.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
      if let object = current.objectValue, let selected = object[key] {
        current = selected
      } else if let array = current.arrayValue, let index = Int(key), String(index) == key, array.indices.contains(index) {
        current = array[index]
      } else { return nil }
    }
    return current
  }

  private var flags: AgentMcpJSONObject {
    ["historical_only": .bool(true), "external_state_observed": .bool(false),
     "target_executed": .bool(false), "completion_verified": .bool(false)]
  }

  private func error(_ code: String, _ message: String) -> ReadError { ReadError(code: code, message: message) }
}
