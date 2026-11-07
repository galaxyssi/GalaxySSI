import Foundation

enum AgentCollaborationWorkflowConditions {
  struct Condition {
    let fields: AgentMcpJSONObject
    var id: String { fields.string("id") }

    init?(_ value: AgentMcpJSONValue, inputNames: Set<String>) {
      guard let fields = value.objectValue,
            Set(fields.keys) == ["id", "input", "pointer", "operator", "value", "rationale"],
            let id = fields["id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 160,
            let rationale = fields["rationale"]?.strictStringValue, !rationale.isBlank, rationale.utf8.count <= 1_024,
            let input = fields["input"]?.strictStringValue, inputNames.contains(input),
            let pointer = fields["pointer"]?.strictStringValue, pointer.utf8.count <= 1_024,
            pointer.isEmpty || pointer.hasPrefix("/"), pointer.range(of: "~(?![01])", options: .regularExpression) == nil,
            let op = fields["operator"]?.strictStringValue, ["eq", "neq", "lt", "lte", "gt", "gte"].contains(op),
            let expected = fields["value"], expected.arrayValue == nil, expected.objectValue == nil,
            ["eq", "neq"].contains(op) || DecimalValue(expected) != nil,
            !Self.isNumeric(expected) || DecimalValue(expected) != nil
      else { return nil }
      self.fields = fields
    }

    func evaluate(_ inputs: AgentMcpJSONObject) -> Observation {
      func unknown(_ reason: String, _ actual: String? = nil) -> Observation {
        .init(condition: self, state: "unknown", unknown: reason, actualType: actual)
      }
      guard let input = inputs[fields.string("input")] else { return unknown("input_missing") }
      guard let actual = Self.atPointer(fields.string("pointer"), in: input), let expected = fields["value"] else {
        return unknown("pointer_unavailable")
      }
      let actualType = Self.type(actual)
      guard actualType != "object", actualType != "array" else { return unknown("non_scalar_value", actualType) }
      guard actualType == Self.type(expected) else { return unknown("type_mismatch", actualType) }
      let comparison: Int?
      if Self.isNumeric(actual) {
        guard let left = DecimalValue(actual), let right = DecimalValue(expected) else {
          return unknown("unsupported_numeric_value", actualType)
        }
        comparison = left.compare(right)
      } else {
        comparison = nil
      }
      let equal: Bool
      if case .string(let left) = actual, case .string(let right) = expected {
        equal = left.utf8.elementsEqual(right.utf8)
      } else {
        equal = comparison.map { $0 == 0 } ?? (actual == expected)
      }
      let matched: Bool
      switch fields.string("operator") {
      case "eq": matched = equal
      case "neq": matched = !equal
      default:
        guard let comparison else { return unknown("non_numeric_ordering", actualType) }
        switch fields.string("operator") {
        case "lt": matched = comparison < 0
        case "lte": matched = comparison <= 0
        case "gt": matched = comparison > 0
        default: matched = comparison >= 0
        }
      }
      return .init(condition: self, state: matched ? "matched" : "not_matched", unknown: nil, actualType: actualType)
    }

    private static func atPointer(_ pointer: String, in root: AgentMcpJSONValue) -> AgentMcpJSONValue? {
      var value = root
      for part in pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
        let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        if let next = value.objectValue?[key] { value = next }
        else if let list = value.arrayValue, let index = Int(key), String(index) == key, list.indices.contains(index) {
          value = list[index]
        } else { return nil }
      }
      return value
    }

    private static func isNumeric(_ value: AgentMcpJSONValue) -> Bool { type(value) == "number" }

    private static func type(_ value: AgentMcpJSONValue) -> String {
      switch value {
      case .int, .double: return "number"
      case .string: return "string"
      case .bool: return "boolean"
      case .null: return "null"
      case .array: return "array"
      case .object: return "object"
      }
    }
  }

  struct Observation {
    let condition: Condition
    let state: String
    let unknown: String?
    let actualType: String?

    func report(mayChange: Bool) -> AgentMcpJSONValue {
      var row = condition.fields
      row["state"] = .string(state)
      row["unknown_reason"] = unknown.map(AgentMcpJSONValue.string) ?? .null
      row["actual_type"] = actualType.map(AgentMcpJSONValue.string) ?? .null
      row["resolving_unknown_may_change_selection"] = .bool(unknown != nil && mayChange)
      return .object(row)
    }

    var selection: AgentMcpJSONValue { .object(["condition_id": .string(condition.id), "state": .string(state)]) }
  }

  // Compare bounded decimal spellings exactly rather than rounding Int64 values through Double.
  private struct DecimalValue {
    let sign: Int
    let digits: [UInt8]
    let order: Int

    init?(_ value: AgentMcpJSONValue) {
      let text: String
      switch value {
      case .int(let number): text = String(number)
      case .double(let number) where number.isFinite: text = String(number)
      default: return nil
      }
      let parts = text.lowercased().split(separator: "e")
      let mantissa = parts[0]
      guard let exponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
      let decimal = mantissa.split(separator: ".", omittingEmptySubsequences: false)
      let scale = (decimal.count == 2 ? decimal[1].count : 0) - exponent
      let significant = mantissa.utf8.filter { (48...57).contains($0) }.drop(while: { $0 == 48 })
      guard significant.count <= 128, (-128...128).contains(scale) else { return nil }
      sign = significant.isEmpty ? 0 : (mantissa.hasPrefix("-") ? -1 : 1)
      digits = Array(significant)
      order = significant.count - scale
    }

    func compare(_ other: Self) -> Int {
      if sign != other.sign { return sign < other.sign ? -1 : 1 }
      if sign == 0 { return 0 }
      if order != other.order { return order < other.order ? -sign : sign }
      for index in 0..<max(digits.count, other.digits.count) {
        let left = index < digits.count ? digits[index] : 48
        let right = index < other.digits.count ? other.digits[index] : 48
        if left != right { return left < right ? -sign : sign }
      }
      return 0
    }
  }
}
