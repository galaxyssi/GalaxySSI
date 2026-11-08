import Foundation

final class FileAgentNativeToolReplayStore: AgentNativeToolReplayStore {
  private static let globalLock = NSRecursiveLock()

  private let fileURL: URL
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = FileAgentNativeToolReplayStore.globalLock
  private static let cipherPurpose = "galaxyssi.agent.native-effect-replay.v1"

  init(
    fileURL: URL,
    fileManager: FileManager = .default,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.nowMillis = nowMillis
    self.cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, fileManager: fileManager,
      keyAccount: "agent.native-effect-replay.aes256.v1")
  }

  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult? {
    lock.lock()
    defer { lock.unlock() }
    return (try? loadUnlocked())?.last { $0.key == key }?.result
  }

  func observe(_ key: AgentNativeToolReplayKey) -> AgentNativeEffectClaim? {
    lock.lock()
    defer { lock.unlock() }
    guard let entry = (try? loadUnlocked())?.last(where: { $0.key == key }) else { return nil }
    return observation(entry)
  }

  private func observation(_ entry: AgentNativeToolReplayEntry) -> AgentNativeEffectClaim {
    return AgentNativeEffectClaim(
      acquired: false,
      invocationId: entry.invocationId,
      inputSha256: entry.inputSha256,
      result: entry.result,
      recoveryQuery: entry.recoveryQuery
    )
  }

  func claim(
    _ key: AgentNativeToolReplayKey,
    inputSha256: String,
    invocationId: String,
    recoveryQuery: AgentNativeEffectRecoveryQuery?
  ) throws -> AgentNativeEffectClaim {
    lock.lock()
    defer { lock.unlock() }
    var entries = try loadUnlocked()
    if let entry = entries.last(where: { $0.key == key }) { return observation(entry) }
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
      savedAtMillis: nowMillis(),
      recoveryQuery: recoveryQuery
    ))
    try saveUnlocked(entries)
    return AgentNativeEffectClaim(
      acquired: true,
      invocationId: invocationId,
      inputSha256: inputSha256,
      result: nil,
      recoveryQuery: recoveryQuery
    )
  }

  func complete(
    _ key: AgentNativeToolReplayKey,
    invocationId: String,
    result: AgentNativeToolResult
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    var entries = try loadUnlocked()
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
    var entries = try loadUnlocked().filter { $0.key != key }
    entries.append(AgentNativeToolReplayEntry(key: key, result: result, savedAtMillis: nowMillis()))
    try saveUnlocked(entries)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL)
  }

  private func loadUnlocked() throws -> [AgentNativeToolReplayEntry] {
    let bytes: Data
    do { bytes = try Data(contentsOf: fileURL) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return [] }
    if bytes.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
      let legacy = try AgentNativeToolReplayJsonCodec.decodeStrict(bytes)
      guard legacy.allSatisfy({ $0.recoveryQuery == nil }) else { throw AgentNativeToolReplayError.invalidJournal }
      return legacy
    }
    return try AgentNativeToolReplayJsonCodec.decodeStrict(cipher.decrypt(bytes, expectedPurpose: Self.cipherPurpose))
  }

  private func saveUnlocked(_ entries: [AgentNativeToolReplayEntry]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    let raw = Data(AgentNativeToolReplayJsonCodec.stringify(entries).utf8)
    let protected = try cipher.encrypt(raw, purpose: Self.cipherPurpose)
    try protected.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
