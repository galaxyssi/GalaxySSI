import Foundation

enum VoiceWakeProvider: String, Codable, CaseIterable, Identifiable {
  case openWakeWord = "openwakeword"
  case androidASR = "android_asr"

  var id: String { rawValue }

  static let defaultValue: VoiceWakeProvider = .openWakeWord

  static func normalized(_ value: String?) -> VoiceWakeProvider {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? defaultValue
  }

  var displayTitle: String {
    switch self {
    case .openWakeWord:
      return "OpenWakeWord"
    case .androidASR:
      return "iOS Speech wake"
    }
  }
}

enum VoiceASRProvider: String, Codable, CaseIterable, Identifiable {
  case automatic = "auto"
  case localWhisperCpp = "local_whisper_cpp"
  case onlineRealtime = "online_realtime"
  case remoteWhisper = "remote_whisper"

  var id: String { rawValue }

  static let defaultValue: VoiceASRProvider = .automatic

  static func normalized(_ value: String?) -> VoiceASRProvider {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? defaultValue
  }

  var displayTitle: String {
    switch self {
    case .automatic:
      return "Automatic"
    case .localWhisperCpp:
      return "On-device whisper.cpp"
    case .onlineRealtime:
      return "Online realtime ASR"
    case .remoteWhisper:
      return "Remote Whisper"
    }
  }
}

enum VoiceRecognitionPreference: String, Codable, CaseIterable, Identifiable {
  case automatic = "AUTO"
  case onlineFast = "ONLINE_FAST"
  case localPrivate = "LOCAL_PRIVATE"
  case localHighAccuracy = "LOCAL_HIGH_ACCURACY"
  case remoteNode = "REMOTE_NODE"

  var id: String { rawValue }

  static func normalized(_ value: String?) -> VoiceRecognitionPreference {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .automatic
  }

  static func migrated(
    provider: VoiceASRProvider,
    runtimeMode: VoiceWhisperUserVoiceMode
  ) -> VoiceRecognitionPreference {
    switch provider {
    case .automatic:
      return .automatic
    case .onlineRealtime:
      return .onlineFast
    case .remoteWhisper:
      return .remoteNode
    case .localWhisperCpp:
      return runtimeMode == .accurate ? .localHighAccuracy : .localPrivate
    }
  }

  var provider: VoiceASRProvider {
    switch self {
    case .automatic:
      return .automatic
    case .onlineFast:
      return .onlineRealtime
    case .localPrivate, .localHighAccuracy:
      return .localWhisperCpp
    case .remoteNode:
      return .remoteWhisper
    }
  }

  var runtimeMode: VoiceWhisperUserVoiceMode {
    switch self {
    case .automatic:
      return .automatic
    case .onlineFast:
      return .fast
    case .localPrivate:
      return .privacy
    case .localHighAccuracy, .remoteNode:
      return .accurate
    }
  }
}

enum VoiceTTSProvider: String, Codable, CaseIterable, Identifiable {
  case system = "android"
  case microsoftEdge = "microsoft_edge"

  var id: String { rawValue }

  static let defaultValue: VoiceTTSProvider = .system

  static func normalized(_ value: String?) -> VoiceTTSProvider {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? defaultValue
  }

  var displayTitle: String {
    switch self {
    case .system:
      return "iOS System TTS"
    case .microsoftEdge:
      return "Microsoft Edge TTS"
    }
  }

  var runtimeChannel: VoiceRuntimeChannel {
    switch self {
    case .system:
      return .androidSystemTTS
    case .microsoftEdge:
      return .microsoftEdgeTTS
    }
  }
}
