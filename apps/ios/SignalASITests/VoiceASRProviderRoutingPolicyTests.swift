import XCTest
@testable import SignalASI

final class VoiceASRProviderRoutingPolicyTests: XCTestCase {
  func testRoutesToLocalWhisperWhenRequestedProviderIsReady() {
    let route = VoiceASRProviderRoutingPolicy.route(
      settings: settings(locale: "en-US"),
      capabilities: VoiceProviderCapabilitySnapshot(
        capabilities: [
          capability(.whisperCpp, .ready, .ready, metadata: ["model_name": "Base"]),
          capability(.androidSystemASR, .ready, .ready),
        ],
        checkedAtMillis: 1_000
      )
    )

    XCTAssertEqual(route.kind, .localWhisper)
    XCTAssertEqual(route.capability.id, .whisperCpp)
    XCTAssertEqual(route.channel, .localWhisperASR)
    XCTAssertEqual(route.provider, "Local Whisper / Base")
    XCTAssertFalse(route.usesFallback)
    XCTAssertNil(route.fallbackReason)
  }

  func testAutomaticRouteUsesReadyLocalWhisper() {
    let route = VoiceASRProviderRoutingPolicy.route(
      settings: settings(locale: "en-US", provider: .automatic),
      capabilities: VoiceProviderCapabilitySnapshot(
        capabilities: [
          capability(.whisperCpp, .ready, .ready, metadata: ["model_name": "Tiny"]),
          capability(.androidSystemASR, .ready, .ready),
        ],
        checkedAtMillis: 1_000
      )
    )

    XCTAssertEqual(route.kind, .localWhisper)
    XCTAssertEqual(route.provider, "Local Whisper / Tiny")
    XCTAssertFalse(route.usesFallback)
  }

  func testAutomaticRouteUsesIOSSpeechWithoutMarkingItAsFallback() {
    let route = VoiceASRProviderRoutingPolicy.route(
      settings: settings(locale: "zh-Hans", provider: .automatic),
      capabilities: VoiceProviderCapabilitySnapshot(
        capabilities: [
          capability(.whisperCpp, .needsDownload, .whisperModelMissing),
          capability(.androidSystemASR, .ready, .ready),
        ],
        checkedAtMillis: 1_000
      )
    )

    XCTAssertEqual(route.kind, .iosSpeechFallback)
    XCTAssertEqual(route.provider, "iOS Speech / zh-Hans")
    XCTAssertFalse(route.usesFallback)
    XCTAssertNil(route.fallbackReason)
  }

  func testFallsBackToIOSSpeechWhenWhisperNeedsDownload() {
    let route = VoiceASRProviderRoutingPolicy.route(
      settings: settings(locale: "zh-Hans"),
      capabilities: VoiceProviderCapabilitySnapshot(
        capabilities: [
          capability(.whisperCpp, .needsDownload, .whisperModelMissing),
          capability(.androidSystemASR, .ready, .ready),
        ],
        checkedAtMillis: 1_000
      )
    )

    XCTAssertEqual(route.kind, .iosSpeechFallback)
    XCTAssertEqual(route.capability.id, .androidSystemASR)
    XCTAssertEqual(route.channel, .androidSystemASR)
    XCTAssertEqual(route.provider, "iOS Speech / zh-Hans")
    XCTAssertTrue(route.usesFallback)
    XCTAssertEqual(route.fallbackReason, .whisperModelMissing)
  }

  func testFallbackCarriesSystemCapabilityWhenBothRoutesAreBlocked() {
    let route = VoiceASRProviderRoutingPolicy.route(
      settings: settings(locale: "en-US"),
      capabilities: VoiceProviderCapabilitySnapshot(
        capabilities: [
          capability(.whisperCpp, .unavailable, .whisperRuntimeMissing),
          capability(.androidSystemASR, .unavailable, .systemRecognizerMissing),
        ],
        checkedAtMillis: 1_000
      )
    )

    XCTAssertEqual(route.kind, .iosSpeechFallback)
    XCTAssertEqual(route.capability.id, .androidSystemASR)
    XCTAssertEqual(route.capability.state, .unavailable)
    XCTAssertEqual(route.fallbackReason, .whisperRuntimeMissing)
  }

  func testLocalWhisperRequestsOnlyMicrophoneWhenModelIsReady() {
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.whisperCpp, .ready, .ready),
        capability(.androidSystemASR, .ready, .ready),
      ],
      checkedAtMillis: 1_000
    )

    XCTAssertFalse(
      VoiceASRProviderRoutingPolicy.requiresSystemSpeechAuthorization(
        settings: settings(locale: "zh-Hans"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      )
    )
    XCTAssertTrue(
      VoiceASRProviderRoutingPolicy.shouldUseLocalWhisper(
        settings: settings(locale: "zh-Hans"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      )
    )
    XCTAssertEqual(
      VoiceASRProviderRoutingPolicy.authorizationRequirement(
        settings: settings(locale: "zh-Hans"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      ),
      .microphoneOnly
    )
  }

  func testLocalWhisperWaitingForMicrophoneDoesNotRequestSpeechAuthorization() {
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.whisperCpp, .needsPermission, .microphonePermissionRequired),
        capability(.androidSystemASR, .needsPermission, .microphonePermissionRequired),
      ],
      checkedAtMillis: 1_000
    )

    XCTAssertFalse(
      VoiceASRProviderRoutingPolicy.requiresSystemSpeechAuthorization(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      )
    )
  }

  func testLocalWhisperFallsBackToSystemAuthorizationWhenModelIsMissing() {
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.whisperCpp, .needsDownload, .whisperModelMissing),
        capability(.androidSystemASR, .ready, .ready),
      ],
      checkedAtMillis: 1_000
    )

    XCTAssertTrue(
      VoiceASRProviderRoutingPolicy.requiresSystemSpeechAuthorization(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      )
    )
    XCTAssertFalse(
      VoiceASRProviderRoutingPolicy.shouldUseLocalWhisper(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      )
    )
    XCTAssertEqual(
      VoiceASRProviderRoutingPolicy.authorizationRequirement(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: true,
        adaptivePartialEnabled: true
      ),
      .microphoneAndSystemSpeech
    )
  }

  func testDisabledLocalPipelineUsesSystemSpeechAuthorization() {
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.whisperCpp, .ready, .ready),
        capability(.androidSystemASR, .ready, .ready),
      ],
      checkedAtMillis: 1_000
    )

    XCTAssertTrue(
      VoiceASRProviderRoutingPolicy.requiresSystemSpeechAuthorization(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: false,
        adaptivePartialEnabled: true
      )
    )
    XCTAssertFalse(
      VoiceASRProviderRoutingPolicy.shouldUseLocalWhisper(
        settings: settings(locale: "en-US"),
        capabilities: capabilities,
        pcmCaptureEnabled: true,
        localRuntimeEnabled: false,
        adaptivePartialEnabled: true
      )
    )
  }

  private func settings(
    locale: String,
    provider: VoiceASRProvider = .localWhisperCpp
  ) -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: locale,
      asrProvider: provider
    )
  }

  private func capability(
    _ id: VoiceProviderCapabilityId,
    _ state: VoiceProviderCapabilityState,
    _ reason: VoiceProviderCapabilityReason,
    metadata: [String: String] = [:]
  ) -> VoiceProviderCapability {
    VoiceProviderCapability(id: id, state: state, reason: reason, metadata: metadata)
  }
}
