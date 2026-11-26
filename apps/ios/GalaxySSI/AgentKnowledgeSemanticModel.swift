import Combine
import Foundation
import UIKit

enum AgentKnowledgeEmbeddingModel {
  static let id = "bge-small-zh-v1.5-q8_0"
  static let fileName = "\(id).gguf"
  static let expectedBytes: Int64 = 26_472_640
  static let sha256 = "5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039"
  static let revision = "5bf683e6a1bd454bbb60ba051088c50731d63fcb"
  static let dimensions = 512
  static let contextTokens = 512
  static let urls = [
    URL(string: "https://huggingface.co/CompendiumLabs/bge-small-zh-v1.5-gguf/resolve/\(revision)/\(fileName)")!,
    URL(string: "https://hf-mirror.com/CompendiumLabs/bge-small-zh-v1.5-gguf/resolve/\(revision)/\(fileName)")!
  ]
}

enum AgentKnowledgeSemanticPhase: String, Codable {
  case notInstalled = "NOT_INSTALLED"
  case downloading = "DOWNLOADING"
  case verifying = "VERIFYING"
  case ready = "READY"
  case indexing = "INDEXING"
  case disabled = "DISABLED"
  case failed = "FAILED"
}

struct AgentKnowledgeSemanticState: Codable, Equatable {
  var installed = false
  var enabled = false
  var phase: AgentKnowledgeSemanticPhase = .notInstalled
  var downloadedBytes: Int64 = 0
  var indexedChunks = 0
  var pendingDocuments = 0
  var enrollmentPending = false
  var countsPending = false
  var countsError = ""
  var downloadRequestId = ""
  var error = ""

  private enum CodingKeys: String, CodingKey {
    case installed, enabled, phase, downloadedBytes, indexedChunks, pendingDocuments
    case enrollmentPending, countsPending, countsError, downloadRequestId, error
  }

  init(
    installed: Bool = false,
    enabled: Bool = false,
    phase: AgentKnowledgeSemanticPhase = .notInstalled,
    downloadedBytes: Int64 = 0,
    indexedChunks: Int = 0,
    pendingDocuments: Int = 0,
    enrollmentPending: Bool = false,
    countsPending: Bool = false,
    countsError: String = "",
    downloadRequestId: String = "",
    error: String = ""
  ) {
    self.installed = installed
    self.enabled = enabled
    self.phase = phase
    self.downloadedBytes = downloadedBytes
    self.indexedChunks = indexedChunks
    self.pendingDocuments = pendingDocuments
    self.enrollmentPending = enrollmentPending
    self.countsPending = countsPending
    self.countsError = countsError
    self.downloadRequestId = downloadRequestId
    self.error = error
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    installed = try values.decodeIfPresent(Bool.self, forKey: .installed) ?? false
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    phase = try values.decodeIfPresent(AgentKnowledgeSemanticPhase.self, forKey: .phase) ?? .notInstalled
    downloadedBytes = try values.decodeIfPresent(Int64.self, forKey: .downloadedBytes) ?? 0
    indexedChunks = try values.decodeIfPresent(Int.self, forKey: .indexedChunks) ?? 0
    pendingDocuments = try values.decodeIfPresent(Int.self, forKey: .pendingDocuments) ?? 0
    enrollmentPending = try values.decodeIfPresent(Bool.self, forKey: .enrollmentPending) ?? false
    countsPending = try values.decodeIfPresent(Bool.self, forKey: .countsPending) ?? false
    countsError = try values.decodeIfPresent(String.self, forKey: .countsError) ?? ""
    downloadRequestId = try values.decodeIfPresent(String.self, forKey: .downloadRequestId) ?? ""
    error = try values.decodeIfPresent(String.self, forKey: .error) ?? ""
  }
}

final class AgentKnowledgeSemanticModelStorage {
  private let fileManager: FileManager
  let rootURL: URL

