import Foundation

struct AgentIOSWebFetchFlightResult {
  var value: AgentNativeToolExecutionResult
  var shared: Bool
  var waitedMillis: Int64
}

enum AgentIOSWebFetchSingleFlight {
  private final class Entry {
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var result: Result<AgentNativeToolExecutionResult, Error>?

    init() {
      completion.enter()
    }

    func complete(_ result: Result<AgentNativeToolExecutionResult, Error>) {
      lock.lock()
      guard self.result == nil else {
        lock.unlock()
        return
      }
      self.result = result
      lock.unlock()
      completion.leave()
    }

    func wait(milliseconds: Int64) -> Bool {
      completion.wait(timeout: .now() + .milliseconds(Int(max(1, milliseconds)))) == .success
    }

    func resolvedValue() throws -> AgentNativeToolExecutionResult {
      lock.lock()
      let current = result
      lock.unlock()
      guard let current else { throw AgentNativeToolInvocationError.timedOut }
      return try current.get()
    }
  }

  private static let lock = NSLock()
  private static var entries: [String: Entry] = [:]

  static func execute(
    canonicalURL: String,
    timeoutMillis: Int64,
    isCancellationRequested: () -> Bool,
    checkpoint: () throws -> Void,
    fetch: () throws -> AgentNativeToolExecutionResult
  ) throws -> AgentIOSWebFetchFlightResult {
    let entry: Entry
    let shared: Bool
    lock.lock()
    if let active = entries[canonicalURL] {
      entry = active
      shared = true
    } else {
      let created = Entry()
      entries[canonicalURL] = created
      entry = created
      shared = false
    }
    lock.unlock()

    if !shared {
      defer { remove(entry, canonicalURL: canonicalURL) }
      do {
        let value = try fetch()
        entry.complete(.success(value))
        return AgentIOSWebFetchFlightResult(value: value, shared: false, waitedMillis: 0)
      } catch {
        entry.complete(.failure(error))
        throw error
      }
    }

    let started = uptimeMillis()
    let deadline = started + max(1, timeoutMillis)
    while true {
      if isCancellationRequested() { throw AgentNativeToolInvocationError.cancelled }
      try checkpoint()
      let remaining = deadline - uptimeMillis()
      guard remaining > 0 else { throw AgentNativeToolInvocationError.timedOut }
      if entry.wait(milliseconds: min(remaining, 100)) {
        return AgentIOSWebFetchFlightResult(
          value: try entry.resolvedValue(),
          shared: true,
          waitedMillis: max(0, uptimeMillis() - started)
        )
      }
    }
  }

  private static func remove(_ entry: Entry, canonicalURL: String) {
    lock.lock()
    if entries[canonicalURL] === entry {
      entries.removeValue(forKey: canonicalURL)
    }
    lock.unlock()
  }

  private static func uptimeMillis() -> Int64 {
    Int64((ProcessInfo.processInfo.systemUptime * 1_000).rounded())
  }
}
