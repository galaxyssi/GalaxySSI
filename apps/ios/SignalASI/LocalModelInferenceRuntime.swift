import Foundation

final class LocalModelInferenceRuntime {
  static let shared = LocalModelInferenceRuntime()

  private let lock = NSLock()
  private let storage: LocalModelRuntimeStorage
  private let followsRegistry: Bool
  private var backend: LocalModelInferenceBackend
  private var loadedProfile = ""
  private var loadedContextTokens = 0

  init(
    storage: LocalModelRuntimeStorage = LocalModelRuntimeStorage(),
    backend: LocalModelInferenceBackend? = nil
  ) {
    self.storage = storage
    self.followsRegistry = backend == nil
    self.backend = backend ?? LocalModelInferenceBackendRegistry.current()
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
    return LocalModelInferenceRuntimeSnapshot(
      backend: backend.backendName,
      available: backend.isAvailable,
      loadedProfileId: loadedProfile,
      loadedContextTokens: loadedContextTokens
    )
  }

  func ready(profile: LocalModelRuntimeProfile? = nil) -> Bool {
    lock.lock()
    refreshBackendIfNeededLocked()
    let backendAvailable = backend.isAvailable
    lock.unlock()
    guard backendAvailable else { return false }
    let selected = profile ?? LocalModelRuntimeSettings.selectedProfile()
    return LocalModelRuntimeSettings.isProfileEnabled(selected) && storage.inspect(selected).installed
  }

  func generate(
    profile: LocalModelRuntimeProfile,
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int = 768,
    temperature: Double = 0.3
  ) throws -> LocalModelInferenceResult {
    guard LocalModelRuntimeSettings.isProfileEnabled(profile) else {
      throw LocalModelInferenceError.modelDisabled
    }
    lock.lock()
    defer { lock.unlock() }
    refreshBackendIfNeededLocked()

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
    let prompt = Self.prepareUserPrompt(profile: profile, userPrompt: userPrompt)
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
    temperature: Double = 0.3
  ) async throws -> LocalModelInferenceResult {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        do {
          continuation.resume(returning: try generate(
            profile: profile,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maximumTokens: maximumTokens,
            temperature: temperature
          ))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func releaseForAsr() {
    lock.lock()
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

  private func refreshBackendIfNeededLocked() {
    guard followsRegistry else { return }
    let registered = LocalModelInferenceBackendRegistry.current()
    guard ObjectIdentifier(backend) != ObjectIdentifier(registered) else { return }
    backend.unload()
    backend = registered
    loadedProfile = ""
    loadedContextTokens = 0
  }

  private static func prepareUserPrompt(profile: LocalModelRuntimeProfile, userPrompt: String) -> String {
    guard profile.defaultNoThink, !noThinkCommand.matches(userPrompt) else { return userPrompt }
    return "\(userPrompt)\n/no_think"
  }

  private static let noThinkCommand = try! NSRegularExpression(
    pattern: "(?m)(^|\\s)/no_think(?=\\s|$)"
  )
}

private extension NSRegularExpression {
  func matches(_ string: String) -> Bool {
    firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
  }
}
