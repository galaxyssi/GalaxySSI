import Foundation

enum GalaxySSIHealthReportDelivery {
  enum Problem: String, Error { case notSent, notAccepted, replyTimeout, remoteFailure }
  enum Admission: Equatable { case missing, active, completed, terminalFailure, unknown }
  struct Timing {
    var earlyWait: UInt64 = 20_000_000_000
    var responseWait: UInt64 = 160_000_000_000
    var retryDelay: UInt64 = 500_000_000
    var poll: UInt64 = 200_000_000
    var activeGrace: UInt64 = 90_000_000_000
    var completedGrace: UInt64 = 30_000_000_000
  }

  @MainActor static func receive(publish: () async throws -> Bool, probe: () async throws -> Admission,
      outcome: () -> GalaxySSIHealthReportCodexExchange.Outcome?, valid: () -> Bool,
      timing: Timing = .init(), now: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
      sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) async throws -> String {
    @MainActor func current() throws {
      try Task.checkCancellation()
      guard valid() else { throw MqttRouteError.identityChanged }
    }
    @MainActor func resolved() throws -> String? {
      guard let value = outcome() else { return nil }
      switch value {
      case .result(let text): return text
      case .failed: throw Problem.remoteFailure
      }
    }
    @MainActor func wait(_ duration: UInt64) async throws -> String? {
      let started = now()
      while true {
        try current()
        if let text = try resolved() { return text }
        let clock = now(), elapsed = clock >= started ? clock - started : UInt64.max
        guard elapsed < duration else { return nil }
        try await sleep(min(max(1, timing.poll), duration - elapsed))
      }
    }
    var published = false
    for attempt in 0..<2 {
      try current()
      if let text = try resolved() { return text }
      let accepted = try await publish()
      try current()
      if let text = try resolved() { return text }
      if accepted {
        published = true
        let early = try await wait(timing.earlyWait)
        if let early { return early }
        let admission = try await probe()
        try current()
        // A terminal reply arriving while the probe is in flight wins over admission metadata.
        if let text = try resolved() { return text }
        switch admission {
        case .missing:
          if attempt == 1 { throw Problem.notAccepted }
        case .terminalFailure: throw Problem.remoteFailure
        case .active, .completed, .unknown:
          let late = try await wait(timing.responseWait)
          if let late { return late }
          let deadlineAdmission = try await probe()
          try current()
          if let text = try resolved() { return text }
          let grace: UInt64
          switch deadlineAdmission {
          case .active: grace = timing.activeGrace
          case .completed: grace = timing.completedGrace
          case .terminalFailure: throw Problem.remoteFailure
          case .missing, .unknown: grace = 0
          }
          let final = try await wait(grace)
          if let final { return final }
          throw Problem.replyTimeout
        }
      } else if attempt == 1 { throw published ? Problem.notAccepted : Problem.notSent }
      try current()
      try await sleep(timing.retryDelay)
    }
    throw Problem.notSent
  }
}
