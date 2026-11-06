import Foundation
import UIKit

enum GalaxySSIGlobalAgentBackgroundPolicy {
  static let allowsAutomaticCycles = true
}

struct AgentIOSBackgroundLoad: Equatable {
  let deferSeconds: TimeInterval
  let spacing: TimeInterval

  static func evaluate(thermal: ProcessInfo.ThermalState, batteryPercent: Int?, powered: Bool,
                       lowPower: Bool) -> Self {
    if thermal == .critical { return .init(deferSeconds: 300, spacing: 60) }
    if let batteryPercent, (0...5).contains(batteryPercent) ||
      (!powered && (0...10).contains(batteryPercent)) {
      return .init(deferSeconds: 300, spacing: 30)
    }
    if lowPower { return .init(deferSeconds: 300, spacing: 30) }
    if thermal == .serious { return .init(deferSeconds: 120, spacing: 30) }
    return .init(deferSeconds: 0, spacing: thermal == .fair ? 30 : 1)
  }

  @MainActor
  static func current(process: ProcessInfo = .processInfo) -> Self {
    let now = process.systemUptime
    if battery == nil || now - (battery?.sampledAt ?? 0) >= 15 {
      let device = UIDevice.current
      let wasMonitoring = device.isBatteryMonitoringEnabled
      if !wasMonitoring { device.isBatteryMonitoringEnabled = true }
      let level = device.batteryLevel
      let percent = (0...1).contains(level) ? Int((level * 100).rounded()) : nil
      let powered = device.batteryState == .charging || device.batteryState == .full
      if !wasMonitoring { device.isBatteryMonitoringEnabled = false }
      battery = (percent, powered, now)
    }
    return evaluate(thermal: process.thermalState, batteryPercent: battery?.percent,
      powered: battery?.powered == true, lowPower: process.isLowPowerModeEnabled)
  }

  @MainActor private static var battery: (percent: Int?, powered: Bool, sampledAt: TimeInterval)?
}

struct AgentIOSAutomaticCognitionWake {
  private(set) var pending: AgentIOSCognitionWorkMode?
  private(set) var notBefore: TimeInterval = 0
  private var lastStart: TimeInterval?

  mutating func request(_ mode: AgentIOSCognitionWorkMode) {
    guard mode.usesBackgroundLoadPolicy else { return }
    if pending == nil || mode == .scheduled || (mode == .foreground && pending == .event) {
      pending = mode
    }
  }

  mutating func delay(now: TimeInterval, load: AgentIOSBackgroundLoad) -> TimeInterval {
    if load.deferSeconds > 0, now >= notBefore { notBefore = now + load.deferSeconds }
    let nextStart = lastStart.map { $0 + load.spacing } ?? 0
    return max(0, max(notBefore, nextStart) - now)
  }

  mutating func take(now: TimeInterval) -> AgentIOSCognitionWorkMode? {
    guard let pending else { return nil }
    self.pending = nil
    notBefore = 0
    lastStart = now
    return pending
  }

  mutating func clear() { pending = nil; notBefore = 0 }
}
