import Foundation

#if os(iOS)
// The iOS SDK exposes this symbol from <os/proc.h>, which is not imported by
// Swift's Darwin module. Keep the declaration local to avoid a bridging header.
@_silgen_name("os_proc_available_memory")
private func galaxySSIAvailableMemoryBudget() -> UInt64
#endif

struct AgentIOSDeviceMemorySnapshot {
  var totalBytes: Int64
  var availableBytes: Int64
  var lowMemory: Bool
  var lowMemoryThresholdBytes: Int64
  var pressure: String
  var availableBytesEstimated: Bool
  var appAvailableMemoryBudgetBytes: Int64?

  init(
    totalBytes: Int64,
    availableBytes: Int64,
    lowMemory: Bool,
    lowMemoryThresholdBytes: Int64,
    pressure: String,
    availableBytesEstimated: Bool = true,
    appAvailableMemoryBudgetBytes: Int64? = nil
  ) {
    self.totalBytes = max(0, totalBytes)
    self.availableBytes = min(max(0, availableBytes), self.totalBytes)
    self.lowMemory = lowMemory
    self.lowMemoryThresholdBytes = min(max(0, lowMemoryThresholdBytes), self.totalBytes)
    self.pressure = pressure
    self.availableBytesEstimated = availableBytesEstimated
    self.appAvailableMemoryBudgetBytes = appAvailableMemoryBudgetBytes.map { max(0, $0) }
  }
}

protocol AgentIOSDeviceMemoryStatusProviding {
  func snapshot() -> AgentIOSDeviceMemorySnapshot
}

struct AgentIOSDefaultDeviceMemoryStatusProvider: AgentIOSDeviceMemoryStatusProviding {
  private let processInfo: ProcessInfo

  init(processInfo: ProcessInfo = .processInfo) {
    self.processInfo = processInfo
  }

  func snapshot() -> AgentIOSDeviceMemorySnapshot {
    let total = Int64(min(processInfo.physicalMemory, UInt64(Int64.max)))
    let pressure = memoryPressure(processInfo.thermalState)
    let ratio: Double
    switch pressure {
    case "critical": ratio = 0.35
    case "serious": ratio = 0.45
    case "fair": ratio = 0.50
    default: ratio = processInfo.isLowPowerModeEnabled ? 0.45 : 0.55
    }
    let available = Int64((Double(total) * ratio).rounded())
    let threshold = min(total, max(Int64(128) * 1_024 * 1_024, total / 8))
    return AgentIOSDeviceMemorySnapshot(
      totalBytes: total,
      availableBytes: available,
      lowMemory: available <= threshold,
      lowMemoryThresholdBytes: threshold,
      pressure: pressure,
      appAvailableMemoryBudgetBytes: appAvailableMemoryBudget()
    )
  }

  private func appAvailableMemoryBudget() -> Int64? {
    #if os(iOS)
    let budget = galaxySSIAvailableMemoryBudget()
    guard budget > 0 else { return nil }
    return Int64(min(budget, UInt64(Int64.max)))
    #else
    return nil
    #endif
  }

  private func memoryPressure(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "normal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
}

enum AgentIOSDeviceMemoryStatusPresentation {
  static func output(snapshot: AgentIOSDeviceMemorySnapshot, nowMillis: Int64) -> AgentMcpJSONObject {
    let total = max(0, snapshot.totalBytes)
    let available = min(max(0, snapshot.availableBytes), total)
    let used = total - available
    let usedPercent = total == 0
      ? 0
      : min(100, max(0, Int64((Double(used) * 100 / Double(total)).rounded(.down))))
    var output: AgentMcpJSONObject = [
      "scope": .string("device_ram"),
      "total_bytes": .int(total),
      "available_bytes": .int(available),
      "used_bytes": .int(used),
      "used_percent": .int(usedPercent),
      "low_memory": .bool(snapshot.lowMemory),
      "low_memory_threshold_bytes": .int(snapshot.lowMemoryThresholdBytes),
      "memory_pressure": .string(snapshot.pressure),
      "available_memory_estimated": .bool(snapshot.availableBytesEstimated),
      "observed_at_epoch_ms": .int(max(0, nowMillis))
    ]
    if let budget = snapshot.appAvailableMemoryBudgetBytes {
      output["app_available_memory_budget_bytes"] = .int(budget)
    }
    return output
  }

  static func message(output: AgentMcpJSONObject, language: String) -> String {
    let total = formatBytes(output["total_bytes"]?.intValue ?? 0)
    let available = formatBytes(output["available_bytes"]?.intValue ?? 0)
    let used = formatBytes(output["used_bytes"]?.intValue ?? 0)
    let percent = output["used_percent"]?.intValue ?? 0
    let lowMemory = output["low_memory"]?.boolValue == true
    let appBudget = output["app_available_memory_budget_bytes"]?.intValue
    if language.lowercased().hasPrefix("zh") {
      let budgetMessage = appBudget.map { "\u{ff1b}\u{5e94}\u{7528}\u{53ef}\u{7528}\u{5185}\u{5b58}\u{9884}\u{7b97}\u{ff1a}\(formatBytes($0))\u{3002}" } ?? ""
      return "\u{624b}\u{673a}\u{5185}\u{5b58}\u{ff1a}\u{5df2}\u{7528} \(used) / \(total)\u{ff0c}\u{53ef}\u{7528} \(available)\u{ff08}\(percent)%\u{ff09}" +
        (lowMemory ? "\u{ff1b}\u{7cfb}\u{7edf}\u{62a5}\u{544a}\u{5185}\u{5b58}\u{4e0d}\u{8db3}\u{3002}" : "\u{ff1b}\u{5185}\u{5b58}\u{72b6}\u{6001}\u{6b63}\u{5e38}\u{3002}") + budgetMessage
    }
    let budgetMessage = appBudget.map { " App memory budget remaining: \(formatBytes($0))." } ?? ""
    return "Phone memory: \(used) used of \(total), \(available) available (\(percent)%). " +
      (lowMemory ? "The system reports low memory." : "Memory status is normal.") + budgetMessage
  }

  private static func formatBytes(_ value: Int64) -> String {
    let bytes = Double(max(0, value))
    if bytes >= 1_024 * 1_024 * 1_024 { return String(format: "%.1f GB", bytes / (1_024 * 1_024 * 1_024)) }
    if bytes >= 1_024 * 1_024 { return String(format: "%.1f MB", bytes / (1_024 * 1_024)) }
    return String(format: "%.1f KB", bytes / 1_024)
  }
}
