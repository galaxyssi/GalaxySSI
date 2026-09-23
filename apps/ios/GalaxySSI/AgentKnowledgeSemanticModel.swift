import Combine
import Foundation

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
  private var semanticSearch: AgentKnowledgeSemanticSearch?
  private let stateKey = "galaxyssi.agent.knowledge.semantic-model.v1"

  init(
    database: AgentKnowledgeDatabase,
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    storage: AgentKnowledgeSemanticModelStorage = AgentKnowledgeSemanticModelStorage()
  ) {
    self.database = database
    self.defaults = defaults
    self.secrets = secrets
    self.storage = storage
    state = Self.loadState(defaults: defaults, secrets: secrets)
    state.installed = storage.installed
    state.downloadedBytes = storage.partialBytes
    if !state.installed && state.phase == .ready { state.phase = .notInstalled }
    startCountMaintenance()
    if !state.downloadRequestId.isEmpty {
      startDownload(recovering: true)
    } else if state.installed, state.enabled {
      startIndexing()
    }
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
        state.installed = true
        state.enabled = true
        state.phase = .ready
        state.downloadRequestId = ""
        persist()
        work = nil
        startIndexing()
      } catch {
        state.phase = .failed
        state.error = String(error.localizedDescription.prefix(180))
        persist()
        work = nil
      }
    }
  }

  func setEnabled(_ enabled: Bool) {
    guard work == nil else { return }
    work = Task { [weak self] in
      guard let self else { return }
      do {
        let storage = self.storage
        if enabled { try await Task.detached(priority: .utility) { try storage.verifyInstalled() }.value }
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
    work = Task { [weak self] in
      guard let self else { return }
      do {
        state.phase = .indexing
        let runtime = try await ensureRuntime()
        let indexer = AgentKnowledgeVectorIndexer(database: database, runtime: runtime, provenance: provenance)
        while true {
          let indexed = try await indexer.indexPending(pageSize: 32)
          let enrollmentPending = try database.vectorEnrollmentPending(
            modelSHA256: AgentKnowledgeEmbeddingModel.sha256
          )
          state.enrollmentPending = enrollmentPending
          try refreshCounts()
          if indexed == 0 && !enrollmentPending { break }
        }
        try refreshCounts()
        state.enrollmentPending = false
        state.phase = .ready
        persist()
      } catch is CancellationError {
        state.phase = .ready
      } catch {
        state.phase = .failed
        state.error = String(error.localizedDescription.prefix(180))
        persist()
      }
      work = nil
    }
  }

  func hybridSearch(query: String, lexicalHits: [AgentKnowledgeHit], limit: Int) async -> [AgentKnowledgeHit] {
    guard state.enabled, state.installed else { return lexicalHits }
    do {
      let runtime = try await ensureRuntime()
      if semanticSearch == nil {
        semanticSearch = AgentKnowledgeSemanticSearch(database: database, runtime: runtime, provenance: provenance)
      }
      return try await semanticSearch?.search(query: query, lexicalHits: lexicalHits, limit: limit) ?? lexicalHits
    } catch {
      return lexicalHits
    }
  }

  func destroyPrivateData() {
    work?.cancel()
    countWork?.cancel()
    storage.delete()
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: stateKey, secrets: secrets)
    state = AgentKnowledgeSemanticState()
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

  private func ensureRuntime() async throws -> GalaxySSIEmbeddingRuntime {
    if let runtime { return runtime }
    let opened = try await GalaxySSIEmbeddingRuntime.open(
      modelURL: storage.modelURL,
      contextTokens: AgentKnowledgeEmbeddingModel.contextTokens,
      threads: min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 8)
    )
    runtime = opened
    return opened
  }

  private func closeRuntime() async {
    semanticSearch?.clearTransientIndex()
    semanticSearch = nil
    await runtime?.close()
    runtime = nil
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
