import Foundation

struct AgentHomeAssistantServiceCallRequest: Equatable {
  var serviceDomain: String
  var service: String
  var entityId: String
  var serviceData: AgentMcpJSONObject

  init(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject = [:]
  ) {
    self.serviceDomain = serviceDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.service = service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.entityId = entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.serviceData = serviceData
  }

  var nativeToolInput: AgentMcpJSONObject {
    [
      "service_domain": .string(serviceDomain),
      "service": .string(service),
      "entity_id": .string(entityId),
      "service_data": .object(serviceData)
    ]
  }
}

enum AgentHomeAssistantPromptRouter {
  static func serviceCall(for prompt: String, defaultEntityId: String = "") -> AgentHomeAssistantServiceCallRequest? {
    parseCommand(prompt: prompt, defaultEntityId: defaultEntityId)
  }

  static func entityId(for prompt: String, defaultEntityId: String = "") -> String {
    if let range = prompt.range(of: entityIdPattern, options: .regularExpression) {
      return String(prompt[range]).lowercased()
    }
    return defaultEntityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func parseCommand(prompt: String, defaultEntityId: String) -> AgentHomeAssistantServiceCallRequest? {
    let lower = prompt.lowercased()
    let entityId = entityId(for: prompt, defaultEntityId: defaultEntityId)
    guard !entityId.isEmpty else { return nil }
    let entityDomain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? "homeassistant"
    if let requestedDomain = requestedDomain(lower), requestedDomain != entityDomain {
      return nil
    }
    let service = serviceName(lower: lower, entityId: entityId, entityDomain: entityDomain)
    let serviceDomain = serviceDomain(for: service, entityDomain: entityDomain)
    return AgentHomeAssistantServiceCallRequest(
      serviceDomain: serviceDomain,
      service: service,
      entityId: entityId,
      serviceData: service == "trigger" ? ["skip_condition": .bool(lower.contains("skip condition"))] : [:]
    )
  }

  private static func requestedDomain(_ lower: String) -> String? {
    if lower.contains("run automation") ||
      lower.contains("trigger automation") ||
      lower.contains("\u{81ea}\u{52a8}\u{5316}") {
      return "automation"
    }
    if lower.contains("run script") ||
      lower.contains("execute script") ||
      lower.contains("\u{811a}\u{672c}") {
      return "script"
    }
    if lower.contains("activate scene") ||
      lower.contains("run scene") ||
      lower.contains("\u{573a}\u{666f}") {
      return "scene"
    }
    return nil
  }

  private static func serviceName(lower: String, entityId: String, entityDomain: String) -> String {
    if entityId.hasPrefix("automation.") ||
      lower.contains("run automation") ||
      lower.contains("trigger automation") ||
      lower.contains("\u{81ea}\u{52a8}\u{5316}") {
      return "trigger"
    }
    if entityId.hasPrefix("script.") ||
      lower.contains("run script") ||
      lower.contains("execute script") ||
      lower.contains("\u{811a}\u{672c}") {
      return "turn_on"
    }
    if entityId.hasPrefix("scene.") ||
      lower.contains("activate scene") ||
      lower.contains("run scene") ||
      lower.contains("\u{573a}\u{666f}") {
      return "turn_on"
    }
    if lower.contains("unlock") || lower.contains("\u{89e3}\u{9501}") {
      return "unlock"
    }
    if lower.contains("lock") ||
      lower.contains("\u{4e0a}\u{9501}") ||
      lower.contains("\u{9501}\u{95e8}") {
      return "lock"
    }
    if entityDomain == "cover" &&
      (lower.contains("open") ||
        lower.contains("\u{6253}\u{5f00}") ||
        lower.contains("\u{5f00}\u{542f}")) {
      return "open_cover"
    }
    if entityDomain == "cover" &&
      (lower.contains("close") ||
        lower.contains("\u{5173}\u{95ed}") ||
        lower.contains("\u{5173}\u{4e0a}")) {
      return "close_cover"
    }
    if entityDomain == "valve" &&
      (lower.contains("open") || lower.contains("\u{6253}\u{5f00}")) {
      return "open_valve"
    }
    if entityDomain == "valve" &&
      (lower.contains("close") || lower.contains("\u{5173}\u{95ed}")) {
      return "close_valve"
    }
    if lower.contains("turn off") ||
      lower.contains("power off") ||
      lower.hasSuffix(" off") ||
      lower.contains("\u{5173}\u{95ed}") ||
      lower.contains("\u{5173}\u{6389}") ||
      lower.contains("\u{5173}\u{706f}") {
      return "turn_off"
    }
    if lower.contains("turn on") ||
      lower.contains("power on") ||
      lower.hasSuffix(" on") ||
      lower.contains("\u{6253}\u{5f00}") ||
      lower.contains("\u{5f00}\u{542f}") ||
      lower.contains("\u{5f00}\u{706f}") {
      return "turn_on"
    }
    if lower.contains("toggle") ||
      lower.contains("switch") ||
      lower.contains("\u{5207}\u{6362}") {
      return "toggle"
    }
    if lower.contains("activate") || lower.contains("scene") {
      return "turn_on"
    }
    return "toggle"
  }

  private static func serviceDomain(for service: String, entityDomain: String) -> String {
    switch service {
    case "trigger":
      return "automation"
    case "turn_on" where entityDomain == "scene" || entityDomain == "script":
      return entityDomain
    case "turn_on", "turn_off", "toggle":
      return "homeassistant"
    case "open_cover", "close_cover":
      return "cover"
    case "open_valve", "close_valve":
      return "valve"
    case "lock", "unlock":
      return "lock"
    default:
      return entityDomain
    }
  }

  private static let entityIdPattern = #"\b[a-z_]+\.[A-Za-z0-9_]+\b"#
}
