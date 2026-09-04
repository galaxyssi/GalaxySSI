import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

enum VoiceProviderCapabilityId: String, Codable, CaseIterable, Identifiable {
  case openWakeWord = "OPEN_WAKE_WORD"
  case whisperCpp = "WHISPER_CPP"
  case androidSystemASR = "ANDROID_SYSTEM_ASR"
  case androidOfflineASR = "ANDROID_OFFLINE_ASR"
  case cloudASR = "CLOUD_ASR"
  case androidSystemTTS = "ANDROID_SYSTEM_TTS"
  case microsoftEdgeTTS = "MICROSOFT_EDGE_TTS"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceProviderCapabilityId? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized }
  }
}

enum VoiceProviderCapabilityState: String, Codable, CaseIterable, Identifiable {
  case ready = "READY"
  case checking = "CHECKING"
  case needsPermission = "NEEDS_PERMISSION"
  case needsDownload = "NEEDS_DOWNLOAD"
  case needsNetwork = "NEEDS_NETWORK"
  case unavailable = "UNAVAILABLE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceProviderCapabilityState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized } ?? .unavailable
  }
}

enum VoiceProviderCapabilityReason: String, Codable, CaseIterable, Identifiable {
  case ready = "READY"
  case checking = "CHECKING"
  case microphoneMissing = "MICROPHONE_MISSING"
  case microphonePermissionRequired = "MICROPHONE_PERMISSION_REQUIRED"
  case whisperRuntimeMissing = "WHISPER_RUNTIME_MISSING"
  case whisperModelMissing = "WHISPER_MODEL_MISSING"
  case systemRecognizerMissing = "SYSTEM_RECOGNIZER_MISSING"
  case offlineRecognizerMissing = "OFFLINE_RECOGNIZER_MISSING"
  case networkRequired = "NETWORK_REQUIRED"
  case ttsEngineMissing = "TTS_ENGINE_MISSING"
  case ttsLanguageUnsupported = "TTS_LANGUAGE_UNSUPPORTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceProviderCapabilityReason {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return allCases.first { $0.rawValue == normalized } ?? .checking
  }
}

struct VoiceProviderCapability: Codable, Equatable, Identifiable {
  var id: VoiceProviderCapabilityId
  var state: VoiceProviderCapabilityState
  var reason: VoiceProviderCapabilityReason
  var metadata: [String: String]

  var ready: Bool { state == .ready }

  init(
    id: VoiceProviderCapabilityId,
    state: VoiceProviderCapabilityState,
    reason: VoiceProviderCapabilityReason,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.state = state
    self.reason = reason
    self.metadata = metadata.filter { !$0.key.isBlank && !$0.value.isBlank }
  }
}

struct VoiceProviderCapabilitySnapshot: Codable, Equatable {
  var capabilities: [VoiceProviderCapability]
  var checkedAtMillis: Int64

  init(
    capabilities: [VoiceProviderCapability],
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    var byId: [VoiceProviderCapabilityId: VoiceProviderCapability] = [:]
    for capability in capabilities {
      byId[capability.id] = capability
    }
    self.capabilities = VoiceProviderCapabilityId.allCases.map {
      byId[$0] ?? VoiceProviderCapability(id: $0, state: .unavailable, reason: .checking)
    }
    self.checkedAtMillis = max(0, checkedAtMillis)
  }

  subscript(id: VoiceProviderCapabilityId) -> VoiceProviderCapability {
    capabilities.first { $0.id == id } ?? VoiceProviderCapability(id: id, state: .unavailable, reason: .checking)
  }

  var readyIds: [VoiceProviderCapabilityId] {
    capabilities.filter { $0.ready }.map { $0.id }
  }

  enum CodingKeys: String, CodingKey {
    case capabilities
    case checkedAtMillis = "checked_at_millis"
  }
}

