import Foundation
#if canImport(NetworkExtension)
import NetworkExtension
#endif

protocol AgentIOSVPNStatusProviding {
  func vpnStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

struct AgentIOSDefaultVPNStatusProvider: AgentIOSVPNStatusProviding {
  func vpnStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(NetworkExtension)
    let status = NEVPNManager.shared().connection.status
    let statusName = vpnStatusName(status)
    let active = isActive(status)
    let networks: [AgentMcpJSONValue] = status == .invalid ? [] : [
      .object([
        "network": .string("app_managed_vpn"),
        "status": .string(statusName),
        "validated": .null,
        "internet": .null,
        "scope": .string("network_extension_connection_status")
      ])
    ]
    return [
      "active": .bool(active),
      "vpn_networks": .array(networks),
      "consent_granted": .null,
      "connection_status": .string(statusName),
      "configuration_scope": .string("app_managed_network_extension"),
      "global_vpn_enumeration_supported": .bool(false),
      "framework": .string("NetworkExtension"),
      "identifiers_included": .bool(false),
      "scope": .string("ios_app_managed_vpn_status"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #else
    return [
      "active": .bool(false),
      "vpn_networks": .array([]),
      "consent_granted": .null,
      "connection_status": .string("unavailable"),
      "configuration_scope": .string("network_extension_unavailable"),
      "global_vpn_enumeration_supported": .bool(false),
      "framework": .string("unavailable"),
      "identifiers_included": .bool(false),
      "scope": .string("ios_app_managed_vpn_status_unavailable"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #endif
  }

  #if canImport(NetworkExtension)
  private func isActive(_ status: NEVPNStatus) -> Bool {
    switch status {
    case .connected, .connecting, .reasserting:
      return true
    case .invalid, .disconnected, .disconnecting:
      return false
    @unknown default:
      return false
    }
  }

  private func vpnStatusName(_ status: NEVPNStatus) -> String {
    switch status {
    case .invalid:
      return "invalid"
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .reasserting:
      return "reasserting"
    case .disconnecting:
      return "disconnecting"
    @unknown default:
      return "unknown"
    }
  }
  #endif
}
