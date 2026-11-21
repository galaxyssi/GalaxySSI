import Darwin
import Foundation
import UIKit

struct PublicNewsBudgetProfile: Equatable {
  let recentlyRead: Bool
  let charging: Bool
  init(now: TimeInterval, lastRead: TimeInterval, charging: Bool) {
    recentlyRead = lastRead.isFinite && lastRead > 0 && now >= lastRead && now - lastRead < 86_400
    self.charging = charging
  }
  var feedInterval: TimeInterval { !recentlyRead ? 43_200 : charging ? 1_800 : 3_600 }
  var feedSpacing: TimeInterval { charging ? 15 : recentlyRead ? 60 : 300 }
  var articleLimit: Int { charging ? 10 : recentlyRead ? 4 : 2 }
  var articleTime: TimeInterval { charging ? 60 : 30 }
  var allowPush: Bool { charging && recentlyRead }
  func articleSpacing(published: Bool) -> TimeInterval {
    if !charging && !recentlyRead { return 43_200 }
    return charging ? (published ? 120 : 600) : (published ? 900 : 2_700)
  }
  static func remaining(now: TimeInterval, last: TimeInterval, interval: TimeInterval) -> TimeInterval {
    guard now.isFinite, last.isFinite, interval.isFinite, last > 0, last <= now else { return 0 }
    return max(0, interval - (now - last))
  }
}

struct PublicNewsCPUWindow {
  private var start: TimeInterval?
  private var startCPU: TimeInterval = 0
  private var resume: TimeInterval = 0
  private var previous: TimeInterval?
  mutating func delay(uptime: TimeInterval, cpu: TimeInterval) -> TimeInterval {
    guard uptime.isFinite, cpu.isFinite, uptime >= 0, cpu >= 0 else { return 60 }
    if previous.map({ uptime < $0 }) == true { start = nil; resume = 0 }
    previous = uptime
    if uptime < resume { return resume - uptime }
    let duration = start.map { uptime - $0 } ?? -1
    if start == nil || duration < 0 || duration > 60 || cpu < startCPU {
      start = uptime; startCPU = cpu
    } else if duration >= 10 {
      if (cpu - startCPU) * 10 >= duration { resume = uptime + 300; start = nil }
      else { start = uptime; startCPU = cpu }
    }
    return max(0, resume - uptime)
  }
}

struct PublicNewsBudgetYield: Error {}

@MainActor
final class PublicNewsBudget {
  static let shared = PublicNewsBudget()
  private let defaults: UserDefaults
  private let prefix = "galaxyssi.public-news.budget.v1."
  private var cpu = PublicNewsCPUWindow()
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func profile(now: Date = Date(), charging: Bool? = nil) -> PublicNewsBudgetProfile {
    PublicNewsBudgetProfile(now: now.timeIntervalSince1970, lastRead: value("last-read"), charging: charging ?? Self.charging())
  }
  func noteRead(now: Date = Date()) {
    let time = now.timeIntervalSince1970
    guard time.isFinite, time > 0 else { return }
    guard PublicNewsBudgetProfile.remaining(now: time, last: value("last-read"), interval: 60) == 0 else { return }
    defaults.set(time, forKey: prefix + "last-read")
  }
  func feedDelay(now: Date = Date(), atSweepBoundary: Bool, charging: Bool? = nil) -> TimeInterval {
    let profile = profile(now: now, charging: charging), time = now.timeIntervalSince1970
    return max(PublicNewsBudgetProfile.remaining(now: time, last: value("last-feed"), interval: profile.feedSpacing),
      atSweepBoundary ? PublicNewsBudgetProfile.remaining(now: time, last: value("last-sweep"), interval: profile.feedInterval) : 0)
  }
  func feedFinished(now: Date = Date(), completedSweep: Bool) {
    defaults.set(now.timeIntervalSince1970, forKey: prefix + "last-feed")
    if completedSweep { defaults.set(now.timeIntervalSince1970, forKey: prefix + "last-sweep") }
  }
  func articleDelay(now: Date = Date(), charging: Bool? = nil) -> TimeInterval {
    let boundary = defaults.dictionary(forKey: prefix + "article") ?? [:]
    return PublicNewsBudgetProfile.remaining(now: now.timeIntervalSince1970, last: boundary["at"] as? Double ?? 0,
      interval: profile(now: now, charging: charging).articleSpacing(published: boundary["published"] as? Bool ?? false))
  }
  func articleBoundary(now: Date = Date(), published: Bool = false) {
    let boundary: [String: Any] = ["at": now.timeIntervalSince1970, "published": published]
    defaults.set(boundary, forKey: prefix + "article")
  }
  func pressure() -> TimeInterval { max(cpuDelay(), AgentIOSBackgroundLoad.current().deferSeconds) }
  func check() throws { if pressure() > 0 { throw PublicNewsBudgetYield() } }
  private func cpuDelay() -> TimeInterval {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 60 }
    let seconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec) +
      (Double(usage.ru_utime.tv_usec) + Double(usage.ru_stime.tv_usec)) / 1_000_000
    return cpu.delay(uptime: ProcessInfo.processInfo.systemUptime, cpu: seconds)
  }
  private func value(_ key: String) -> TimeInterval { defaults.double(forKey: prefix + key) }
  private static func charging() -> Bool {
    let device = UIDevice.current, monitoring = UIDevice.current.isBatteryMonitoringEnabled
    if !monitoring { device.isBatteryMonitoringEnabled = true }
    defer { if !monitoring { device.isBatteryMonitoringEnabled = false } }
    return device.batteryState == .charging || device.batteryState == .full
  }
}
