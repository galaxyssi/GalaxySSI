import Foundation

enum VoiceASRProviderRouteKind: String, Codable, Equatable {
  case localWhisper = "LOCAL_WHISPER"
  case onlineRealtime = "ONLINE_REALTIME"
  case remoteWhisper = "REMOTE_WHISPER"
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
    switch requestedProvider {
    case .automatic:
      return false
    case .localWhisperCpp:
      return kind != .localWhisper
    case .onlineRealtime:
      return kind != .onlineRealtime
    case .remoteWhisper:
      return kind != .remoteWhisper
    }
  }
}

enum VoiceASRProviderRoutingPolicy {
  static func route(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    onlineRealtimeAvailable: Bool = false,
    remoteWhisperAvailable: Bool = false
  ) -> VoiceASRProviderRoute {
    let normalized = settings.normalized
    let whisper = capabilities[.whisperCpp]
    let prefersLocalWhisper = normalized.asrProvider == .localWhisperCpp ||
      (normalized.asrProvider == .automatic && normalized.localAsrAlwaysPreferred)
    if prefersLocalWhisper, whisper.ready {
      return VoiceASRProviderRoute(
        kind: .localWhisper,
        capability: whisper,
        channel: .localWhisperASR,
        provider: whisperProvider(whisper),
        requestedProvider: normalized.asrProvider
      )
    }

    let system = capabilities[.androidSystemASR]
    let cloud = capabilities[.cloudASR]
    let canSelectOnline = normalized.asrProvider == .automatic ||
      normalized.asrProvider == .onlineRealtime
    if canSelectOnline,
       onlineConsentGranted(settings: normalized),
       VoiceFeatureFlags.isOnlineRealtimeASREnabled(),
       onlineRealtimeAvailable,
       cloud.ready {
      return VoiceASRProviderRoute(
        kind: .onlineRealtime,
        capability: cloud,
        channel: .onlineRealtimeASR,
        provider: "SignalASI Realtime ASR",
        requestedProvider: normalized.asrProvider
      )
    }
    let canFallbackToLocal = normalized.asrProvider == .automatic ||
      normalized.asrProvider == .onlineRealtime
    if canFallbackToLocal, whisper.ready {
      return VoiceASRProviderRoute(
        kind: .localWhisper,
        capability: whisper,
        channel: .localWhisperASR,
        provider: whisperProvider(whisper),
        requestedProvider: normalized.asrProvider,
        fallbackReason: normalized.asrProvider == .onlineRealtime ? .networkRequired : nil
      )
    }
    if normalized.asrProvider == .remoteWhisper,
       normalized.remoteWhisperAllowed,
       VoiceFeatureFlags.isRemoteWhisperNodeEnabled(),
       remoteWhisperAvailable,
       system.ready {
      return VoiceASRProviderRoute(
        kind: .remoteWhisper,
        capability: system,
        channel: .remoteWhisperASR,
        provider: "Remote Whisper / paired Desktop",
        requestedProvider: normalized.asrProvider
      )
    }

    return VoiceASRProviderRoute(
      kind: .iosSpeechFallback,
      capability: system,
      channel: .androidSystemASR,
      provider: iosSpeechProvider(localeIdentifier: normalized.preferredLocaleIdentifier),
      requestedProvider: normalized.asrProvider,
      fallbackReason: normalized.asrProvider == .localWhisperCpp
        ? whisper.reason
        : normalized.asrProvider == .remoteWhisper || normalized.asrProvider == .onlineRealtime
          ? .networkRequired
          : nil
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
    onlineRealtimeAvailable: Bool = false,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> Bool {
    pcmCaptureEnabled && localRuntimeEnabled && adaptivePartialEnabled &&
      route(
        settings: settings,
        capabilities: capabilities,
        onlineRealtimeAvailable: onlineRealtimeAvailable
      ).kind == .localWhisper
  }

  static func shouldUseRemoteWhisper(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    remoteWhisperAvailable: Bool
  ) -> Bool {
    route(
      settings: settings,
      capabilities: capabilities,
      remoteWhisperAvailable: remoteWhisperAvailable
    ).kind == .remoteWhisper
  }

  static func shouldUseOnlineRealtime(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    onlineRealtimeAvailable: Bool
  ) -> Bool {
    route(
      settings: settings,
      capabilities: capabilities,
      onlineRealtimeAvailable: onlineRealtimeAvailable
    ).kind == .onlineRealtime
  }

  static func onlineAllowed(settings: VoiceSettings, network: AgentMediaNetworkProbe) -> Bool {
    let normalized = settings.normalized
    guard onlineConsentGranted(settings: normalized),
          network.networkPresent,
          network.internetCapable,
          network.validated else {
      return false
    }
    if network.cellular {
      return !normalized.onlineAsrWifiOnly && normalized.onlineAsrMobileAllowed
    }
    if normalized.onlineAsrWifiOnly {
      return network.transports.contains { $0.caseInsensitiveCompare("wifi") == .orderedSame }
    }
    return true
  }

  private static func localCaptureCanBeAuthorized(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot,
    pcmCaptureEnabled: Bool,
    localRuntimeEnabled: Bool,
    adaptivePartialEnabled: Bool
  ) -> Bool {
    let provider = settings.normalized.asrProvider
    if provider == .automatic,
       onlineConsentGranted(settings: settings.normalized),
       !settings.normalized.localAsrAlwaysPreferred {
      return false
    }
    guard (provider == .automatic || provider == .localWhisperCpp),
          pcmCaptureEnabled,
          localRuntimeEnabled,
          adaptivePartialEnabled else {
      return false
    }
    let localCapability = capabilities[.whisperCpp]
    return localCapability.state == .ready || localCapability.state == .needsPermission
  }

  private static func onlineConsentGranted(settings: VoiceSettings) -> Bool {
    settings.onlineAsrAllowed &&
      settings.onlineAsrAudioUploadAllowed &&
      !settings.localAsrAlwaysPreferred
  }
}
