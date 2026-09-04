import Foundation

final class DefaultVoiceLocalWhisperRuntime: VoiceLocalWhisperRuntime, VoiceStatefulLocalWhisperRuntime {
  private struct RuntimeLease {
    var handle: Int64
    var loaded: VoiceWhisperLoadedModel
    var options: VoiceWhisperLoadOptions
  }

  private let modelResolver: (VoiceWhisperModelProfile) throws -> URL
  private let native: VoiceWhisperNativeAPI
  private let markModelLoaded: (String) -> Void
  private let markModelUnloaded: (String?) -> Void
  private let clockMillis: () -> Int64
  private let elapsedMillis: () -> Int64
  private let lifecycleLock = NSRecursiveLock()
  private let decodeLock = NSLock()
  private var runtime: RuntimeLease?
  private var sessions: [String: Session] = [:]
  private var closed = false

  private(set) var state: VoiceWhisperRuntimeState = .unloaded

  convenience init(
    modelManager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    native: VoiceWhisperNativeAPI = GalaxySSIWhisperNativeBridge()
  ) {
    self.init(
      modelResolver: { try modelManager.ensureVerifiedFile(for: $0) },
      native: native,
      markModelLoaded: { modelManager.markLoaded($0) },
      markModelUnloaded: { modelManager.markUnloaded($0) }
    )
  }

  init(
    modelResolver: @escaping (VoiceWhisperModelProfile) throws -> URL,
    native: VoiceWhisperNativeAPI = UnavailableVoiceWhisperNativeBridge(),
    markModelLoaded: @escaping (String) -> Void = { _ in },
    markModelUnloaded: @escaping (String?) -> Void = { _ in },
    clockMillis: @escaping () -> Int64 = DefaultVoiceLocalWhisperRuntime.defaultClockMillis,
    elapsedMillis: @escaping () -> Int64 = DefaultVoiceLocalWhisperRuntime.defaultElapsedMillis
  ) {
    self.modelResolver = modelResolver
    self.native = native
    self.markModelLoaded = markModelLoaded
    self.markModelUnloaded = markModelUnloaded
    self.clockMillis = clockMillis
    self.elapsedMillis = elapsedMillis
    LocalModelWhisperResourceArbiter.shared.register(whisperRuntime: self)
  }

  func transcribe(_ request: VoiceLocalWhisperRuntimeRequest) async throws -> String {
    let options = try VoiceWhisperLoadOptions(threadCount: request.threadCount, warmUp: false)
    _ = try await load(profile: request.model, options: options)
    let config = try VoiceLocalWhisperSessionConfig(
      language: request.language,
      noContext: true,
      mode: request.model.recommendedMode
    )
    let session = try await createSession(config: config)
    defer { session.close() }
    let decode = try VoiceWhisperDecodeRequest(
      pcm16: Self.pcm16(from: request.samples),
      sampleRateHz: request.sampleRateHz,
      mode: request.model.recommendedMode
    )
    let result = try await session.decode(decode)
    guard result.successful else {
      throw VoiceLocalWhisperASRError.inferenceFailed(result.message ?? result.code.description)
    }
    return result.text
  }

  func load(
    profile: VoiceWhisperModelProfile,
    options: VoiceWhisperLoadOptions
  ) async throws -> VoiceWhisperLoadedModel {
    guard profile.supportsIOSRuntime else {
      throw VoiceWhisperModelManagerError.unsupportedPlatform(
        modelId: profile.id,
        artifactFormat: profile.artifactFormat
      )
    }
    LocalModelWhisperResourceArbiter.shared.releaseLocalModelForWhisper()
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    if closed { throw VoiceWhisperRuntimeFailure.closed }
    if let lease = runtime, lease.loaded.profile.id == profile.id, lease.options == options {
      return lease.loaded
    }
    if runtime != nil {
      unloadLocked(reason: .modelSwitch)
    }

    state = .loading(profileId: profile.id)
    let startedAt = elapsedMillis()
    var handle: Int64 = 0
    do {
      let modelFile = try modelResolver(profile).standardizedFileURL
      guard FileManager.default.isReadableFile(atPath: modelFile.path) else {
        throw VoiceWhisperRuntimeFailure.verifiedModelUnavailable
      }
      handle = native.createRuntime(
        modelPath: modelFile.path,
        threadCount: options.threadCount,
        useGPU: options.useGPU
      )
      if handle == 0 {
        throw VoiceWhisperRuntimeFailure.nativeLoadFailed(profile.displayName)
      }
      let warmUpTimings = options.warmUp ? try warmUp(runtimeHandle: handle, options: options) : nil
      let loaded = VoiceWhisperLoadedModel(
        profile: profile,
        threadCount: options.threadCount,
        loadedAtMillis: clockMillis(),
        loadDurationMillis: max(0, elapsedMillis() - startedAt),
        warmUpTimings: warmUpTimings
      )
      runtime = RuntimeLease(handle: handle, loaded: loaded, options: options)
      markModelLoaded(profile.id)
      state = .ready(loaded)
      return loaded
    } catch {
      if handle != 0 {
        native.destroyRuntime(runtimeHandle: handle)
      }
      markModelUnloaded(profile.id)
      state = .failed(
        VoiceWhisperRuntimeError(
          code: .modelNotLoaded,
          message: error.localizedDescription
        )
      )
      throw error
    }
  }

