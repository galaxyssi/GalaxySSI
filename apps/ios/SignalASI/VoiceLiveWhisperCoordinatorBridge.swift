import Foundation

let voiceLocalWhisperProviderId = "whisper.cpp"

typealias VoiceLiveWhisperTranscriptEmitter = (
  _ text: String,
  _ provider: String,
  _ modelProfileId: String
) -> VoiceInteractionTransition

struct VoiceLiveWhisperCoordinatorBridge {
  private let provider: String
  private let emitPartial: VoiceLiveWhisperTranscriptEmitter
  private let emitStable: VoiceLiveWhisperTranscriptEmitter
  private let emitFinal: VoiceLiveWhisperTranscriptEmitter

  init(
    provider: String = voiceLocalWhisperProviderId,
    emitPartial: @escaping VoiceLiveWhisperTranscriptEmitter,
    emitStable: @escaping VoiceLiveWhisperTranscriptEmitter,
    emitFinal: @escaping VoiceLiveWhisperTranscriptEmitter
  ) {
    self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(voiceLocalWhisperProviderId)
    self.emitPartial = emitPartial
    self.emitStable = emitStable
    self.emitFinal = emitFinal
  }

  init(
    coordinatorBridge: VoiceSpeechCaptureCoordinatorBridge,
    provider: String = voiceLocalWhisperProviderId
  ) {
    self.init(
      provider: provider,
      emitPartial: { text, provider, modelProfileId in
        coordinatorBridge.transcriptPartial(text, provider: provider, modelProfileId: modelProfileId)
      },
      emitStable: { text, provider, modelProfileId in
        coordinatorBridge.transcriptStable(text, provider: provider, modelProfileId: modelProfileId)
      },
      emitFinal: { text, provider, modelProfileId in
        coordinatorBridge.finishWithBestTranscript(text, provider: provider, modelProfileId: modelProfileId)
      }
    )
  }

  @discardableResult
  func apply(_ update: VoiceLiveWhisperTranscriptUpdate) -> [VoiceInteractionTransition] {
    let modelProfileId = update.modelProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    let transcript = update.transcript
    if transcript.final {
      return accepted(
        emitFinal(
          transcript.displayText,
          provider,
          modelProfileId
        )
      )
    }

    var transitions: [VoiceInteractionTransition] = []
    appendAccepted(
      emitStable(
        transcript.stableText,
        provider,
        modelProfileId
      ),
      to: &transitions
    )
    appendAccepted(
      emitPartial(
        transcript.displayText,
        provider,
        modelProfileId
      ),
      to: &transitions
    )
    return transitions
  }

  private func accepted(_ transition: VoiceInteractionTransition) -> [VoiceInteractionTransition] {
    transition.accepted ? [transition] : []
  }

  private func appendAccepted(
    _ transition: VoiceInteractionTransition,
    to transitions: inout [VoiceInteractionTransition]
  ) {
    guard transition.accepted else { return }
    transitions.append(transition)
  }
}
