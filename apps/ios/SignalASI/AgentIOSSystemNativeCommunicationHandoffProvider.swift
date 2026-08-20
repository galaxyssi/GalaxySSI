import Foundation
#if canImport(MessageUI)
import MessageUI
#endif

protocol AgentIOSCommunicationHandoffProviding {
  func dialHandoff(phoneNumber: String, toolId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func smsComposeHandoff(
    phoneNumber: String,
    message: String,
    toolId: String,
    requestedDirectSend: Bool,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultCommunicationHandoffProvider: AgentIOSCommunicationHandoffProviding {
  func dialHandoff(phoneNumber: String, toolId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    guard let normalized = normalizedPhoneNumber(phoneNumber) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_phone_number",
        message: "Phone number must contain only bounded dialable characters."
      )
    }
    return handoffResult(
      kind: "dial",
      url: "tel:\(normalized)",
      toolId: toolId,
      message: "Dialer handoff prepared for user confirmation.",
      nowMillis: nowMillis,
      extra: ["phone_number": .string(normalized)]
    )
  }

  func smsComposeHandoff(
    phoneNumber: String,
    message: String,
    toolId: String,
    requestedDirectSend: Bool,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    guard let normalized = normalizedPhoneNumber(phoneNumber) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_phone_number",
        message: "Phone number must contain only bounded dialable characters."
      )
    }
    let body = bounded(message, 2_000)
    return handoffResult(
      kind: "sms_compose",
      url: "sms:\(normalized)",
      toolId: toolId,
      message: "SMS compose handoff prepared; iOS requires the user to review and send.",
      nowMillis: nowMillis,
      extra: [
        "phone_number": .string(normalized),
        "prefill_body": .string(body),
        "body_in_url": .bool(false),
        "requested_direct_send": .bool(requestedDirectSend),
        "direct_send_supported": .bool(false),
        "submitted_to_system": .bool(false),
        "can_send_text": .bool(canSendText()),
        "handoff_transport": .string("message_compose_controller_or_sms_url")
      ]
    )
  }

  private func handoffResult(
    kind: String,
    url: String,
    toolId: String,
    message: String,
    nowMillis: Int64,
    extra: AgentMcpJSONObject
  ) -> AgentNativeToolExecutionResult {
    var output: AgentMcpJSONObject = [
      "handoff_kind": .string(kind),
      "url": .string(url),
      "requires_user_action": .bool(true),
      "completion_untrusted": .bool(true),
      "platform": .string("ios"),
      "tool_id": .string(toolId),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    for (key, value) in extra {
      output[key] = value
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: [
        "handoff_required": .bool(true),
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(toolId),
        "platform": .string("ios")
      ]
    )
  }

  private func normalizedPhoneNumber(_ value: String) -> String? {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" ", "-", "(", ")", "."] {
      normalized = normalized.replacingOccurrences(of: removable, with: "")
    }
    guard !normalized.isEmpty,
          normalized.count <= 64,
          normalized.range(of: #"^[+0-9*#,;]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return normalized
  }

  private func canSendText() -> Bool {
    #if canImport(MessageUI)
    return MFMessageComposeViewController.canSendText()
    #else
    return false
    #endif
  }

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