struct VoiceDeviceCapabilityProbe: Codable, Equatable {
  var hasMicrophone: Bool
  var microphonePermissionGranted: Bool
  var whisperRuntimeAvailable: Bool
  var whisperModelAvailable: Bool
  var whisperModelId: String
  var whisperModelName: String
  var systemAsrAvailable: Bool
  var offlineAsrAvailable: Bool
  var validatedNetworkAvailable: Bool
  var ttsInitialized: Bool
  var ttsReady: Bool
  var ttsEngineCount: Int
  var ttsLanguageSupported: Bool
  var ttsLanguage: String

  enum CodingKeys: String, CodingKey {
    case hasMicrophone = "has_microphone"
    case microphonePermissionGranted = "microphone_permission_granted"
    case whisperRuntimeAvailable = "whisper_runtime_available"
    case whisperModelAvailable = "whisper_model_available"
    case whisperModelId = "whisper_model_id"
    case whisperModelName = "whisper_model_name"
    case systemAsrAvailable = "system_asr_available"
    case offlineAsrAvailable = "offline_asr_available"
    case validatedNetworkAvailable = "validated_network_available"
    case ttsInitialized = "tts_initialized"
    case ttsReady = "tts_ready"
    case ttsEngineCount = "tts_engine_count"
    case ttsLanguageSupported = "tts_language_supported"
    case ttsLanguage = "tts_language"
  }
}