  init(fileManager: FileManager = .default, rootURL: URL? = nil) {
    self.fileManager = fileManager
    if let rootURL {
      self.rootURL = rootURL
    } else {
      let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fileManager.temporaryDirectory
      self.rootURL = root.appendingPathComponent("GalaxySSI/KnowledgeModels", isDirectory: true)
    }
  }

  var modelURL: URL { rootURL.appendingPathComponent(AgentKnowledgeEmbeddingModel.fileName) }
  var partialURL: URL { rootURL.appendingPathComponent("\(AgentKnowledgeEmbeddingModel.fileName).part") }

  var installed: Bool { fileSize(modelURL) == AgentKnowledgeEmbeddingModel.expectedBytes }
  var partialBytes: Int64 { min(fileSize(partialURL), AgentKnowledgeEmbeddingModel.expectedBytes) }

  func download(progress: @escaping (Int64) -> Void) async throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    if installed, (try? verifyInstalled()) != nil {
      progress(AgentKnowledgeEmbeddingModel.expectedBytes)
      return
    }
    if fileSize(partialURL) > AgentKnowledgeEmbeddingModel.expectedBytes {
      try? fileManager.removeItem(at: partialURL)
    }
    var lastError: Error?
    for url in AgentKnowledgeEmbeddingModel.urls {
      try Task.checkCancellation()
      do {
        var offset = partialBytes
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
          throw URLError(.badServerResponse)
        }
        let append = offset > 0 && http.statusCode == 206 &&
          http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(offset)-") == true
        if !append { offset = 0 }
        guard offset + Int64(data.count) <= AgentKnowledgeEmbeddingModel.expectedBytes else {
          throw URLError(.dataLengthExceedsMaximum)
        }
        if !append { try? fileManager.removeItem(at: partialURL) }
        if !fileManager.fileExists(atPath: partialURL.path) {
          fileManager.createFile(atPath: partialURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partialURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        progress(offset + Int64(data.count))
        guard fileSize(partialURL) == AgentKnowledgeEmbeddingModel.expectedBytes else {
          throw URLError(.networkConnectionLost)
        }
        do {
          try verify(partialURL)
        } catch {
          try? fileManager.removeItem(at: partialURL)
          throw error
        }
        try atomicInstall(partialURL)
        return
      } catch {
        lastError = error
      }
    }
    throw lastError ?? URLError(.cannotLoadFromNetwork)
  }

  func importFile(_ sourceURL: URL) throws {
    let scoped = sourceURL.startAccessingSecurityScopedResource()
    defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let temporary = rootURL.appendingPathComponent("import-\(UUID().uuidString).part")
    defer { try? fileManager.removeItem(at: temporary) }
    try fileManager.copyItem(at: sourceURL, to: temporary)
    try verify(temporary)
    try atomicInstall(temporary)
  }

  func verifyInstalled() throws {
    try verify(modelURL)
  }

  func delete() {
    try? fileManager.removeItem(at: modelURL)
    try? fileManager.removeItem(at: partialURL)
  }

  private func verify(_ url: URL) throws {
    guard fileSize(url) == AgentKnowledgeEmbeddingModel.expectedBytes,
          try LocalModelRuntimeStorage.sha256(fileURL: url) == AgentKnowledgeEmbeddingModel.sha256 else {
      throw LocalModelRuntimeStorageError.sha256Mismatch
    }
  }

  private func atomicInstall(_ sourceURL: URL) throws {
    let replacement = rootURL.appendingPathComponent("verified-\(UUID().uuidString).gguf")
    try? fileManager.removeItem(at: replacement)
    try fileManager.moveItem(at: sourceURL, to: replacement)
    if fileManager.fileExists(atPath: modelURL.path) {
      _ = try fileManager.replaceItemAt(modelURL, withItemAt: replacement, backupItemName: nil, options: [])
    } else {
      try fileManager.moveItem(at: replacement, to: modelURL)
    }
  }

  private func fileSize(_ url: URL) -> Int64 {
    let values = try? fileManager.attributesOfItem(atPath: url.path)
    return (values?[.size] as? NSNumber)?.int64Value ?? 0
  }
}

