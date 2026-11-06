import CoreFoundation
import Foundation

enum PublicNewsPushError: Error { case invalidEvent, invalidStory, unavailable }

struct PublicNewsPushCursor: Codable, Equatable {
  struct Work: Codable, Equatable {
    let firstSeen: Date
    var retryAt: Date
    var attempts = 0
  }

  private(set) var initialized = false
  private(set) var slots: [Int: Int64] = [:]
  private(set) var pending: [Int64: Work] = [:]
  private var seen: [Int64] = []
  static let retention: TimeInterval = 7 * 86_400

  mutating func accept(type: String, data: Data, now: Date) throws {
    guard data.count <= 128 * 1_024,
          let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let path = event["path"] as? String, let value = event["data"] else {
      throw PublicNewsPushError.invalidEvent
    }
    var next = slots
    switch (type, path) {
    case ("put", "/"):
      next = [:]
      if let list = value as? [Any], list.count <= 1_024 {
        for (index, item) in list.enumerated() { try Self.set(String(index), to: item, in: &next) }
      } else if let map = value as? [String: Any], map.count <= 1_024 {
        for (index, item) in map { try Self.set(index, to: item, in: &next) }
      } else if !(value is NSNull) { throw PublicNewsPushError.invalidEvent }
    case ("patch", "/"):
      guard let map = value as? [String: Any], map.count <= 1_024 else { throw PublicNewsPushError.invalidEvent }
      for (index, item) in map { try Self.set(index, to: item, in: &next) }
    case ("put", _):
      guard path.hasPrefix("/") else { throw PublicNewsPushError.invalidEvent }
      try Self.set(String(path.dropFirst()), to: value, in: &next)
    default:
      throw PublicNewsPushError.invalidEvent
    }
    if !initialized && (type != "put" || path != "/") { throw PublicNewsPushError.invalidEvent }

    expire(now: now)
    let known = Set(seen).union(slots.values).union(pending.keys)
    let newIDs = Set(next.values).subtracting(known).sorted()
    if initialized {
      for id in newIDs.suffix(max(0, 1_024 - pending.count)) {
        pending[id] = Work(firstSeen: now, retryAt: now)
      }
    }
    seen = Array((seen + newIDs).suffix(4_096))
    slots = next
    initialized = true
  }

  mutating func expire(now: Date) {
    pending = pending.filter { now.timeIntervalSince($0.value.firstSeen) <= Self.retention }
  }

  func next(at now: Date) -> Int64? {
    pending.filter { $0.value.retryAt <= now && now.timeIntervalSince($0.value.firstSeen) <= Self.retention }
      .min { a, b in
        a.value.firstSeen == b.value.firstSeen ? a.key < b.key : a.value.firstSeen < b.value.firstSeen
      }?.key
  }

  func nextWake(at now: Date) -> Date? {
    pending.values.lazy.filter {
      now.timeIntervalSince($0.firstSeen) <= Self.retention && $0.retryAt <= $0.firstSeen.addingTimeInterval(Self.retention)
    }.map(\.retryAt).min()
  }

  mutating func complete(_ id: Int64) { pending.removeValue(forKey: id) }

  mutating func deferItem(_ id: Int64, now: Date) {
    guard var work = pending[id] else { return }
    work.attempts = min(work.attempts + 1, 12)
    work.retryAt = now.addingTimeInterval(min(3_600, 5 * pow(2, Double(work.attempts))))
    pending[id] = work
  }

  private static func set(_ key: String, to value: Any, in slots: inout [Int: Int64]) throws {
    guard let index = Int(key), (0...1_023).contains(index), String(index) == key else {
      throw PublicNewsPushError.invalidEvent
    }
    if value is NSNull {
      slots.removeValue(forKey: index)
    } else if let id = positiveInteger(value) {
      slots[index] = id
    } else {
      throw PublicNewsPushError.invalidEvent
    }
  }

  static func positiveInteger(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          let integer = Int64(exactly: number.doubleValue), integer > 0, integer <= 9_007_199_254_740_991 else {
      return nil
    }
    return integer
  }
}
