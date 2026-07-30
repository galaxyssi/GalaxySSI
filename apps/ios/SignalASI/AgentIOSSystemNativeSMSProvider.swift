import Foundation

protocol AgentIOSSMSInboxProviding {
  func listMessages(limit: Int, address: String, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultSMSInboxProvider: AgentIOSSMSInboxProviding {
  func listMessages(limit: Int, address: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: [
        "messages": .array([]),
        "count": .int(0),
        "limit": .int(Int64(max(1, min(100, limit)))),
        "address_filter": .string(bounded(address, 128)),
        "sms_database_read_supported": .bool(false),
        "direct_sms_read_supported": .bool(false),
        "identifiers_included": .bool(false),
        "platform": .string("ios"),
        "scope": .string("ios_sms_inbox_unavailable_app_sandbox"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS does not expose the user's SMS database to normal apps."
    )
  }

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
