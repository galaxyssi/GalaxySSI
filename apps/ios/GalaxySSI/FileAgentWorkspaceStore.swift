import Foundation

final class FileAgentWorkspaceStore: AgentWorkspaceStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let clock: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    fileURL: URL = FileAgentWorkspaceStore.defaultFileURL(),
    fileManager: FileManager = .default,
    clock: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.clock = clock
  }

  static func defaultFileURL(
    storageRootURL: URL = defaultStorageRootURL()
  ) -> URL {
    storageRootURL.appendingPathComponent("workspaces.json", isDirectory: false)
  }

  static func defaultStorageRootURL(fileManager: FileManager = .default) -> URL {
    let base = fileManager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? fileManager.temporaryDirectory
    return base
      .appendingPathComponent("GalaxySSI", isDirectory: true)
      .appendingPathComponent("agent-task-workspaces", isDirectory: true)
  }

  func list() -> [AgentWorkspace] {
    locked {
      loadStore().list()
    }
  }

  func find(_ workspaceId: String) -> AgentWorkspace? {
    locked {
      loadStore().find(workspaceId)
    }
  }

  func upsert(_ workspace: AgentWorkspace, expectedRevision: Int64) throws -> AgentWorkspace {
    try locked {
      let store = loadStore()
      let updated = try store.upsert(workspace, expectedRevision: expectedRevision)
      try persist(store)
      return updated
    }
  }

  func appendEvent(
    workspaceId: String,
    event: AgentWorkspaceEvent,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace? {
    try locked {
      let store = loadStore()
      guard let updated = try store.appendEvent(
        workspaceId: workspaceId,
        event: event,
        expectedRevision: expectedRevision
      ) else {
        return nil
      }
      try persist(store)
      return updated
    }
  }

  func checkpoint(
    workspaceId: String,
    checkpoint: AgentWorkspaceCheckpoint,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace? {
    try locked {
      let store = loadStore()
      guard let updated = try store.checkpoint(
        workspaceId: workspaceId,
        checkpoint: checkpoint,
        expectedRevision: expectedRevision
      ) else {
        return nil
      }
      try persist(store)
      return updated
    }
  }

  func requestCancel(
    _ workspaceId: String,
    expectedRevision: Int64?,
    timestampMillis: Int64
  ) throws -> AgentWorkspace? {
    try locked {
      let store = loadStore()
      guard let updated = try store.requestCancel(
        workspaceId,
        expectedRevision: expectedRevision,
        timestampMillis: timestampMillis
      ) else {
        return nil
      }
      try persist(store)
      return updated
    }
  }

  func delete(_ workspaceId: String, expectedRevision: Int64?) throws -> Bool {
    try locked {
      let store = loadStore()
      let deleted = try store.delete(workspaceId, expectedRevision: expectedRevision)
      if deleted {
        try persist(store)
      }
      return deleted
    }
  }

  func clear() {
    locked {
      try? fileManager.removeItem(at: fileURL)
    }
  }

  func recoverable() -> [AgentWorkspace] {
    locked {
      loadStore().recoverable()
    }
  }

  private func loadStore() -> InMemoryAgentWorkspaceStore {
    guard fileManager.fileExists(atPath: fileURL.path),
      let raw = try? String(contentsOf: fileURL, encoding: .utf8),
      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return InMemoryAgentWorkspaceStore(clock: clock)
    }
    return InMemoryAgentWorkspaceStore(serialized: raw, clock: clock)
  }

  private func persist(_ store: InMemoryAgentWorkspaceStore) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try store.serializedSnapshot().write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
