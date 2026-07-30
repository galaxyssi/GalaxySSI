import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol AgentIOSDevicePolicyStatusProviding {
  func devicePolicyStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

struct AgentIOSDefaultDevicePolicyStatusProvider: AgentIOSDevicePolicyStatusProviding {
  func devicePolicyStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(UIKit)
    let protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
    let framework = "UIKit"
    #else
    let protectedDataAvailable = false
    let framework = "unavailable"
    #endif
    return [
      "admin_active": .bool(false),
      "device_owner": .bool(false),
      "profile_owner": .bool(false),
      "lock_supported": .bool(false),
      "reboot_supported": .bool(false),
      "supervised_mdm_status_available": .bool(false),
      "managed_configuration_visible": .bool(false),
      "protected_data_available": .bool(protectedDataAvailable),
      "platform_management_model": .string("ios_app_sandbox"),
      "framework": .string(framework),
      "scope": .string("ios_app_visible_device_policy_status"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }
}
