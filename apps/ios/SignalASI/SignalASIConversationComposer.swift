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
  @FocusState private var inputFocused: Bool

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
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
      guard inputFocused, !voiceRecorder.isPending, !voiceRecorder.isRecording else { return }
      inputFocused = false
    }
    .onChange(of: inputFocused) { focused in
      guard focused, !voiceRecorder.isRecording else { return }
      voiceRecorder.cancelFromView()
    }
    .onDisappear { voiceRecorder.cancelFromView() }
  }

  private var inputRow: some View {
    HStack(spacing: 4) {
      textInput
      if canSend {
        Button {
          inputFocused = false
          onSend()
        } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.signalASIAccent)
            .frame(width: 54, height: 54)
            .background(Color(red: 0.655, green: 0.906, blue: 0.847))
            .clipShape(Circle())
        }
        .accessibilityLabel(Text(t("signalasi.common.send", "Send")))
      } else {
        Button {
          attachmentMenuPresented = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .frame(width: 54, height: 54)
        }
        .accessibilityLabel(Text(t("agent_attachment_add_file", "Add attachment")))
      }
    }
    .frame(minHeight: 72)
  }

  private var textInput: some View {
    TextField(t("signalasi.message.input", "Message"), text: $draft)
      .focused($inputFocused)
      .submitLabel(.send)
      .onSubmit {
        guard canSend else { return }
        inputFocused = false
        onSend()
      }
      .simultaneousGesture(holdToTalkGesture)
      .padding(.horizontal, 12)
      .frame(height: 54)
      .background(Color.signalASISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
      )
      .accessibilityLabel(Text(t("agent_voice_button", "Hold to talk")))
  }

  private var voiceCaptureSurface: some View {
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      Text(voiceRecorder.isPending
        ? t("signalasi.voice.preparing_title", "Preparing voice input")
        : voiceRecorder.cancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      if voiceRecorder.isRecording {
        SignalASIChatVoiceWaveform(
          phase: voiceRecorder.waveformPhase,
          cancelPending: voiceRecorder.cancelPending,
          color: .white
        )
        .frame(height: 38)
        Text(voiceRecorder.elapsedLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(voiceRecorder.cancelPending ? .red : .white)
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, minHeight: 236, alignment: .bottom)
    .background(Color.signalASIAgentRecordingDeep)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !inputFocused else { return }
        attachmentMenuPresented = false
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
      .onEnded { value in
        guard !inputFocused || voiceRecorder.isPending || voiceRecorder.isRecording else { return }
        voiceRecorder.dragEnded(translation: value.translation)
      }
  }
}

private struct SignalASIChatVoiceWaveform: View {
  var phase: Double
  var cancelPending: Bool
  var color: Color = .signalASIAccent

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<18, id: \.self) { index in
        Capsule()
          .fill(cancelPending ? Color.red : color)
          .frame(width: 3, height: 8 + abs(sin(phase + Double(index) * 0.58)) * 16)
      }
    }
    .accessibilityHidden(true)
  }
}
