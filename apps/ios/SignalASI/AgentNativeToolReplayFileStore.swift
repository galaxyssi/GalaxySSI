import Foundation

final class FileAgentNativeToolReplayStore: AgentNativeToolReplayStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    fileURL: URL,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.nowMillis = nowMillis
  }

  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult? {
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    let loaded = loadUnlocked()
    let retained = retainedEntries(loaded, nowMillis: now)
    if retained.count != loaded.count {
      saveUnlocked(retained)
    }
    return retained.last { $0.key == key }?.result
  }

  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws {
    guard result.isSuccess else {
      throw AgentNativeToolReplayError.unsuccessfulResult
    }
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    var entries = Array(retainedEntries(loadUnlocked(), nowMillis: now)
      .filter { $0.key != key }
      .suffix(AgentNativeToolReplaySnapshotStore.maxEntries - 1))
    entries.append(AgentNativeToolReplayEntry(key: key, result: result, savedAtMillis: now))
    saveUnlocked(entries)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL)
  }

  private func loadUnlocked() -> [AgentNativeToolReplayEntry] {
    guard fileManager.fileExists(atPath: fileURL.path),
          let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return []
    }
    return AgentNativeToolReplayJsonCodec.decode(raw)
  }

  private func saveUnlocked(_ entries: [AgentNativeToolReplayEntry]) {
    do {
      let directory = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      let raw = AgentNativeToolReplayJsonCodec.stringify(entries)
      try raw.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      // Replay persistence should never fail a successful native tool invocation.
    }
  }

  private func retainedEntries(
    _ entries: [AgentNativeToolReplayEntry],
    nowMillis: Int64
  ) -> [AgentNativeToolReplayEntry] {
    entries.filter { nowMillis - $0.savedAtMillis <= AgentNativeToolReplaySnapshotStore.retentionMillis }
  }
}
