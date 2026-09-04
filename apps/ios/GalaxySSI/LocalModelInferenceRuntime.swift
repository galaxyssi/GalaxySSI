import Foundation

final class LocalModelInferenceRuntime {
  static let shared = LocalModelInferenceRuntime()

  private let lock = NSLock()
  private let idleReleaseQueue = DispatchQueue(
    label: "com.galaxyssi.ios.local-model-idle-release",
    qos: .utility
  )
  private let inferenceQueue = DispatchQueue(
    label: LocalModelInferenceExecutionPolicy.executorLabel,
    qos: .userInitiated
  )
  private let storage: LocalModelRuntimeStorage
  private let followsRegistry: Bool
  private var backend: LocalModelInferenceBackend
  private var loadedProfile = ""
  private var loadedContextTokens = 0
  private var foregroundWaiters = 0
  private var foregroundLeaseUntilUptime = ProcessInfo.processInfo.systemUptime + LocalModelInferenceRuntime.backgroundStartupGraceSeconds
  private var idleReleaseWorkItem: DispatchWorkItem?

  init(
    storage: LocalModelRuntimeStorage = LocalModelRuntimeStorage(),
    backend: LocalModelInferenceBackend? = nil
  ) {
    self.storage = storage
    self.followsRegistry = backend == nil
    self.backend = backend ?? LocalModelInferenceBackendRegistry.current()
    LocalModelWhisperResourceArbiter.shared.register(localModelRuntime: self)
  }

  var available: Bool {
    lock.lock()
    refreshBackendIfNeededLocked()
    let value = backend.isAvailable
    lock.unlock()
    return value
  }

  func snapshot() -> LocalModelInferenceRuntimeSnapshot {
    lock.lock()
    refreshBackendIfNeededLocked()
    defer { lock.unlock() }
    let selectedProfile = LocalModelRuntimeSettings.selectedProfile()
    let backgroundReady = backend.isAvailable &&
      LocalModelRuntimeSettings.isProfileEnabled(selectedProfile) &&
      Self.backgroundSafe(selectedProfile) &&
      storage.inspect(selectedProfile).installed &&
      canRunBackgroundLocked()
    return LocalModelInferenceRuntimeSnapshot(
      backend: backend.backendName,
      available: backend.isAvailable,
      backgroundReady: backgroundReady,
      loadedProfileId: loadedProfile,
      loadedContextTokens: loadedContextTokens,
      executionIsolation: LocalModelInferenceExecutionPolicy.executionIsolation,
      backendScope: LocalModelInferenceExecutionPolicy.backendScope
    )
  }

  func ready(profile: LocalModelRuntimeProfile? = nil) -> Bool {
    guard !LocalModelWhisperResourceArbiter.shared.asrHasPriority() else { return false }
    lock.lock()
    refreshBackendIfNeededLocked()
    let backendAvailable = backend.isAvailable
    lock.unlock()
    guard backendAvailable else { return false }
    let selected = profile ?? LocalModelRuntimeSettings.selectedProfile()
    guard selected.supportsIOSRuntime else { return false }
    return LocalModelRuntimeSettings.isProfileEnabled(selected) && storage.inspect(selected).installed
  }

