import Foundation

enum AgentIOSWebWatchPolicy {
  static func isValid(_ watch: AgentIOSWebIntelligenceCacheWatch) -> Bool {
    !watch.id.isEmpty && watch.id.count <= 96 && AgentIOSWebCrawlPolicy.canonical(watch.url) != nil &&
      (15...10_080).contains(watch.intervalMinutes) && watch.lastCheckedAtMillis >= 0 && watch.lastChangedAtMillis >= 0 &&
      watch.createdAtMillis >= 0 && watch.updatedAtMillis >= 0 && (watch.lastSHA256.isEmpty || validHash(watch.lastSHA256))
  }
  static func isDue(_ watch: AgentIOSWebIntelligenceCacheWatch, now: Int64) -> Bool {
    guard isValid(watch), watch.enabled, now >= 0 else { return false }
    if watch.lastCheckedAtMillis == 0 { return true }
    let age = now.subtractingReportingOverflow(watch.lastCheckedAtMillis)
    let interval = Int64(watch.intervalMinutes).multipliedReportingOverflow(by: 60_000)
    return !age.overflow && age.partialValue >= 0 && !interval.overflow && age.partialValue >= interval.partialValue
  }
  static func completed(_ watch: AgentIOSWebIntelligenceCacheWatch, hash: String, now: Int64) -> (watch: AgentIOSWebIntelligenceCacheWatch, changed: Bool)? {
    let value = hash.lowercased()
    guard isValid(watch), validHash(value) else { return nil }
    let changed = !watch.lastSHA256.isEmpty && watch.lastSHA256.lowercased() != value
    var updated = watch
    let timestamp = max(0, now, watch.updatedAtMillis, watch.lastCheckedAtMillis, watch.lastChangedAtMillis, watch.createdAtMillis)
    updated.lastSHA256 = value
    updated.lastCheckedAtMillis = timestamp
    updated.updatedAtMillis = timestamp
    if changed { updated.lastChangedAtMillis = timestamp }
    return (updated, changed)
  }
  private static func validHash(_ value: String) -> Bool {
    value.count == 64 && value.lowercased().allSatisfy({ "0123456789abcdef".contains($0) })
  }
}
