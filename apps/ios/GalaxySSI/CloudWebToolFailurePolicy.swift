import Foundation

enum CloudWebToolFailurePolicy {
  static func applying(to payload: AgentMcpJSONObject, status: AgentNativeToolResultStatus, code: String?) -> AgentMcpJSONObject {
    guard status != .succeeded else { return payload }
    let hint: (code: String, next: String)
    let value = code ?? ""
    if status == .cancelled || ["cancelled", "web_media_cancelled", "web_execution_stopped", "web_budget_exceeded"].contains(value) {
      hint = ("web_execution_stopped", "Stop web calls and answer using existing evidence. State missing evidence honestly.")
    } else if status == .timedOut || ["timeout", "web_media_timeout", "web_source_timeout"].contains(value) {
      hint = ("web_source_timeout", "This URL timed out. Do not fetch the same URL again through extract, diff or another read tool in this turn. Use another source or existing evidence and state what is missing.")
    } else if value == "renderer_unavailable" {
      hint = ("renderer_unavailable", "The dynamic renderer is temporarily unavailable. Do not retry dynamic rendering in this turn. Use existing search snippets or cached/static evidence; state any missing evidence instead of claiming the page was read.")
    } else if ["unsupported_search_engine", "unsupported_image_engine", "invalid_engine"].contains(value) {
      hint = ("invalid_engine", "Do not invent engine IDs. Correct the engines in the plan; omit engines to use automatic source selection only if the user did not require a specific source.")
    } else { return payload }
    var output = payload
    output["status"] = .string("failed")
    output["native_status"] = .string(status.rawValue)
    output["error_code"] = .string(hint.code)
    output["retryable"] = .bool(false)
    output["next_action"] = .string(hint.next)
    return output
  }

  static func failure(tool: String, error: Error) -> AgentMcpJSONObject {
    var status = AgentNativeToolResultStatus.failed
    var code: String?
    switch error {
    case let native as AgentNativeToolInvocationError:
      switch native {
      case .cancelled: status = .cancelled; code = "cancelled"
      case .timedOut: status = .timedOut; code = "timeout"
      }
    case let web as AgentIOSURLSessionWebError:
      switch web {
      case .timeout: code = "web_media_timeout"
      case .cancelled: code = "web_media_cancelled"
      case .unsupportedSearchEngine: code = "unsupported_search_engine"
      case .unsupportedImageEngine: code = "unsupported_image_engine"
      default: break
      }
    case let renderer as AgentIOSDynamicWebRenderError where renderer == .unavailable:
      code = "renderer_unavailable"
    default: break
    }
    return applying(to: ["status": .string("failed"), "tool": .string(String(tool.prefix(80))),
      "error": .string(String(error.localizedDescription.prefix(300)))], status: status, code: code)
  }
}