  private func generate(
    profile: LocalModelRuntimeProfile,
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int = 768,
    temperature: Double = 0.3,
    thinkingMode: LocalModelThinkingMode = .automatic,
    workClass: LocalModelWorkClass = .interactive
  ) throws -> LocalModelInferenceResult {
    guard profile.supportsIOSRuntime else {
      throw LocalModelInferenceError.modelNotReady
    }
    guard LocalModelRuntimeSettings.isProfileEnabled(profile) else {
      throw LocalModelInferenceError.modelDisabled
    }
    if workClass == .background && !Self.backgroundSafe(profile) {
      throw LocalModelBackgroundDeferredError(reason: "This local model backend is reserved for interactive inference")
    }
    guard !LocalModelWhisperResourceArbiter.shared.asrHasPriority() else {
      throw LocalModelASRPriorityError()
    }
    if workClass == .interactive {
      beginInteractiveWork()
      defer { endInteractiveWork() }
    }
    guard !LocalModelWhisperResourceArbiter.shared.asrHasPriority() else {
      throw LocalModelASRPriorityError()
    }
    lock.lock()
    defer { lock.unlock() }
    refreshBackendIfNeededLocked()

    if workClass == .background && !canRunBackgroundLocked() {
      throw LocalModelBackgroundDeferredError()
    }

    guard backend.isAvailable else {
      throw LocalModelInferenceError.nativeBackendUnavailable
    }
    let modelURL: URL
    do {
      modelURL = try storage.verifyForNativeLoad(profile)
    } catch {
      throw LocalModelInferenceError.modelNotReady
    }

    let requestedContext = min(
      max(512, LocalModelRuntimeSettings.contextTokens()),
      profile.maximumContextTokens
    )
    let estimate: LocalModelRuntimeEstimate
    do {
      estimate = try LocalModelRuntimePreflight.beforeLaunch(
        profile: profile,
        modelFileURL: modelURL,
        contextTokens: requestedContext
      )
    } catch {
      throw LocalModelInferenceError.modelLoadFailed(error.localizedDescription)
    }

    if loadedProfile != profile.id || loadedContextTokens != estimate.recommendedContextTokens {
      backend.unload()
      do {
        try backend.loadModel(
          at: modelURL,
          contextTokens: estimate.recommendedContextTokens,
          threads: estimate.recommendedThreads
        )
      } catch {
        loadedProfile = ""
        loadedContextTokens = 0
        throw LocalModelInferenceError.modelLoadFailed(error.localizedDescription)
      }
      loadedProfile = profile.id
      loadedContextTokens = estimate.recommendedContextTokens
    }

    let startedAt = Date()
    let prompt = Self.prepareUserPrompt(
      profile: profile,
      userPrompt: userPrompt,
      thinkingMode: thinkingMode
    )
    let response: String
    do {
      response = try backend.generate(
        systemPrompt: systemPrompt,
        userPrompt: prompt,
        maximumTokens: max(1, maximumTokens),
        temperature: max(0, temperature)
      ).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw LocalModelInferenceError.generationFailed(error.localizedDescription)
    }
    guard !response.isEmpty else { throw LocalModelInferenceError.emptyResponse }

    return LocalModelInferenceResult(
      text: response,
      profileId: profile.id,
      backend: backend.backendName,
      smeAvailable: backend.exposesSme,
      elapsedMillis: max(0, Int64(Date().timeIntervalSince(startedAt) * 1_000))
    )
  }

