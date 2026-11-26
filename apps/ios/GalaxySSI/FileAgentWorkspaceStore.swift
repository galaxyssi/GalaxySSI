import Foundation

final class FileAgentWorkspaceStore: AgentWorkspaceStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let clock: () -> Int64
  private let lock: NSRecursiveLock
  private let writeFile: (Data, URL) throws -> Void
  private let readFile: (URL) throws -> Data
  private let timingClock: () -> Int64
  private let timingSink: AgentWorkspaceCreationTiming.Sink
  private static let gatesLock = NSLock()
  private static var fileGates: [String: NSRecursiveLock] = [:]

  private static func gate(for url: URL) -> NSRecursiveLock {
    gatesLock.lock()
    defer { gatesLock.unlock() }
    let path = url.standardizedFileURL.path
    if let gate = fileGates[path] { return gate }
    let gate = NSRecursiveLock()
    fileGates[path] = gate
    return gate
  }

  init(
    fileURL: URL = FileAgentWorkspaceStore.defaultFileURL(),
    fileManager: FileManager = .default,
    clock: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
    writeFile: @escaping (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    },
    timingClock: @escaping () -> Int64 = AgentWorkspaceCreationTiming.monotonicMillis,
    timingSink: @escaping AgentWorkspaceCreationTiming.Sink = AgentWorkspaceCreationTiming.log
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.clock = clock
    self.writeFile = writeFile
    self.readFile = readFile
    self.timingClock = timingClock
    self.timingSink = timingSink
    lock = Self.gate(for: fileURL)
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
      (try? loadStore().list()) ?? []
    }
  }

  func find(_ workspaceId: String) -> AgentWorkspace? {
    locked {
      try? loadStore().find(workspaceId)
    }
  }

  func upsert(_ workspace: AgentWorkspace, expectedRevision: Int64) throws -> AgentWorkspace {
    try locked {
      let preparationStarted = timingClock()
      let store = try loadStore()
      let isNew = store.find(workspace.workspaceId) == nil
      let updated = try store.upsert(workspace, expectedRevision: expectedRevision)
      try persist(store, creation: isNew ? (updated.taskId, preparationStarted) : nil)
      return updated
    }
  }

  func appendEvent(
    workspaceId: String,
    event: AgentWorkspaceEvent,
    expectedRevision: Int64?
  ) throws -> AgentWorkspace? {
    try locked {
      let store = try loadStore()
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
      let store = try loadStore()
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
      let store = try loadStore()
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
      let store = try loadStore()
      let deleted = try store.delete(workspaceId, expectedRevision: expectedRevision)
      if deleted {
        try persist(store)
      }
      return deleted
    }
  }

  func clear() {
    locked {
      guard fileManager.fileExists(atPath: fileURL.path) else { return }
      do {
        try fileManager.removeItem(at: fileURL)
        NotificationCenter.default.post(name: .galaxySSIWorkspaceDidPersist, object: self)
      } catch {
        // Keep the existing snapshot visible when clearing persistent state failed.
      }
    }
  }

  func recoverable() -> [AgentWorkspace] {
    locked {
      (try? loadStore().recoverable()) ?? []
    }
  }

  private func loadStore() throws -> InMemoryAgentWorkspaceStore {
    guard fileURL.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let data: Data
    do { data = try readFile(fileURL) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return InMemoryAgentWorkspaceStore(clock: clock)
    }
    guard let raw = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
    return InMemoryAgentWorkspaceStore(
      initialWorkspaces: try AgentWorkspaceJsonCodec.decodePersistedList(raw), clock: clock
    )
  }

  private func persist(_ store: InMemoryAgentWorkspaceStore,
    creation: (taskId: String, started: Int64)? = nil) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // Publish only after the complete record/recovery snapshot has committed.
    let data = Data(store.serializedSnapshot().utf8)
    let commitStarted = creation == nil ? nil : timingClock()
    try writeFile(data, fileURL)
    if let creation, let commitStarted {
      timingSink(AgentWorkspaceCreationTiming.sample(taskId: creation.taskId,
        started: creation.started, commitStarted: commitStarted, committed: timingClock()))
    }
    NotificationCenter.default.post(name: .galaxySSIWorkspaceDidPersist, object: self)
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
