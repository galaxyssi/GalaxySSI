import Foundation

enum AgentPinnedDesktopCodexCapability {
  static let id = "pinned_team_codex_v1"
  struct Inventory: Equatable {
    var capabilities: [String]
    var markerRemoved: Bool
  }

  static func advertised(_ agent: [String: Any]) -> Bool {
    (agent["capabilities"] as? [Any])?.contains { ($0 as? String) == id } == true
  }

  static func compact(_ agent: [String: Any]) -> Bool {
    advertised(agent) && inventory(agent) == nil
  }

  static func inventory(_ agent: [String: Any]) -> Inventory? {
    let adapter = agent["adapter"] as? [String: Any]
    let values = (agent["capabilities"] as? [Any]) ?? (adapter?["capabilities"] as? [Any])
    guard let values else { return nil }
    let strings = values.compactMap { $0 as? String }
    let remaining = strings.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines) != id }
    // A compact marker-only advertisement does not replace the routing inventory.
    if advertised(agent), remaining.isEmpty, adapter == nil { return nil }
    return Inventory(capabilities: remaining, markerRemoved: remaining.count != strings.count)
  }

  static func inheritedCapabilities(_ value: Any) -> Any? {
    guard let values = value as? [Any], values.contains(where: { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == id }) else {
      return value
    }
    let remaining = values.filter { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) != id }
    return remaining.isEmpty ? nil : remaining
  }

  static func boundAdvertisement(_ agent: [String: Any], agentID: String, desktopID: String,
                                 fingerprint: String, link: ServerLink?) -> Bool {
    guard agentID == "codex", advertised(agent), let link, link.paired,
      desktopID == link.desktopId, !fingerprint.isBlank,
      fingerprint.caseInsensitiveCompare(link.desktopFingerprint) == .orderedSame else { return false }
    return true
  }
}