  func generateAsync(
    profile: LocalModelRuntimeProfile,
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int = 768,
    temperature: Double = 0.3,
    thinkingMode: LocalModelThinkingMode = .automatic,
    workClass: LocalModelWorkClass = .interactive
  ) async throws -> LocalModelInferenceResult {
    try await withCheckedThrowingContinuation { continuation in
      inferenceQueue.async { [self] in
        do {
          continuation.resume(returning: try generate(
            profile: profile,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maximumTokens: maximumTokens,
            temperature: temperature,
            thinkingMode: thinkingMode,
            workClass: workClass
          ))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func releaseForAsr() {
    releaseForResourcePressure()
  }

  func releaseForResourcePressure() {
    lock.lock()
    idleReleaseWorkItem?.cancel()
    idleReleaseWorkItem = nil
    refreshBackendIfNeededLocked()
    backend.unload()
    loadedProfile = ""
    loadedContextTokens = 0
    lock.unlock()
  }

  func unloadIfSelected(profileId: String) {
    lock.lock()
    refreshBackendIfNeededLocked()
    guard loadedProfile == profileId else {
      lock.unlock()
      return
    }
    backend.unload()
    loadedProfile = ""
    loadedContextTokens = 0
    lock.unlock()
  }

  func loadedProfileId() -> String {
    lock.lock()
    defer { lock.unlock() }
    return loadedProfile
  }

  func readyForBackground(profile: LocalModelRuntimeProfile? = nil) -> Bool {
    let resolvedProfile = profile ?? LocalModelRuntimeSettings.selectedProfile()
    return Self.backgroundSafe(resolvedProfile) && ready(profile: resolvedProfile)
  }

  func canRunBackground() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return canRunBackgroundLocked()
  }

  private func refreshBackendIfNeededLocked() {
    guard followsRegistry else { return }
    let registered = LocalModelInferenceBackendRegistry.current()
    guard ObjectIdentifier(backend) != ObjectIdentifier(registered) else { return }
    backend.unload()
    backend = registered
    loadedProfile = ""
    loadedContextTokens = 0
  }

  private func beginInteractiveWork() {
    lock.lock()
    idleReleaseWorkItem?.cancel()
    idleReleaseWorkItem = nil
    foregroundWaiters += 1
    lock.unlock()
  }

  private func endInteractiveWork() {
    lock.lock()
    foregroundWaiters = max(0, foregroundWaiters - 1)
    foregroundLeaseUntilUptime = ProcessInfo.processInfo.systemUptime + Self.foregroundIdleGraceSeconds
    let shouldScheduleRelease = foregroundWaiters == 0
    let releaseWorkItem = shouldScheduleRelease
      ? DispatchWorkItem { [weak self] in self?.releaseIfIdle() }
      : nil
    idleReleaseWorkItem = releaseWorkItem
    lock.unlock()
    if let releaseWorkItem {
      idleReleaseQueue.asyncAfter(
        deadline: .now() + Self.foregroundIdleGraceSeconds,
        execute: releaseWorkItem
      )
    }
  }

  private func releaseIfIdle() {
    lock.lock()
    defer { lock.unlock() }
    guard foregroundWaiters == 0,
          ProcessInfo.processInfo.systemUptime >= foregroundLeaseUntilUptime else {
      return
    }
    refreshBackendIfNeededLocked()
    backend.unload()
    loadedProfile = ""
    loadedContextTokens = 0
    idleReleaseWorkItem = nil
  }

  private func canRunBackgroundLocked() -> Bool {
    foregroundWaiters == 0 && ProcessInfo.processInfo.systemUptime >= foregroundLeaseUntilUptime
  }

  private static func backgroundSafe(_ profile: LocalModelRuntimeProfile) -> Bool {
    let identity = "\(profile.id) \(profile.repositoryId) \(profile.quantizationLabel)".lowercased()
    return !identity.contains("qairt") && !identity.contains("geniex")
  }

  static func prepareUserPrompt(
    profile: LocalModelRuntimeProfile,
    userPrompt: String,
    thinkingMode: LocalModelThinkingMode = .automatic
  ) -> String {
    guard profile.isQwenFamily else { return userPrompt }
    if thinkingMode == .automatic {
      guard profile.defaultNoThink, !thinkingCommand.matches(userPrompt) else { return userPrompt }
      return "\(userPrompt)\n/no_think"
    }
    let withoutCommand = thinkingCommand.stringByReplacingMatches(
      in: userPrompt,
      range: NSRange(userPrompt.startIndex..., in: userPrompt),
      withTemplate: " "
    )
      .replacingOccurrences(of: #"[ \t]+(?=\r?$)"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let command = thinkingMode == .think ? "/think" : "/no_think"
    return withoutCommand.isEmpty ? command : "\(withoutCommand)\n\(command)"
  }

  private static let thinkingCommand = try! NSRegularExpression(
    pattern: "(?m)(^|\\s)/(?:no_)?think(?=\\s|$)"
  )

  private static let backgroundStartupGraceSeconds: TimeInterval = 2.0
  private static let foregroundIdleGraceSeconds: TimeInterval = 1.5

}

private extension NSRegularExpression {
  func matches(_ string: String) -> Bool {
    firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
  }
}

private extension LocalModelRuntimeProfile {
  var isQwenFamily: Bool {
    id.lowercased().hasPrefix("qwen") ||
      repositoryId.split(separator: "/").last?.lowercased().hasPrefix("qwen") == true
  }
}