  func createSession(config: VoiceLocalWhisperSessionConfig) async throws -> VoiceLocalWhisperSession {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    if closed { throw VoiceWhisperRuntimeFailure.closed }
    guard let lease = runtime else {
      throw VoiceWhisperRuntimeFailure.modelNotLoaded
    }
    let handle = native.createSession(runtimeHandle: lease.handle, config: config)
    if handle == 0 {
      throw VoiceWhisperRuntimeFailure.sessionCreationFailed
    }
    let session = Session(
      id: UUID().uuidString,
      nativeHandle: handle,
      config: config,
      owner: self
    )
    sessions[session.id] = session
    return session
  }

  func unload(reason: VoiceWhisperUnloadReason = .userRequest) async {
    lifecycleLock.lock()
    unloadLocked(reason: reason)
    lifecycleLock.unlock()
  }

  func runBenchmark(_ request: VoiceWhisperBenchmarkRequest) async throws -> VoiceWhisperBenchmarkResult {
    guard let loaded = currentLoadedModel() else {
      throw VoiceWhisperRuntimeFailure.modelNotLoaded
    }
    var timings: [VoiceNativeWhisperTimings] = []
    for _ in 0..<request.iterations {
      let session = try await createSession(
        config: try VoiceLocalWhisperSessionConfig(language: request.language)
      )
      do {
        defer { session.close() }
        let result = try await session.decode(try VoiceWhisperDecodeRequest(pcm16: request.pcm16))
        if !result.successful {
          throw VoiceWhisperRuntimeFailure.decodeFailed(result.message ?? result.code.description)
        }
        timings.append(result.timings)
      }
    }
    let sorted = timings.map(\.realTimeFactor).sorted()
    return VoiceWhisperBenchmarkResult(
      profileId: loaded.profile.id,
      iterations: timings.count,
      timings: timings,
      medianRealTimeFactor: sorted[sorted.count / 2]
    )
  }

  func requestAbortAll(_ reason: VoiceWhisperAbortReason) {
    lifecycleLock.lock()
    let activeSessions = Array(sessions.values)
    lifecycleLock.unlock()
    activeSessions.forEach { $0.requestAbort(reason) }
  }

  func release() {
    close()
  }

  func releaseForResourcePressure() {
    lifecycleLock.lock()
    unloadLocked(reason: .memoryPressure)
    lifecycleLock.unlock()
  }

  func reservesQnn() -> Bool {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    switch state {
    case .loading, .ready, .decoding:
      return true
    case .unloaded, .unloading, .failed:
      return false
    }
  }

  func close() {
    lifecycleLock.lock()
    if closed {
      lifecycleLock.unlock()
      return
    }
    closed = true
    unloadLocked(reason: .appShutdown)
    lifecycleLock.unlock()
  }

  func activeNativeHandles() -> (runtimes: Int, sessions: Int) {
    (native.activeRuntimeCount(), native.activeSessionCount())
  }