enum VoiceProviderCapabilityPolicy {
  static func evaluate(
    _ probe: VoiceDeviceCapabilityProbe,
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> VoiceProviderCapabilitySnapshot {
    VoiceProviderCapabilitySnapshot(
      capabilities: [
        openWakeWord(probe),
        whisper(probe),
        systemASR(probe),
        offlineASR(probe),
        cloudASR(probe),
        systemTTS(probe),
        cloudTTS(probe),
      ],
      checkedAtMillis: checkedAtMillis
    )
  }

  private static func openWakeWord(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.hasMicrophone {
      return unavailable(.openWakeWord, .microphoneMissing)
    }
    if !probe.microphonePermissionGranted {
      return capability(.openWakeWord, .needsPermission, .microphonePermissionRequired)
    }
    return ready(.openWakeWord, metadata: ["model_name": VoiceSettings.defaultWakeModel])
  }

  private static func whisper(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.hasMicrophone {
      return unavailable(.whisperCpp, .microphoneMissing)
    }
    if !probe.whisperRuntimeAvailable {
      return unavailable(.whisperCpp, .whisperRuntimeMissing)
    }
    if !probe.whisperModelAvailable {
      return capability(.whisperCpp, .needsDownload, .whisperModelMissing, metadata: whisperMetadata(probe))
    }
    if !probe.microphonePermissionGranted {
      return capability(.whisperCpp, .needsPermission, .microphonePermissionRequired, metadata: whisperMetadata(probe))
    }
    return ready(.whisperCpp, metadata: whisperMetadata(probe))
  }

  private static func systemASR(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.hasMicrophone {
      return unavailable(.androidSystemASR, .microphoneMissing)
    }
    if !probe.systemAsrAvailable {
      return unavailable(.androidSystemASR, .systemRecognizerMissing)
    }
    if !probe.microphonePermissionGranted {
      return capability(.androidSystemASR, .needsPermission, .microphonePermissionRequired)
    }
    return ready(.androidSystemASR)
  }

  private static func offlineASR(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.hasMicrophone {
      return unavailable(.androidOfflineASR, .microphoneMissing)
    }
    if !probe.offlineAsrAvailable {
      return unavailable(.androidOfflineASR, .offlineRecognizerMissing)
    }
    if !probe.microphonePermissionGranted {
      return capability(.androidOfflineASR, .needsPermission, .microphonePermissionRequired)
    }
    return ready(.androidOfflineASR)
  }

  private static func cloudASR(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.hasMicrophone {
      return unavailable(.cloudASR, .microphoneMissing)
    }
    if !probe.systemAsrAvailable {
      return unavailable(.cloudASR, .systemRecognizerMissing)
    }
    if !probe.microphonePermissionGranted {
      return capability(.cloudASR, .needsPermission, .microphonePermissionRequired)
    }
    if !probe.validatedNetworkAvailable {
      return capability(.cloudASR, .needsNetwork, .networkRequired)
    }
    return ready(.cloudASR)
  }

  private static func systemTTS(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if !probe.ttsInitialized {
      return capability(.androidSystemTTS, .checking, .checking, metadata: ttsMetadata(probe))
    }
    if !probe.ttsReady || probe.ttsEngineCount <= 0 {
      return unavailable(.androidSystemTTS, .ttsEngineMissing, metadata: ttsMetadata(probe))
    }
    if !probe.ttsLanguageSupported {
      return unavailable(.androidSystemTTS, .ttsLanguageUnsupported, metadata: ttsMetadata(probe))
    }
    return ready(.androidSystemTTS, metadata: ttsMetadata(probe))
  }

  private static func cloudTTS(_ probe: VoiceDeviceCapabilityProbe) -> VoiceProviderCapability {
    if probe.validatedNetworkAvailable {
      return ready(.microsoftEdgeTTS)
    }
    return capability(.microsoftEdgeTTS, .needsNetwork, .networkRequired)
  }

  private static func whisperMetadata(_ probe: VoiceDeviceCapabilityProbe) -> [String: String] {
    [
      "model_id": probe.whisperModelId,
      "model_name": probe.whisperModelName,
    ]
  }

  private static func ttsMetadata(_ probe: VoiceDeviceCapabilityProbe) -> [String: String] {
    [
      "engine_count": String(max(0, probe.ttsEngineCount)),
      "language": probe.ttsLanguage,
    ]
  }

  private static func ready(
    _ id: VoiceProviderCapabilityId,
    metadata: [String: String] = [:]
  ) -> VoiceProviderCapability {
    capability(id, .ready, .ready, metadata: metadata)
  }

  private static func unavailable(
    _ id: VoiceProviderCapabilityId,
    _ reason: VoiceProviderCapabilityReason,
    metadata: [String: String] = [:]
  ) -> VoiceProviderCapability {
    capability(id, .unavailable, reason, metadata: metadata)
  }

  private static func capability(
    _ id: VoiceProviderCapabilityId,
    _ state: VoiceProviderCapabilityState,
    _ reason: VoiceProviderCapabilityReason,
    metadata: [String: String] = [:]
  ) -> VoiceProviderCapability {
    VoiceProviderCapability(id: id, state: state, reason: reason, metadata: metadata)
  }
}

enum VoiceProviderCapabilityDetector {
  static func detect(
    settings: VoiceSettings,
    validatedNetworkAvailable: Bool,
    whisperRuntimeLibraryNames: Set<String> = bundledRuntimeNames(),
    whisperModelManager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    whisperModelAvailable: Bool? = nil,
    ttsInitialized: Bool = true,
    checkedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> VoiceProviderCapabilitySnapshot {
    let whisperModel = VoiceWhisperModelCatalog.model(settings.asrModelId)
    return VoiceProviderCapabilityPolicy.evaluate(
      probe(
        settings: settings,
        validatedNetworkAvailable: validatedNetworkAvailable,
        whisperRuntimeLibraryNames: whisperRuntimeLibraryNames,
        whisperModelAvailable: whisperModelAvailable ?? whisperModelManager.isAvailable(whisperModel),
        ttsInitialized: ttsInitialized
      ),
      checkedAtMillis: checkedAtMillis
    )
  }

  static func probe(
    settings: VoiceSettings,
    validatedNetworkAvailable: Bool,
    whisperRuntimeLibraryNames: Set<String>,
    whisperModelAvailable: Bool,
    ttsInitialized: Bool = true,
    hasMicrophone: Bool = microphoneAvailable(),
    microphonePermissionGranted: Bool = microphonePermissionGranted(),
    systemAsrAvailable: Bool? = nil,
    offlineAsrAvailable: Bool? = nil,
    ttsReady: Bool? = nil,
    ttsEngineCount: Int? = nil,
    ttsLanguageSupported: Bool? = nil
  ) -> VoiceDeviceCapabilityProbe {
    let locale = normalizedLocale(settings.preferredLocaleIdentifier)
    let whisperModel = VoiceWhisperModelCatalog.model(settings.asrModelId)
    let resolvedTtsEngineCount = ttsEngineCount ?? Self.ttsEngineCount()
    return VoiceDeviceCapabilityProbe(
      hasMicrophone: hasMicrophone,
      microphonePermissionGranted: microphonePermissionGranted,
      whisperRuntimeAvailable: whisperRuntimeAvailable(whisperRuntimeLibraryNames),
      whisperModelAvailable: whisperModelAvailable,
      whisperModelId: whisperModel.id,
      whisperModelName: whisperModel.displayName,
      systemAsrAvailable: systemAsrAvailable ?? speechRecognizerAvailable(localeIdentifier: locale),
      offlineAsrAvailable: offlineAsrAvailable ?? offlineSpeechRecognizerAvailable(localeIdentifier: locale),
      validatedNetworkAvailable: validatedNetworkAvailable,
      ttsInitialized: ttsInitialized,
      ttsReady: ttsReady ?? (resolvedTtsEngineCount > 0),
      ttsEngineCount: resolvedTtsEngineCount,
      ttsLanguageSupported: ttsLanguageSupported ?? Self.ttsLanguageSupported(localeIdentifier: locale),
      ttsLanguage: locale
    )
  }

  static func whisperRuntimeAvailable(_ runtimeLibraryNames: Set<String>) -> Bool {
    #if GALAXYSSI_NATIVE_WHISPER
    return true
    #else
    let normalized = runtimeLibraryNames.map { $0.lowercased() }
    return normalized.contains { name in
      whisperRuntimeSignals.contains { signal in name.contains(signal) }
    }
    #endif
  }

  static func bundledRuntimeNames(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> Set<String> {
    var names = Set<String>()
    let roots = [
      bundle.executableURL,
      bundle.privateFrameworksURL,
      bundle.builtInPlugInsURL,
      bundle.resourceURL,
    ].compactMap { $0 }
    for root in roots {
      collectNames(root, fileManager: fileManager, into: &names)
    }
    return names
  }

  private static func collectNames(_ url: URL, fileManager: FileManager, into names: inout Set<String>) {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
    names.insert(url.lastPathComponent.lowercased())
    guard isDirectory.boolValue else { return }
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return
    }
    for case let entry as URL in enumerator {
      names.insert(entry.lastPathComponent.lowercased())
      if names.count >= maximumRuntimeNameCount {
        break
      }
    }
  }

  private static func normalizedLocale(_ identifier: String) -> String {
    identifier.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Locale.current.identifier)
  }

