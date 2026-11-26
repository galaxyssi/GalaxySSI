import Foundation

struct GlobalRealtimePlanningScope {
  let canRead: Bool
  let allowedConversationIds: Set<String>
  let excludedConversationIds: Set<String>

  init(enabled: Bool, suppressed: Bool = false,
       conversations: @autoclosure () -> [AgentConversation]) {
    canRead = enabled && !suppressed
    guard canRead else {
      allowedConversationIds = []
      excludedConversationIds = []
      return
    }
    let sessions = conversations()
    allowedConversationIds = Set(sessions.filter { !$0.privateMode && !$0.trackingPaused }.map(\.id))
    excludedConversationIds = Set(sessions.filter { $0.privateMode || $0.trackingPaused }.map(\.id))
  }

  static func suppressesGlobalContext(selectedProviderOnly: Bool, overrideGlobalContext: String?) -> Bool {
    selectedProviderOnly || overrideGlobalContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
  }

  func context(provider: @autoclosure () -> GlobalRealtimeContextProvider,
               query: String, currentConversationId: String,
               maximumItems: Int = GlobalRealtimeContextPolicy.defaultMaximumItems,
               maximumCharacters: Int = GlobalRealtimeContextPolicy.defaultMaximumCharacters,
               nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> String {
    guard canRead else { return "" }
    return provider().buildNonBlocking(query: query, currentConversationId: currentConversationId,
      excludedConversationIds: excludedConversationIds, maximumItems: maximumItems,
      maximumCharacters: maximumCharacters, nowMillis: nowMillis,
      allowedConversationIds: allowedConversationIds)
  }
}