@MainActor
final class AgentKnowledgeSemanticController: ObservableObject {
  private static var instances: [ObjectIdentifier: AgentKnowledgeSemanticController] = [:]

  static func shared(database: AgentKnowledgeDatabase) -> AgentKnowledgeSemanticController {
    let key = ObjectIdentifier(database)
    if let existing = instances[key] { return existing }
    let controller = AgentKnowledgeSemanticController(database: database)
    instances[key] = controller
    return controller
  }

  @Published private(set) var state: AgentKnowledgeSemanticState

  private let database: AgentKnowledgeDatabase
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let storage: AgentKnowledgeSemanticModelStorage
  private var work: Task<Void, Never>?
  private var countWork: Task<Void, Never>?
  private var runtime: GalaxySSIEmbeddingRuntime?
  private var runtimeOpening: (id: UUID, task: Task<GalaxySSIEmbeddingRuntime, Error>)?
  private var semanticSearch: AgentKnowledgeSemanticSearch?
  private var nativeObservers: [NSObjectProtocol] = []
  private var idleCleanupTask: Task<Void, Never>?
  private var activeQueries = 0
  private let stateKey = "galaxyssi.agent.knowledge.semantic-model.v1"

  init(
    database: AgentKnowledgeDatabase,
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    storage: AgentKnowledgeSemanticModelStorage = AgentKnowledgeSemanticModelStorage(),
    automaticallyStart: Bool = true
  ) {
    self.database = database
    self.defaults = defaults
    self.secrets = secrets
    self.storage = storage
    state = Self.loadState(defaults: defaults, secrets: secrets)
    state.installed = storage.installed
    state.downloadedBytes = storage.partialBytes
    if !state.installed && state.phase == .ready { state.phase = .notInstalled }
    guard automaticallyStart else { return }
    for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification] {
      nativeObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if name == UIApplication.didBecomeActiveNotification { self.startIndexing() }
          else if !self.canUseNativeIndex || self.database.nativeFiles.activeToken() == nil {
            if self.state.phase == .indexing { self.work?.cancel() }
            await self.closeRuntime()
            if self.canUseNativeIndex { self.startIndexing() }
          }
        }
      })
    }
    startCountMaintenance()
    if !state.downloadRequestId.isEmpty {
      startDownload(recovering: true)
    } else if state.installed, state.enabled {
      startIndexing()
    }
  }

  deinit {
    for observer in nativeObservers { NotificationCenter.default.removeObserver(observer) }
    idleCleanupTask?.cancel()
    runtimeOpening?.task.cancel()
  }

  func startDownload(recovering: Bool = false) {
    guard work == nil else { return }
    if !recovering || state.downloadRequestId.isEmpty { state.downloadRequestId = UUID().uuidString }
    state.phase = .downloading
    state.error = ""
    persist()
    let requestId = state.downloadRequestId
    work = Task { [weak self] in
      guard let self else { return }
      do {
        try await storage.download { bytes in
          Task { @MainActor [weak self] in self?.state.downloadedBytes = bytes }
        }
        try Task.checkCancellation()
        guard state.downloadRequestId == requestId else { return }
        state.installed = true
        state.enabled = true
        state.phase = .ready
        state.downloadRequestId = ""
        persist()
        work = nil
        startIndexing()
      } catch is CancellationError {
        work = nil
      } catch {
        state.phase = .failed
        state.error = String(error.localizedDescription.prefix(180))
        state.downloadRequestId = ""
        persist()
        work = nil
      }
    }
  }

  func cancelDownload() {
    state.downloadRequestId = ""
    work?.cancel()
    work = nil
    state.phase = state.installed ? .ready : .notInstalled
    persist()
  }

  func importModel(_ url: URL) {
    work?.cancel()
    work = Task { [weak self] in
      guard let self else { return }
      do {
        state.phase = .verifying
        let storage = self.storage
        try await Task.detached(priority: .utility) { try storage.importFile(url) }.value
        try Task.checkCancellation()
        state.installed = true
        state.enabled = true
        state.phase = .ready
        state.downloadRequestId = ""
        persist()
        work = nil
        startIndexing()
      } catch is CancellationError {
        state.phase = state.installed ? (state.enabled ? .ready : .disabled) : .notInstalled
        work = nil
      } catch {
        state.phase = .failed
        state.error = String(error.localizedDescription.prefix(180))
        persist()
        work = nil
      }
    }
  }

  func setEnabled(_ enabled: Bool) {
    if !enabled {
      AgentKnowledgeBackgroundScheduler.cancel()
      work?.cancel()
      state.enabled = false
      state.phase = .disabled
      persist()
      Task { await closeRuntime() }
      return
    }
    guard work == nil else { return }
    work = Task { [weak self] in
      guard let self else { return }
      do {
        let storage = self.storage
        if enabled { try await Task.detached(priority: .utility) { try storage.verifyInstalled() }.value }
        try Task.checkCancellation()
        state.enabled = enabled
        state.installed = storage.installed
        state.phase = enabled ? .ready : .disabled
        persist()
        if !enabled { await closeRuntime() }
        work = nil
        if enabled { startIndexing() }
      } catch {
        state.phase = .failed
        state.error = String(error.localizedDescription.prefix(180))
        persist()
        work = nil
      }
    }
  }

  func startIndexing() {
    guard state.enabled, state.installed, work == nil else { return }
    AgentKnowledgeBackgroundScheduler.schedule(pending: true)
    guard canUseNativeIndex else { return }
    idleCleanupTask?.cancel()
    idleCleanupTask = nil
    work = Task { [weak self] in
      guard let self else { return }
      var interrupted = false
      var successor = true
      do {
        state.phase = .indexing
        state.error = ""
        let runtime = try await ensureRuntime()
        let indexer = AgentKnowledgeVectorIndexer(database: database, runtime: runtime, provenance: provenance)
        let search = ensureSemanticSearch(runtime: runtime)
        while true {
          try Task.checkCancellation()
          let nativeEnrollmentComplete = try await Task.detached(priority: .utility) { [database = self.database, provenance = self.provenance] in
            try database.maintainNativeVectorEnrollment(provenance: provenance)
          }.value
          try Task.checkCancellation()
          let indexed = try await indexer.indexPending(pageSize: 32)
          let enrollmentPending = try database.vectorEnrollmentPending(
            modelSHA256: AgentKnowledgeEmbeddingModel.sha256
          )
          state.enrollmentPending = enrollmentPending || !nativeEnrollmentComplete
          try refreshCounts()
          let replayPending: Bool
          if canUseNativeIndex { replayPending = try await search.advanceReplay() }
          else { replayPending = false }
          if indexed == 0 && !enrollmentPending && nativeEnrollmentComplete && !replayPending {
            successor = !canUseNativeIndex
            break
          }
          await Task.yield()
        }
        try refreshCounts()
        state.enrollmentPending = false
        state.phase = .ready
        persist()
      } catch is CancellationError {
        interrupted = true
        state.phase = state.enabled && state.installed ? .ready : (state.installed ? .disabled : .notInstalled)
      } catch {
        if Task.isCancelled {
          state.phase = state.enabled && state.installed ? .ready : (state.installed ? .disabled : .notInstalled)
        } else {
          state.phase = .failed
          state.error = String(error.localizedDescription.prefix(180))
          persist()
        }
      }
      work = nil
      AgentKnowledgeBackgroundScheduler.schedule(pending: state.enabled && state.installed && successor)
      if Task.isCancelled || interrupted, canUseNativeIndex, database.nativeFiles.activeToken() != nil,
        state.enabled, state.installed { startIndexing() }
      else { scheduleIdleCleanup() }
    }
  }

  func hybridSearch(query: String, lexicalHits: [AgentKnowledgeHit], limit: Int) async -> [AgentKnowledgeHit] {
    guard state.enabled, state.installed else { return lexicalHits }
    idleCleanupTask?.cancel()
    idleCleanupTask = nil
    activeQueries += 1
    defer { activeQueries -= 1; scheduleIdleCleanup() }
    guard canUseNativeIndex, let token = database.nativeFiles.activeToken() else { return [] }
    do {
      let runtime = try await ensureRuntime()
      guard database.nativeFiles.activeToken() == token, state.enabled, state.installed else { return [] }
      let hits = try await ensureSemanticSearch(runtime: runtime).search(query: query, lexicalHits: lexicalHits, limit: limit)
      guard !Task.isCancelled, canUseNativeIndex, database.nativeFiles.activeToken() == token,
        state.enabled, state.installed else { return [] }
      return hits
    } catch {
      guard !Task.isCancelled, canUseNativeIndex, database.nativeFiles.activeToken() == token,
        state.enabled, state.installed else { return [] }
      let database = self.database, model = provenance.modelSHA256
      let fresh = try? await Task.detached(priority: .utility) {
        let stamp = try database.vectorFeedStamp(modelSHA256: model)
        let hits = try database.validatedLexicalHits(Array(lexicalHits.prefix(256)), stamp: stamp, modelSHA256: model)
        guard try database.vectorFeedStamp(modelSHA256: model) == stamp else { throw AgentKnowledgeDatabaseError.staleCursor }
        return Array(hits.prefix(min(max(limit, 0), 256)))
      }.value
      guard !Task.isCancelled, canUseNativeIndex, database.nativeFiles.activeToken() == token,
        state.enabled, state.installed else { return [] }
      return fresh ?? []
    }
  }

  private var canUseNativeIndex: Bool {
    UIApplication.shared.applicationState == .active && UIApplication.shared.isProtectedDataAvailable
  }

  private func ensureSemanticSearch(runtime: GalaxySSIEmbeddingRuntime) -> AgentKnowledgeSemanticSearch {
    if let semanticSearch { return semanticSearch }
    let search = AgentKnowledgeSemanticSearch(database: database, runtime: runtime, provenance: provenance)
    semanticSearch = search
    return search
  }

  func destroyPrivateData() {
    AgentKnowledgeBackgroundScheduler.cancel()
    work?.cancel()
    countWork?.cancel()
    database.nativeFiles.invalidate()
    let nativeCleanupError: Error?
    do { try database.nativeFiles.destroy(); nativeCleanupError = nil }
    catch { nativeCleanupError = error }
    storage.delete()
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: stateKey, secrets: secrets)
    state = AgentKnowledgeSemanticState()
    if let nativeCleanupError {
      state.phase = .failed
      state.error = String(nativeCleanupError.localizedDescription.prefix(180))
    }
    Task { await closeRuntime() }
  }

  private var provenance: AgentKnowledgeVectorProvenance {
    AgentKnowledgeVectorProvenance(
      modelSHA256: AgentKnowledgeEmbeddingModel.sha256,
      dimensions: AgentKnowledgeEmbeddingModel.dimensions,
      contextTokens: AgentKnowledgeEmbeddingModel.contextTokens,
      chunkingContract: AgentKnowledgeEmbeddingChunker.contract
    )
  }

  // One system-granted slice; do not instantiate the foreground search consumer
  // or reopen its UI permissions. Every exit closes the independently owned runtime.
  func runBackgroundSlice(lease: AgentKnowledgeNativeFiles.BackgroundLease) async throws -> Bool {
    guard state.enabled, state.installed, UIApplication.shared.isProtectedDataAvailable else { throw CancellationError() }
    let check: () throws -> Void = {
      try Task.checkCancellation()
      guard lease.isValid else { throw CancellationError() }
    }
    try check()
    let storage = self.storage
    try await Task.detached(priority: .utility) { try storage.verifyInstalled() }.value
    try check()
    let opened = try await GalaxySSIEmbeddingRuntime.open(modelURL: storage.modelURL,
      contextTokens: provenance.contextTokens, threads: min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 4))
    let spec = provenance, database = self.database
    let native = AgentKnowledgeNativeIndex(database: database, provenance: spec, backgroundLease: lease)
    defer { native.close() }
    do {
      try check()
      let enrolled = try await Task.detached(priority: .utility) {
        try database.maintainNativeVectorEnrollment(provenance: spec, pageSize: 16)
      }.value
      try check()
      let producer = AgentKnowledgeVectorIndexer(database: database, runtime: opened, provenance: spec, activeCheck: check)
      _ = try await producer.indexPending(pageSize: 4, maximumChunks: 16)
      try check()
      _ = try await Task.detached(priority: .utility) { try native.advance(maxPages: 4, token: lease.token) }.value
      try check()
      let sourcePending = try database.vectorWorkPending(modelSHA256: spec.modelSHA256)
      let pending = !enrolled || sourcePending || native.needsReplay
      await opened.close()
      return pending
    } catch {
      await opened.close()
      throw error
    }
  }

  private func ensureRuntime() async throws -> GalaxySSIEmbeddingRuntime {
    if let runtime { return runtime }
    if let runtimeOpening { return try await runtimeOpening.task.value }
    let token = database.nativeFiles.token()
    let requestId = UUID()
    let opening = Task { [self] in
      defer { if runtimeOpening?.id == requestId { runtimeOpening = nil } }
      let opened = try await GalaxySSIEmbeddingRuntime.open(
        modelURL: storage.modelURL,
        contextTokens: AgentKnowledgeEmbeddingModel.contextTokens,
        threads: min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 8)
      )
      guard !Task.isCancelled, database.nativeFiles.token() == token, state.enabled, state.installed,
        runtimeOpening?.id == requestId else {
        await opened.close()
        throw CancellationError()
      }
      runtime = opened
      return opened
    }
    runtimeOpening = (requestId, opening)
    return try await opening.value
  }

  private func closeRuntime() async {
    idleCleanupTask?.cancel()
    idleCleanupTask = nil
    runtimeOpening?.task.cancel()
    runtimeOpening = nil
    database.nativeFiles.invalidate()
    semanticSearch?.clearTransientIndex()
    semanticSearch = nil
    let closing = runtime
    runtime = nil
    await closing?.close()
  }

  private func scheduleIdleCleanup() {
    idleCleanupTask?.cancel()
    idleCleanupTask = nil
    guard state.enabled, state.installed, canUseNativeIndex, work == nil, activeQueries == 0 else { return }
    idleCleanupTask = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
      guard let self, self.work == nil, self.activeQueries == 0 else { return }
      self.idleCleanupTask = nil
      await self.closeRuntime()
    }
  }

  private func startCountMaintenance() {
    guard countWork == nil else { return }
    state.countsError = ""
    countWork = Task { [weak self] in
      guard let self else { return }
      do {
        while !Task.isCancelled {
          let complete = try await Task.detached(priority: .utility) {
            try self.database.maintainVectorCounts(pageSize: 64)
          }.value
          try refreshCounts()
          if complete { break }
          await Task.yield()
        }
      } catch is CancellationError {
        // The durable cursor resumes on the next controller lifetime.
      } catch {
        state.countsError = String(error.localizedDescription.prefix(180))
      }
      countWork = nil
      persist()
    }
  }

  private func refreshCounts() throws {
    let snapshot = try database.vectorCountSnapshot(modelSHA256: AgentKnowledgeEmbeddingModel.sha256)
    state.indexedChunks = Int(clamping: snapshot.chunks)
    state.pendingDocuments = Int(clamping: snapshot.pending)
    state.countsPending = !snapshot.complete
    if snapshot.complete { state.countsError = "" }
  }

  private func persist() {
    guard let data = try? JSONEncoder.galaxySSI.encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: stateKey, secrets: secrets)
  }

  private static func loadState(defaults: UserDefaults, secrets: GalaxySSISecretStore) -> AgentKnowledgeSemanticState {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: "galaxyssi.agent.knowledge.semantic-model.v1", secrets: secrets),
          let state = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeSemanticState.self, from: data) else {
      return AgentKnowledgeSemanticState()
    }
    return state
  }
}