  private static func microphoneAvailable() -> Bool {
    #if canImport(AVFoundation)
    return AVAudioSession.sharedInstance().isInputAvailable
    #else
    return false
    #endif
  }

  private static func microphonePermissionGranted() -> Bool {
    #if canImport(AVFoundation)
    return AVAudioSession.sharedInstance().recordPermission == .granted
    #else
    return false
    #endif
  }

  private static func speechRecognizerAvailable(localeIdentifier: String) -> Bool {
    #if canImport(Speech)
    return SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) != nil
    #else
    return false
    #endif
  }

  private static func offlineSpeechRecognizerAvailable(localeIdentifier: String) -> Bool {
    #if canImport(Speech)
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
      return false
    }
    return recognizer.supportsOnDeviceRecognition
    #else
    return false
    #endif
  }

  private static func ttsEngineCount() -> Int {
    #if canImport(AVFoundation)
    return AVSpeechSynthesisVoice.speechVoices().count
    #else
    return 0
    #endif
  }

  private static func ttsLanguageSupported(localeIdentifier: String) -> Bool {
    #if canImport(AVFoundation)
    return AVSpeechSynthesisVoice(language: localeIdentifier) != nil
    #else
    return false
    #endif
  }

  private static let whisperRuntimeSignals: Set<String> = [
    "whisper",
    "whisperkit",
    "ggml",
    "whisper_cpp",
  ]
  private static let maximumRuntimeNameCount = 2_000
}
