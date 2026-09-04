import Foundation

struct LocalModelInferenceResult: Equatable {
  var text: String
  var profileId: String
  var backend: String
  var smeAvailable: Bool
  var elapsedMillis: Int64
}

enum LocalModelThinkingMode: String, Codable, CaseIterable {
  case automatic = "AUTOMATIC"
  case think = "THINK"
  case noThink = "NO_THINK"
}

enum LocalModelWorkClass: String, Codable, CaseIterable {
  case interactive = "INTERACTIVE"
  case background = "BACKGROUND"
}

struct LocalModelBackgroundDeferredError: LocalizedError, Equatable {
  var reason: String = "The private local model is reserved for an interactive request"

  var errorDescription: String? { reason }
}

struct LocalModelASRPriorityError: LocalizedError, Equatable {
  var errorDescription: String? {
    "Local Whisper is being kept ready for instant voice input"
  }
}

struct LocalModelInferenceRuntimeSnapshot: Equatable {
  var backend: String
  var available: Bool
  var backgroundReady: Bool
  var loadedProfileId: String
  var loadedContextTokens: Int
  var executionIsolation: String
  var backendScope: String

  var loaded: Bool { !loadedProfileId.isEmpty }
}

enum LocalModelInferenceExecutionPolicy {
  static let executorLabel = "com.galaxyssi.ios.local-model-native-runtime"
  static let executionIsolation = "in-process-dedicated-serial-executor"
  static let backendScope = "pinned-static-cpu-metal-accelerate"

  static func requiresDedicatedExecutor(_ profile: LocalModelRuntimeProfile) -> Bool {
    profile.supportsIOSRuntime
  }

  static func allowsRegisteredBackend(named name: String) -> Bool {
    let normalized = name.lowercased()
    return !["qnn", "hexagon", "htp", "genie"].contains { normalized.contains($0) }
  }
}

enum LocalModelInferenceError: LocalizedError, Equatable {
  case nativeBackendUnavailable
  case modelDisabled
  case modelNotReady
  case modelLoadFailed(String)
  case generationFailed(String)
  case emptyResponse

  var errorDescription: String? {
    switch self {
    case .nativeBackendUnavailable:
      return "The native local model backend is not bundled in this build"
    case .modelDisabled:
      return "The selected local model is installed but disabled"
    case .modelNotReady:
      return "The selected local model is not installed or failed verification"
    case let .modelLoadFailed(message):
      return message.isEmpty ? "The local model could not be loaded" : message
    case let .generationFailed(message):
      return message.isEmpty ? "The local model could not generate a response" : message
    case .emptyResponse:
      return "The local model returned an empty response"
    }
  }
}

/// The Swift-side contract for the llama.cpp/Metal backend.
///
/// The app deliberately keeps the backend behind this protocol so the iOS target can
/// link a native implementation without putting C++ details into the Swift UI layer.
protocol LocalModelInferenceBackend: AnyObject {
  var isAvailable: Bool { get }
  var backendName: String { get }
  var exposesSme: Bool { get }

  func loadModel(at modelURL: URL, contextTokens: Int, threads: Int) throws
  func generate(
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int,
    temperature: Double
  ) throws -> String
  func unload()
}

final class UnavailableLocalModelInferenceBackend: LocalModelInferenceBackend {
  var isAvailable: Bool { false }
  var backendName: String { "Unavailable" }
  var exposesSme: Bool { false }

  func loadModel(at modelURL: URL, contextTokens: Int, threads: Int) throws {
    throw LocalModelInferenceError.nativeBackendUnavailable
  }

  func generate(
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int,
    temperature: Double
  ) throws -> String {
    throw LocalModelInferenceError.nativeBackendUnavailable
  }

  func unload() {}
}

/// A small registration point for native backends and test doubles.
///
/// Release builds with the native llama flag use the linked backend by default. Metal
/// hardware alone still never implies that GGUF inference is executable.
enum LocalModelInferenceBackendRegistry {
  private static let lock = NSLock()
  private static let unavailableBackend = UnavailableLocalModelInferenceBackend()
  private static var registeredBackend: LocalModelInferenceBackend?

  static func register(_ backend: LocalModelInferenceBackend) {
    lock.lock()
    registeredBackend = backend
    lock.unlock()
  }

  static func clear() {
    lock.lock()
    registeredBackend?.unload()
    registeredBackend = nil
    lock.unlock()
  }

  static func current() -> LocalModelInferenceBackend {
    lock.lock()
    defer { lock.unlock() }
    if let registeredBackend { return registeredBackend }
#if GALAXYSSI_NATIVE_LLAMA
    return GalaxySSILlamaNativeBackend.shared
#else
    return unavailableBackend
#endif
  }
}
