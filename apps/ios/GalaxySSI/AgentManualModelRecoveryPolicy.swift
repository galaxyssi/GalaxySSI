import Foundation

enum AgentManualModelRecoveryPolicy {
  static let messageKey = "agent_manual_desktop_timeout"
  static let englishMessage = "The selected Desktop did not respond. The app stopped waiting without switching models. Check the connection and try again."

  static func timeoutMessage(language: String = LanguagePolicySettings.auto, bundle: Bundle = .main) -> String {
    let locale = LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en"
    guard let path = bundle.path(forResource: locale, ofType: "lproj"), let localized = Bundle(path: path) else { return englishMessage }
    return localized.localizedString(forKey: messageKey, value: englishMessage, table: "AgentManualModelRecovery")
  }
  static func terminalMessage(record: AgentDesktopReplyRecoveryRecord, payload: [String: Any], language: String) -> String? {
    guard record.isManualTargetLocked, record.binding.matches(payload),
      AgentRemoteTaskStatusPolicy.normalize(payload.string("task_status")) == "timed_out" ||
        AgentCodexSilenceRecoveryPolicy.confirmedTimeout(status: payload.string("task_status"),
          failureCode: payload.string("failure_code"), error: payload.string("error")) else { return nil }
    return timeoutMessage(language: language)
  }
}
