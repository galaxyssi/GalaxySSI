import SwiftUI

struct SignalASIConversationComposer: View {
  @Binding var draft: String
  @Binding var attachments: [SignalASIDraftAttachment]
  @Binding var attachmentError: String
  @Binding var attachmentMenuPresented: Bool

  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var onSend: () -> Void
  var onVoiceAttachment: (SignalASIDraftAttachment, TimeInterval) -> Void
  var t: (String, String) -> String

  @StateObject private var voiceRecorder = SignalASIChatVoiceRecorder()
  @State private var emojiPanelPresented = false
  @State private var voiceMode = false

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
      if !voiceRecorder.statusMessage.isEmpty {
        Text(voiceRecorder.statusMessage)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if voiceRecorder.isPending || voiceRecorder.isRecording {
        voiceCaptureSurface
      } else {
        inputRow
      }
      if emojiPanelPresented && !voiceRecorder.isRecording {
        emojiPanel
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .onDisappear { voiceRecorder.cancelFromView() }
  }

  private var inputRow: some View {
    HStack(spacing: 8) {
      Button {
        voiceMode.toggle()
        emojiPanelPresented = false
      } label: {
        Image(systemName: voiceMode ? "keyboard" : "mic")
      }
      .composerIconButton(
        label: voiceMode
          ? t("signalasi.message.input", "Message")
          : t("agent_voice_button", "Hold to talk")
      )

      if voiceMode {
        voiceModeInput
      } else {
        textInput
      }

      Button { emojiPanelPresented.toggle() } label: {
        Image(systemName: "face.smiling")
      }
      .composerIconButton(label: t("signalasi.message.emoji", "Emoji"))

      if canSend {
        Button(action: onSend) {
          Image(systemName: "arrow.up")
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.signalASIAccent))
        }
        .accessibilityLabel(Text(t("signalasi.common.send", "Send")))
      } else {
        Button {
          emojiPanelPresented = false
          attachmentMenuPresented = true
        } label: {
          Image(systemName: "plus")
        }
        .composerIconButton(label: t("agent_attachment_add_file", "Add attachment"))
      }
    }
  }

  private var textInput: some View {
    TextField(t("signalasi.message.input", "Message"), text: $draft)
      .padding(.horizontal, 12)
      .frame(minHeight: 36)
      .background(Color.signalASISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
      )
  }

  private var voiceModeInput: some View {
    Button {} label: {
      Text(t("agent_voice_button", "Hold to talk"))
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.signalASITextPrimary)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Color.signalASISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .simultaneousGesture(holdToTalkGesture)
    .accessibilityLabel(Text(t("agent_voice_button", "Hold to talk")))
  }

  private var voiceCaptureSurface: some View {
    VStack(spacing: 8) {
      Text(voiceRecorder.isPending
        ? t("signalasi.voice.preparing_title", "Preparing voice input")
        : voiceRecorder.cancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      if voiceRecorder.isRecording {
        SignalASIChatVoiceWaveform(phase: voiceRecorder.waveformPhase, cancelPending: voiceRecorder.cancelPending)
          .frame(height: 24)
        Text(voiceRecorder.elapsedLabel)
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
        voiceRecorder.dragChanged(
          translation: value.translation,
          messages: SignalASIChatVoiceRecorderMessages(
            permissionDenied: t("signalasi.voice.permission_missing", "Microphone permission is missing."),
            recordingFailed: t("signalasi.voice.recording_failed", "Could not start voice recording."),
            tooShort: t("voice_too_short", "Hold a little longer."),
            cancelled: t("voice_cancelled", "Voice cancelled.")
          ),
          onFinish: onVoiceAttachment
        )
      }
      .onEnded { value in voiceRecorder.dragEnded(translation: value.translation) }
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
