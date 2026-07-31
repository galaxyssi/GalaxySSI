import Foundation

enum VoiceASRProviderRouteKind: String, Codable, Equatable {
  case localWhisper = "LOCAL_WHISPER"
  case iosSpeechFallback = "IOS_SPEECH_FALLBACK"
}

struct VoiceASRProviderRoute: Equatable {
  var kind: VoiceASRProviderRouteKind
  var capability: VoiceProviderCapability
  var channel: VoiceRuntimeChannel
  var provider: String
  var requestedProvider: VoiceASRProvider
  var fallbackReason: VoiceProviderCapabilityReason?

  var usesFallback: Bool {
    kind == .iosSpeechFallback
  }
}

enum VoiceASRProviderRoutingPolicy {
  static func route(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot
  ) -> VoiceASRProviderRoute {
    let normalized = settings.normalized
    let whisper = capabilities[.whisperCpp]
    if normalized.asrProvider == .localWhisperCpp, whisper.ready {
      return VoiceASRProviderRoute(
        kind: .localWhisper,
        capability: whisper,
        channel: .localWhisperASR,
        provider: whisperProvider(whisper),
        requestedProvider: normalized.asrProvider
      )
    }

    let system = capabilities[.androidSystemASR]
    return VoiceASRProviderRoute(
      kind: .iosSpeechFallback,
      capability: system,
      channel: .androidSystemASR,
      provider: iosSpeechProvider(localeIdentifier: normalized.preferredLocaleIdentifier),
      requestedProvider: normalized.asrProvider,
      fallbackReason: whisper.reason
    )
  }

  private static func whisperProvider(_ capability: VoiceProviderCapability) -> String {
    let model = (capability.metadata["model_name"] ?? "").ifBlank("Local Whisper")
    return "Local Whisper / \(model)"
  }

  private static func iosSpeechProvider(localeIdentifier: String) -> String {
    let locale = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Locale.current.identifier)
    return "iOS Speech / \(locale)"
  }
}
