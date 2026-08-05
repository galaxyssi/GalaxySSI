import SwiftUI

struct SignalASIAgentComposerView: View {
  @Binding var draft: String
  @Binding var actionTrayPresented: Bool

  var attachments: [SignalASIDraftAttachment]
  var attachmentError: String
  var canSend: Bool
  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var onRemoveAttachment: (SignalASIDraftAttachment) -> Void
  var onNewSession: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onSend: () -> Void
  var t: (String, String) -> String

  private var trayVisible: Bool {
    actionTrayPresented && !canSend
  }

  private var minimumTouchSize: CGFloat {
    CGFloat(deviceInputPolicy.minimumTouchTargetDp)
  }

  var body: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        AttachmentPreviewStrip(attachments: attachments, onRemove: onRemoveAttachment)
      }
      if !attachmentError.isEmpty {
        Text(attachmentError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      inputRow
      if trayVisible {
        actionTray
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .animation(deviceInputPolicy.reduceMotion ? nil : .easeOut(duration: 0.16), value: trayVisible)
    .onChange(of: canSend) { hasInput in
      if hasInput {
        actionTrayPresented = false
      }
    }
  }

  private var inputRow: some View {
    HStack(spacing: 4) {
      inputShell
      primaryActionButton
    }
    .frame(minHeight: 72)
  }

  private var inputShell: some View {
    HStack(spacing: 6) {
      NavigationLink(destination: SignalASIVoiceAssistantSettingsView()) {
        Image(systemName: "waveform")
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(.blue)
          .frame(width: 42, height: 42)
          .background(Color.signalASIButtonSoft)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("signalasi.agent.voice_button", "Hold to talk")))

      TextField(t("signalasi.agent.goal_hint", "Enter message or hold to talk..."), text: $draft)
        .font(.system(size: 15))
        .textInputAutocapitalization(.sentences)
        .lineLimit(2)
        .onTapGesture {
          actionTrayPresented = false
        }
    }
    .padding(.leading, 6)
    .padding(.trailing, 10)
    .frame(maxWidth: .infinity, minHeight: 54)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var primaryActionButton: some View {
    if canSend {
      Button {
        actionTrayPresented = false
        onSend()
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(.signalASIAccent)
          .frame(width: 54, height: 54)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .frame(minWidth: minimumTouchSize, minHeight: minimumTouchSize)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(t("signalasi.common.send", "Send")))
    } else {
      Button {
        actionTrayPresented.toggle()
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .rotationEffect(.degrees(trayVisible ? 45 : 0))
          .frame(width: 54, height: 54)
          .background(Color.signalASISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .frame(minWidth: minimumTouchSize, minHeight: minimumTouchSize)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(trayVisible
        ? t("agent_attachment_close_menu", "Close actions")
        : t("agent_attachment_open_menu", "More actions")))
    }
  }

  private var actionTray: some View {
    HStack(spacing: 0) {
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_new_task", "New session"),
        systemImage: "square.and.pencil",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onNewSession()
      }
      SignalASIAgentComposerTrayNavigationLink(
        title: t("agent_attachment_sessions", "Sessions"),
        systemImage: "tray.full",
        minimumTouchSize: minimumTouchSize,
        destination: SignalASIAgentSessionsView()
      ) {
        closeTray()
      }
      SignalASIAgentComposerTrayNavigationLink(
        title: t("agent_attachment_scan", "Scan"),
        systemImage: "qrcode.viewfinder",
        minimumTouchSize: minimumTouchSize,
        destination: AddContactView(autoOpenScanner: true)
      ) {
        closeTray()
      }
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_take_photo", "Take photo"),
        systemImage: "camera",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onTakePhoto()
      }
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_add_file", "Add file"),
        systemImage: "doc",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onAddFile()
      }
    }
    .frame(height: 96)
    .background(Color.signalASIBarBackground)
  }

  private func closeTray() {
    actionTrayPresented = false
  }
}

private struct SignalASIAgentComposerTrayButton: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SignalASIAgentComposerTrayContent(
        title: title,
        systemImage: systemImage,
        minimumTouchSize: minimumTouchSize
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

private struct SignalASIAgentComposerTrayNavigationLink<Destination: View>: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat
  var destination: Destination
  var onNavigate: () -> Void

  var body: some View {
    NavigationLink(destination: destination) {
      SignalASIAgentComposerTrayContent(
        title: title,
        systemImage: systemImage,
        minimumTouchSize: minimumTouchSize
      )
    }
    .simultaneousGesture(TapGesture().onEnded { _ in onNavigate() })
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

private struct SignalASIAgentComposerTrayContent: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 25, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 30, height: 30)
      Text(title)
        .font(.system(size: 12, weight: .regular))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: minimumTouchSize)
    .contentShape(Rectangle())
  }
}