  private func warmUp(
    runtimeHandle: Int64,
    options: VoiceWhisperLoadOptions
  ) throws -> VoiceNativeWhisperTimings {
    let config = try VoiceLocalWhisperSessionConfig(language: "en", noContext: true, singleSegment: true)
    let sessionHandle = native.createSession(runtimeHandle: runtimeHandle, config: config)
    if sessionHandle == 0 {
      throw VoiceWhisperRuntimeFailure.sessionCreationFailed
    }
    defer { native.destroySession(sessionHandle: sessionHandle) }
    let result = native.decodePcm16(
      sessionHandle: sessionHandle,
      pcm: Array(repeating: 0, count: options.warmUpSamples),
      offset: 0,
      length: options.warmUpSamples
    )
    if !result.successful {
      throw VoiceWhisperRuntimeFailure.decodeFailed(result.message ?? result.code.description)
    }
    return result.timings
  }

  private func unloadLocked(reason: VoiceWhisperUnloadReason) {
    guard let lease = runtime else {
      state = .unloaded
      return
    }
    state = .unloading(reason: reason)
    requestAbortAll(.runtimeUnload)
    let activeSessions = Array(sessions.values)
    activeSessions.forEach { $0.close() }
    sessions.removeAll()
    native.destroyRuntime(runtimeHandle: lease.handle)
    markModelUnloaded(lease.loaded.profile.id)
    runtime = nil
    state = .unloaded
  }

  private func currentLoadedModel() -> VoiceWhisperLoadedModel? {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    return runtime?.loaded
  }

  private func decode(
    session: Session,
    request: VoiceWhisperDecodeRequest
  ) throws -> VoiceNativeWhisperResult {
    decodeLock.lock()
    defer { decodeLock.unlock() }
    lifecycleLock.lock()
    guard !session.isClosed else {
      lifecycleLock.unlock()
      throw VoiceWhisperRuntimeFailure.sessionClosed
    }
    guard let loaded = runtime?.loaded else {
      lifecycleLock.unlock()
      throw VoiceWhisperRuntimeFailure.modelNotLoaded
    }
    state = .decoding(sessionId: session.id, mode: request.mode)
    lifecycleLock.unlock()

    let result = native.decodePcm16(
      sessionHandle: session.nativeHandle,
      pcm: request.pcm16,
      offset: request.offset,
      length: request.length
    )

    lifecycleLock.lock()
    if runtime?.loaded.profile.id == loaded.profile.id, !closed {
      state = .ready(loaded)
    }
    lifecycleLock.unlock()
    return result
  }

  private func removeSession(_ session: Session) {
    lifecycleLock.lock()
    sessions.removeValue(forKey: session.id)
    lifecycleLock.unlock()
  }

  private static func pcm16(from samples: [Float]) -> [Int16] {
    samples.map { sample in
      let clamped = min(1, max(-1, sample))
      let scaled = Int((clamped * 32_767).rounded())
      return Int16(max(Int(Int16.min), min(Int(Int16.max), scaled)))
    }
  }

  private static func defaultClockMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static func defaultElapsedMillis() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
  }

  private final class Session: VoiceLocalWhisperSession {
    let id: String
    let nativeHandle: Int64
    let config: VoiceLocalWhisperSessionConfig
    private weak var owner: DefaultVoiceLocalWhisperRuntime?
    private let lock = NSLock()
    private var closed = false

    var isClosed: Bool {
      lock.lock()
      defer { lock.unlock() }
      return closed
    }

    init(
      id: String,
      nativeHandle: Int64,
      config: VoiceLocalWhisperSessionConfig,
      owner: DefaultVoiceLocalWhisperRuntime
    ) {
      self.id = id
      self.nativeHandle = nativeHandle
      self.config = config
      self.owner = owner
    }

    func decode(_ request: VoiceWhisperDecodeRequest) async throws -> VoiceNativeWhisperResult {
      guard let owner else {
        throw VoiceWhisperRuntimeFailure.closed
      }
      return try owner.decode(session: self, request: request)
    }

    func requestAbort(_ reason: VoiceWhisperAbortReason) {
      owner?.native.requestAbort(sessionHandle: nativeHandle)
    }

    func close() {
      lock.lock()
      if closed {
        lock.unlock()
        return
      }
      closed = true
      lock.unlock()
      owner?.native.requestAbort(sessionHandle: nativeHandle)
      owner?.removeSession(self)
      owner?.native.destroySession(sessionHandle: nativeHandle)
    }
  }
}

private extension VoiceNativeWhisperCode {
  var description: String { String(describing: self) }
}
