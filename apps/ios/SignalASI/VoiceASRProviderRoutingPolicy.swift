import Foundation

enum VoiceASRProviderRouteKind: String, Codable, Equatable {
  case localWhisper = "LOCAL_WHISPER"
  case iosSpeechFallback = "IOS_SPEECH_FALLBACK"
}

enum VoiceASRAuthorizationRequirement: Equatable {
  case microphoneOnly
  case microphoneAndSystemSpeech
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

  /// A selected local model may only be waiting on microphone permission. In that
  /// case, do not request Apple's speech-recognition permission as a prerequisite.
  static func requiresSystemSpeechAuthorization(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> Bool {
    guard localCaptureCanBeAuthorized(
      settings: settings,
      capabilities: capabilities,
      pcmCaptureEnabled: pcmCaptureEnabled,
      localRuntimeEnabled: localRuntimeEnabled,
      adaptivePartialEnabled: adaptivePartialEnabled
    ) else {
      return true
    }
    return false
  }

  static func authorizationRequirement(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> VoiceASRAuthorizationRequirement {
    requiresSystemSpeechAuthorization(
      settings: settings,
      capabilities: capabilities,
      pcmCaptureEnabled: pcmCaptureEnabled,
      localRuntimeEnabled: localRuntimeEnabled,
      adaptivePartialEnabled: adaptivePartialEnabled
    ) ? .microphoneAndSystemSpeech : .microphoneOnly
  }

  static func currentAuthorizationRequirement(settings: VoiceSettings) -> VoiceASRAuthorizationRequirement {
    let normalized = settings.normalized
    return authorizationRequirement(
      settings: normalized,
      capabilities: VoiceProviderCapabilityDetector.detect(
        settings: normalized,
        validatedNetworkAvailable: false
      ),
      pcmCaptureEnabled: VoiceFeatureFlags.isPcmCaptureEnabled(),
      localRuntimeEnabled: VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(),
      adaptivePartialEnabled: VoiceFeatureFlags.isWhisperAdaptivePartialEnabled()
    )
  }

  static func shouldUseLocalWhisper(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> Bool {
    pcmCaptureEnabled && localRuntimeEnabled && adaptivePartialEnabled &&
      route(settings: settings, capabilities: capabilities).kind == .localWhisper
  }

  private static func localCaptureCanBeAuthorized(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> Bool {
    guard settings.normalized.asrProvider == .localWhisperCpp,
          pcmCaptureEnabled,
          localRuntimeEnabled,
          adaptivePartialEnabled else {
      return false
    }
    let localCapability = capabilities[.whisperCpp]
    return localCapability.state == .ready || localCapability.state == .needsPermission
  }
}
