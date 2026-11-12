import Foundation

enum GalaxySSIHealthCareFeedbackTool {
  static let function = "galaxyssi_health_feedback_read"
  static let maximumPages = 4
  static let pageBudget = 12_000
  static let instructions = "Read this turn's explicitly approved action feedback in descending revision order. " +
    "Start with the approved input_version and revision; use the exact next before_revision for older rows. " +
    "Redacted rows are outside the sharing scope. Self-reported execution is not clinically verified improvement. " +
    "Do not infer omitted rows. No other concern, original medical file, or write is authorized."
  static let schema: [String: Any] = [
    "type": "object", "required": ["input_version", "revision"], "additionalProperties": false,
    "properties": ["input_version": ["type": "string"], "revision": ["type": "integer", "minimum": 1],
      "before_revision": ["type": "integer", "minimum": 1]]
  ]

  struct Cursor: Equatable {
    let turn: UUID
    let revision: Int
    var before: Int? = nil

    var arguments: AgentMcpJSONObject {
      var result: AgentMcpJSONObject = ["input_version": .string(turn.uuidString), "revision": .int(Int64(revision))]
      if let before { result["before_revision"] = .int(Int64(before)) }
      return result
    }

    func output(rows: [(revision: Int, payload: AgentMcpJSONObject)], next: Int?,
                remaining: Int, budget: Int = GalaxySSIHealthCareFeedbackTool.pageBudget)
      -> (payload: AgentMcpJSONObject, cursor: Self?) {
      func page(_ items: [AgentMcpJSONValue], next: Int?, hasEarlier: Bool, truncated: Bool) -> AgentMcpJSONObject {
        var value = arguments
        value.removeValue(forKey: "before_revision")
        value["protocol"] = .string("galaxyssi.health-feedback.v1")
        value["page_start"] = before.map { .int(Int64($0)) } ?? .null
        value["items"] = .array(items)
        value["next"] = next.map { .int(Int64($0)) } ?? .null
        value["done"] = .bool(!hasEarlier)
        value["truncated"] = .bool(truncated)
        value["health_improvement_verified"] = .bool(false)
        return value
      }
      var items: [AgentMcpJSONValue] = []
      var last: Int?
      for row in rows {
        let candidate = items + [.object(row.payload)]
        let estimate = page(candidate, next: row.revision, hasEarlier: true, truncated: false)
        guard AgentMcpJSONCodec.stringify(estimate).utf8.count <= budget else { break }
        items = candidate
        last = row.revision
      }
      let truncated = items.count < rows.count
      let continuation = truncated ? (last ?? before) : next
      let cursor = remaining > 0 && (!truncated || last != nil) ? continuation.map {
        Self(turn: turn, revision: revision, before: $0)
      } : nil
      return (page(items, next: truncated && last == nil ? before : cursor?.before,
        hasEarlier: truncated || next != nil, truncated: truncated), cursor)
    }
  }
}
