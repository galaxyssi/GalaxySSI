import Foundation

protocol AgentIOSWifiScanProviding {
  func wifiScanResults(limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func startWifiScan(nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultWifiScanProvider: AgentIOSWifiScanProviding {
  func wifiScanResults(limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: [
        "networks": .array([]),
        "count": .int(0),
        "limit": .int(Int64(max(1, min(100, limit)))),
        "scan_supported": .bool(false),
        "scan_trigger_supported": .bool(false),
        "identifiers_included": .bool(false),
        "platform": .string("ios"),
        "scope": .string("ios_wifi_scan_unavailable_app_sandbox"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS does not expose nearby Wi-Fi scan results to normal apps."
    )
  }

  func startWifiScan(nowMillis: Int64) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: [
        "accepted": .bool(false),
        "may_be_throttled": .bool(false),
        "scan_supported": .bool(false),
        "scan_trigger_supported": .bool(false),
        "platform": .string("ios"),
        "scope": .string("ios_wifi_scan_unavailable_app_sandbox"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS does not allow normal apps to trigger arbitrary Wi-Fi scans."
    )
  }
}
