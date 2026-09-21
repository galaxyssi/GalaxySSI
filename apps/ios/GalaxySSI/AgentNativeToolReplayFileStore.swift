import Foundation

final class FileAgentNativeToolReplayStore: AgentNativeToolReplayStore {
  private static let globalLock = NSRecursiveLock()

  private let fileURL: URL
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let lock = FileAgentNativeToolReplayStore.globalLock

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
    return loadUnlocked().last { $0.key == key }?.result
  }

  func observe(_ key: AgentNativeToolReplayKey) -> AgentNativeEffectClaim? {
    lock.lock()
    defer { lock.unlock() }
    guard let entry = loadUnlocked().last(where: { $0.key == key }) else { return nil }
    return AgentNativeEffectClaim(
      acquired: false,
      invocationId: entry.invocationId,
      inputSha256: entry.inputSha256,
      result: entry.result
    )
  }

  func claim(
    _ key: AgentNativeToolReplayKey,
    inputSha256: String,
    invocationId: String
  ) throws -> AgentNativeEffectClaim {
    lock.lock()
    defer { lock.unlock() }
    if let observed = observe(key) { return observed }
    var entries = loadUnlocked()
    if key.scope != AgentNativeEffectScope(),
       entries.contains(where: {
         $0.key.toolId == key.toolId &&
           $0.key.toolVersion == key.toolVersion &&
           $0.key.idempotencyKey == key.idempotencyKey &&
           $0.key.scope == AgentNativeEffectScope()
       }) {
      throw AgentNativeToolReplayError.legacyScopeUnverified
    }
    entries.append(AgentNativeToolReplayEntry(
      key: key,
      invocationId: invocationId,
      inputSha256: inputSha256,
      result: nil,
      savedAtMillis: nowMillis()
    ))
    try saveUnlocked(entries)
    return AgentNativeEffectClaim(
      acquired: true,
      invocationId: invocationId,
      inputSha256: inputSha256,
      result: nil
    )
  }

  func complete(
    _ key: AgentNativeToolReplayKey,
    invocationId: String,
    result: AgentNativeToolResult
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    var entries = loadUnlocked()
    guard let index = entries.lastIndex(where: { $0.key == key }) else {
      throw AgentNativeToolReplayError.missingClaim
    }
    let claim = entries[index]
    guard claim.invocationId == invocationId,
          result.receipt.invocationId == invocationId,
          claim.inputSha256 == result.receipt.inputSha256 else {
      throw AgentNativeToolReplayError.claimBindingChanged
    }
    if let previous = claim.result, previous != result {
      throw AgentNativeToolReplayError.outcomeChanged
    }
    entries[index].result = result
    entries[index].savedAtMillis = nowMillis()
    try saveUnlocked(entries)
  }

  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws {
    guard result.isSuccess else {
      throw AgentNativeToolReplayError.unsuccessfulResult
    }
    lock.lock()
    defer { lock.unlock() }
    var entries = loadUnlocked().filter { $0.key != key }
    entries.append(AgentNativeToolReplayEntry(key: key, result: result, savedAtMillis: nowMillis()))
    try saveUnlocked(entries)
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

  private func saveUnlocked(_ entries: [AgentNativeToolReplayEntry]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    let raw = AgentNativeToolReplayJsonCodec.stringify(entries)
    try raw.write(to: fileURL, atomically: true, encoding: .utf8)
    try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
  }
}
