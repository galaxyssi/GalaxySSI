import SwiftUI
import UIKit

struct SignalASIConversationComposer: View {
  @Binding var draft: String
  @Binding var attachments: [SignalASIDraftAttachment]
  @Binding var attachmentError: String
  @Binding var attachmentMenuPresented: Bool
  @Binding var textModeActive: Bool

  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var voiceSettings: VoiceSettings
  var onSend: () -> Void
  var onVoiceTranscript: (SignalASIVoiceTranscriptSubmission) -> Void
  var t: (String, String) -> String

  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @FocusState private var inputFocused: Bool

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private var uiState: SignalASIAgentComposerUiState {
    SignalASIAgentComposerUiPolicy.resolve(
      hasInput: canSend,
      hasPendingPrimaryAction: false,
      textModeActive: textModeActive,
      actionTrayRequested: false
    )
  }

  private var voicePermissionDeniedMessage: String {
    switch VoiceASRProviderRoutingPolicy.currentAuthorizationRequirement(settings: voiceSettings) {
    case .microphoneOnly:
      return t("signalasi.voice.microphone_permission_missing", "Microphone permission is missing.")
    case .microphoneAndSystemSpeech:
      return t("signalasi.voice.permission_missing", "Microphone or speech permission is missing.")
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        AttachmentPreviewStrip(attachments: attachments) { attachment in
          attachments.removeAll { $0.id == attachment.id }
        }
      }
      if !attachmentError.isEmpty {
        Text(attachmentError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !holdToTalk.statusMessage.isEmpty {
        Text(holdToTalk.statusMessage)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if holdToTalk.isPending || holdToTalk.isRecording {
        voiceCaptureSurface
      } else {
        inputRow
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .onReceive(
      NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
    ) { _ in
      guard inputFocused, !holdToTalk.isPending, !holdToTalk.isRecording else { return }
      inputFocused = false
      textModeActive = false
    }
    .onChange(of: inputFocused) { focused in
      if textModeActive != focused {
        textModeActive = focused
      }
      guard focused, !holdToTalk.isRecording else { return }
      holdToTalk.cancelFromView()
    }
    .onChange(of: textModeActive) { active in
      if inputFocused != active {
        inputFocused = active
      }
    }
    .onDisappear { holdToTalk.cancelFromView() }
  }

  private var inputRow: some View {
    HStack(spacing: 4) {
      inputShell
      primaryActionButton
    }
    .frame(minHeight: 72)
  }

  private var inputShell: some View {
    ZStack(alignment: .topLeading) {
      if draft.isEmpty {
        Text(t("signalasi.message.input_hint", "Message or hold to talk..."))
          .font(.system(size: 15))
          .foregroundColor(.signalASITextSecondary)
          .padding(.leading, 12)
          .padding(.top, 16)
          .allowsHitTesting(false)
      }
      TextEditor(text: $draft)
        .font(.system(size: 15))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.sentences)
        .focused($inputFocused)
        .frame(height: 54)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.clear)
        .onSubmit {
          guard canSend else { return }
          inputFocused = false
          onSend()
        }
    }
    .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
    .contentShape(Rectangle())
    .simultaneousGesture(holdToTalkGesture)
    .accessibilityLabel(Text(t("agent_voice_button", "Hold to talk")))
  }

  @ViewBuilder
  private var primaryActionButton: some View {
    if uiState.showPrimaryActionSlot {
      Button {
        inputFocused = false
        if canSend {
          onSend()
        } else {
          attachmentMenuPresented = true
        }
      } label: {
        Image(systemName: uiState.showSendButton ? "arrow.up" : "plus")
          .font(.system(size: 21, weight: .bold))
          .foregroundColor(uiState.showSendButton ? .signalASIAccent : .signalASITextPrimary)
          .frame(width: 54, height: 54)
          .background(
            uiState.showSendButton
              ? Color(red: 0.655, green: 0.906, blue: 0.847)
              : Color.clear
          )
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .frame(minWidth: 54, minHeight: 54)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(
        uiState.showSendButton
          ? t("signalasi.common.send", "Send")
          : t("agent_attachment_add_file", "Add attachment")
      ))
    }
  }

  private var voiceCaptureSurface: some View {
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      Text(holdToTalk.isPending
        ? t("signalasi.voice.preparing_title", "Preparing voice input")
        : holdToTalk.cancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      if holdToTalk.isRecording {
        let stableTranscript = holdToTalk.stableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let unstableTranscript = holdToTalk.unstableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if stableTranscript.isEmpty && unstableTranscript.isEmpty {
          SignalASIChatVoiceWaveform(
            phase: holdToTalk.waveformPhase,
            amplitude: holdToTalk.waveformAmplitude,
            cancelPending: holdToTalk.cancelPending,
            color: .white
          )
          .frame(height: 38)
        } else {
          SignalASIChatVoiceTranscript(
            stableText: stableTranscript,
            unstableText: unstableTranscript,
            cancelPending: holdToTalk.cancelPending
          )
          .frame(maxWidth: .infinity, minHeight: 38)
        }
        Text(holdToTalk.elapsedLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(holdToTalk.cancelPending ? .red : .white)
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, minHeight: 236, alignment: .bottom)
    .background(
      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0),
          .init(
            color: Color.signalASIAgentRecordingLight.opacity(30.0 / 255.0),
            location: 0.16
          ),
          .init(
            color: Color.signalASIAgentRecordingLight.opacity(132.0 / 255.0),
            location: 0.36
          ),
          .init(
            color: Color.signalASIAgentRecordingMid.opacity(224.0 / 255.0),
            location: 0.64
          ),
          .init(color: Color.signalASIAgentRecordingDeep, location: 1.0),
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !textModeActive || holdToTalk.isPending || holdToTalk.isRecording else { return }
        holdToTalk.dragChanged(
          translation: value.translation,
          settings: voiceSettings,
          messages: SignalASIAgentHoldToTalkMessages(
            permissionDenied: voicePermissionDeniedMessage,
            speechDisabled: t("signalasi.voice.speech_disabled", "Speech recognition is turned off."),
            speechUnavailable: t("signalasi.voice.speech_unavailable", "Speech recognition could not start."),
            noSpeech: t("voice_no_speech", "No speech captured."),
            tooShort: t("voice_too_short", "Hold a little longer."),
            cancelled: t("voice_cancelled", "Voice cancelled.")
          ),
          onStart: {},
          onFinish: onVoiceTranscript,
          onCancel: {}
        )
      }
      .onEnded { value in
        guard !textModeActive || holdToTalk.isPending || holdToTalk.isRecording else { return }
        let wasCapturingVoice = holdToTalk.isPending || holdToTalk.isRecording
        holdToTalk.dragEnded(translation: value.translation)
        if !wasCapturingVoice {
          inputFocused = true
        }
      }
  }
}

private struct SignalASIChatVoiceTranscript: View {
  var stableText: String
  var unstableText: String
  var cancelPending: Bool

  var body: some View {
    let separator = Self.separator(stable: stableText, unstable: unstableText)
    (Text(stableText).foregroundColor(cancelPending ? .red : .white) +
      Text(separator + unstableText).foregroundColor(cancelPending ? .red : Self.unstableColor))
      .font(.system(size: 15, weight: .medium))
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
  }

  private static let unstableColor = Color(red: 232.0 / 255.0, green: 1, blue: 233.0 / 255.0)

  private static func separator(stable: String, unstable: String) -> String {
    guard let last = stable.last,
          let first = unstable.first,
          (last.isLetter || last.isNumber),
          (first.isLetter || first.isNumber),
          !isCJK(last),
          !isCJK(first) else {
      return ""
    }
    return " "
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (0x3400...0x9FFF).contains(scalar.value)
    }
  }
}

private struct SignalASIChatVoiceWaveform: View {
  var phase: Double
  var amplitude: Double
  var cancelPending: Bool
  var color: Color = .signalASIAccent

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<18, id: \.self) { index in
        Capsule()
          .fill(cancelPending ? Color.red : color)
          .frame(
            width: 3,
            height: 8 + abs(sin(phase + Double(index) * 0.58)) * (8 + amplitude * 18)
          )
      }
    }
    .accessibilityHidden(true)
  }
}
