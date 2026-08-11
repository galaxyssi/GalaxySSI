import SwiftUI

struct SignalASIConversationComposer: View {
  @Binding var draft: String
  @Binding var attachments: [SignalASIDraftAttachment]
  @Binding var attachmentError: String
  @Binding var attachmentMenuPresented: Bool

  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var voiceSettings: VoiceSettings
  var onSend: () -> Void
  var onVoiceTranscript: (String) -> Void
  var t: (String, String) -> String

  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @State private var emojiPanelPresented = false

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
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
      if emojiPanelPresented && !holdToTalk.isRecording {
        emojiPanel
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .onDisappear { holdToTalk.cancelFromView() }
  }

  private var inputRow: some View {
    HStack(spacing: 8) {
      Button {
        emojiPanelPresented = false
        attachmentMenuPresented = true
      } label: {
        Image(systemName: "plus")
      }
      .composerIconButton(label: t("agent_attachment_add_file", "Add attachment"))

      TextField(t("signalasi.message.input", "Message"), text: $draft, axis: .vertical)
        .lineLimit(1...4)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.signalASISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
        )

      Button { emojiPanelPresented.toggle() } label: {
        Image(systemName: "face.smiling")
      }
      .composerIconButton(label: t("signalasi.message.emoji", "Emoji"))

      Button {} label: {
        Image(systemName: "mic")
      }
      .composerIconButton(label: t("agent_voice_button", "Hold to talk"))
      .simultaneousGesture(holdToTalkGesture)

      Button(action: onSend) {
        Image(systemName: "arrow.up")
          .foregroundColor(canSend ? .white : .signalASITextSecondary)
          .frame(width: 32, height: 32)
          .background(Circle().fill(canSend ? Color.signalASIAccent : Color.signalASIButtonSoft))
      }
      .disabled(!canSend)
      .accessibilityLabel(Text(t("signalasi.common.send", "Send")))
    }
  }

  private var voiceCaptureSurface: some View {
    VStack(spacing: 8) {
      Text(holdToTalk.isPending
        ? t("signalasi.voice.preparing_title", "Preparing voice input")
        : holdToTalk.cancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      if holdToTalk.isRecording {
        SignalASIChatVoiceWaveform(phase: holdToTalk.waveformPhase, cancelPending: holdToTalk.cancelPending)
          .frame(height: 24)
        Text(holdToTalk.transcript.ifBlank(holdToTalk.elapsedLabel))
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 70)
    .padding(.horizontal, 12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var emojiPanel: some View {
    HStack(spacing: 4) {
      ForEach(["😀", "😂", "😍", "👍", "🎉", "🙏", "❤️"], id: \.self) { emoji in
        Button { draft.append(emoji) } label: {
          Text(emoji).font(.system(size: 24))
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel(Text(emoji))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        emojiPanelPresented = false
        holdToTalk.dragChanged(
          translation: value.translation,
          settings: voiceSettings,
          messages: SignalASIAgentHoldToTalkMessages(
            permissionDenied: t("signalasi.voice.permission_missing", "Microphone or speech permission is missing."),
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
      .onEnded { value in holdToTalk.dragEnded(translation: value.translation) }
  }
}

private extension View {
  func composerIconButton(label: String) -> some View {
    font(.system(size: 18, weight: .semibold))
      .foregroundColor(.signalASITextPrimary)
      .frame(width: 34, height: 34)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(label))
  }
}

private struct SignalASIChatVoiceWaveform: View {
  var phase: Double
  var cancelPending: Bool

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<18, id: \.self) { index in
        Capsule()
          .fill(cancelPending ? Color.red : Color.signalASIAccent)
          .frame(width: 3, height: 8 + abs(sin(phase + Double(index) * 0.58)) * 16)
      }
    }
    .accessibilityHidden(true)
  }
}
