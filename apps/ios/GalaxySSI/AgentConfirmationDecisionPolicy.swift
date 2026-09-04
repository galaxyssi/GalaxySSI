import Foundation

struct AgentConfirmationDecision: Codable, Equatable {
  var requiresConfirmation: Bool
  var pendingActionIds: [String]
  var rememberedConsentKeys: [String]
  var alwaysConfirmActionIds: [String]

  init(
    requiresConfirmation: Bool,
    pendingActionIds: [String] = [],
    rememberedConsentKeys: [String] = [],
    alwaysConfirmActionIds: [String] = []
  ) {
    self.requiresConfirmation = requiresConfirmation
    self.pendingActionIds = pendingActionIds
    self.rememberedConsentKeys = rememberedConsentKeys
    self.alwaysConfirmActionIds = alwaysConfirmActionIds
  }

  enum CodingKeys: String, CodingKey {
    case requiresConfirmation = "requires_confirmation"
    case pendingActionIds = "pending_action_ids"
    case rememberedConsentKeys = "remembered_consent_keys"
    case alwaysConfirmActionIds = "always_confirm_action_ids"
  }
}

enum AgentConfirmationDecisionPolicy {
  static func decision(
    actions: [AgentAction],
    permissionMode: AgentPermissionMode,
    consentStore: AgentConfirmationConsentStore? = nil,
    sessionId: String = ""
  ) -> AgentConfirmationDecision {
    let pending = actions.filter(isPending)
    let rememberedKeys = pending.compactMap { action -> String? in
      let key = AgentConfirmationPolicy.consentKey(for: action)
      return consentStore?.isRemembered(consentKey: key, sessionId: sessionId) == true ? key : nil
    }
    let alwaysConfirmIds = pending
      .filter { AgentConfirmationPolicy.tier(for: $0) == .confirmAlways }
      .map(\.id)
    let requiresConfirmation: Bool
    switch permissionMode {
    case .observeOnly, .suggestOnly:
      requiresConfirmation = false
    case .askBeforeAction:
      requiresConfirmation = pending.contains { action in
        !askBeforeActionExclusions.contains(action.kind) &&
          AgentConfirmationPolicy.tier(for: action) != .direct
      }
    case .autoLowRisk:
      requiresConfirmation = pending.contains {
        actionRequiresTierConfirmation($0, consentStore: consentStore, sessionId: sessionId)
      }
    }
    return AgentConfirmationDecision(
      requiresConfirmation: requiresConfirmation,
      pendingActionIds: pending.map(\.id),
      rememberedConsentKeys: stableDistinct(rememberedKeys),
      alwaysConfirmActionIds: alwaysConfirmIds
    )
  }

  static func actionRequiresTierConfirmation(
    _ action: AgentAction,
    consentStore: AgentConfirmationConsentStore? = nil,
    sessionId: String = ""
  ) -> Bool {
    switch AgentConfirmationPolicy.tier(for: action) {
    case .direct:
      return false
    case .confirmAlways:
      return true
    case .confirmOnce:
      let key = AgentConfirmationPolicy.consentKey(for: action)
      return consentStore?.isRemembered(consentKey: key, sessionId: sessionId) != true
    }
  }

  static func recordApproval(
    action: AgentAction,
    consentStore: AgentConfirmationConsentStore?,
    sessionId: String = "",
    sessionScoped: Bool = false
  ) {
    guard AgentConfirmationPolicy.tier(for: action) == .confirmOnce else {
      return
    }
    let key = AgentConfirmationPolicy.consentKey(for: action)
    if sessionScoped {
      consentStore?.remember(consentKey: key, sessionId: sessionId)
    } else {
      consentStore?.remember(consentKey: key)
    }
  }

  private static func isPending(_ action: AgentAction) -> Bool {
    action.status == .pendingConfirmation || action.status == .proposed
  }

  private static func stableDistinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
      result.append(value)
    }
    return result
  }

  private static let askBeforeActionExclusions: Set<AgentActionKind> = [
    .readScreen,
    .draftPlan,
    .callConnector
  ]
}
