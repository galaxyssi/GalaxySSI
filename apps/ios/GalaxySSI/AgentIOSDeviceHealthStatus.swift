import Foundation

enum AgentIOSDeviceHealthStatusPresentation {
  static func output(
    battery: AgentMcpJSONObject,
    power: AgentMcpJSONObject,
    memory: AgentMcpJSONObject,
    storage: AgentMcpJSONObject,
    network: AgentMcpJSONObject,
    nowMillis: Int64
  ) -> AgentMcpJSONObject {
    [
      "scope": .string("ios_app_visible_device"),
      "battery": .object(battery),
      "power": .object(power),
      "memory": .object(memory),
      "storage": .object(storage),
      "network": .object(network),
      "observed_at_epoch_ms": .int(max(0, nowMillis))
    ]
  }

  static func message(output: AgentMcpJSONObject, language: String) -> String {
    let battery = output["battery"]?.objectValue ?? [:]
    let memory = output["memory"]?.objectValue ?? [:]
    let storage = output["storage"]?.objectValue ?? [:]
    let network = output["network"]?.objectValue ?? [:]
    let batteryText = battery["percent"]?.intValue.map { "\($0)%" } ?? "unknown"
    let usedPercent = memory["used_percent"]?.intValue ?? 0
    let availableStorage = formatBytes(storage["available_bytes"]?.intValue ?? 0)
    let connected = network["connected"]?.boolValue == true

    if language.lowercased().hasPrefix("zh") {
      return "\u{8BBE}\u{5907}\u{72B6}\u{6001}\u{FF1A}\u{7535}\u{91CF} \(batteryText)\u{FF0C}\u{5185}\u{5B58}\u{5DF2}\u{7528} \(usedPercent)%\u{FF0C}\u{53EF}\u{7528}\u{5B58}\u{50A8} \(availableStorage)\u{FF0C}\u{7F51}\u{7EDC}\(connected ? "\u{5DF2}\u{8FDE}\u{63A5}" : "\u{672A}\u{8FDE}\u{63A5}")\u{3002}"
    }
    return "Device status: battery \(batteryText), memory \(usedPercent)% used, \(availableStorage) storage available, network \(connected ? "connected" : "offline")."
  }

  private static func formatBytes(_ value: Int64) -> String {
    let bytes = Double(max(0, value))
    if bytes >= 1_024 * 1_024 * 1_024 {
      return String(format: "%.1f GB", bytes / (1_024 * 1_024 * 1_024))
    }
    if bytes >= 1_024 * 1_024 {
      return String(format: "%.1f MB", bytes / (1_024 * 1_024))
    }
    return String(format: "%.1f KB", bytes / 1_024)
  }
}
