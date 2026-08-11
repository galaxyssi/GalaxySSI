import SwiftUI

struct SignalASIAgentHomeQuickActionsView: View {
  var t: (String, String) -> String
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      action(
        title: t("agent_attachment_new_task", "New session"),
        systemImage: "square.and.pencil",
        action: onNewSession
      )
      action(
        title: t("agent_attachment_sessions", "Sessions"),
        systemImage: "tray.full",
        action: onOpenSessions
      )
      action(
        title: t("agent_attachment_scan", "Scan Agent"),
        systemImage: "qrcode.viewfinder",
        action: onScan
      )
      action(
        title: t("agent_attachment_take_photo", "Take photo"),
        systemImage: "camera",
        action: onTakePhoto
      )
      action(
        title: t("agent_attachment_add_file", "Add file"),
        systemImage: "paperclip",
        action: onAddFile
      )
    }
    .frame(height: 96)
    .padding(.horizontal, 8)
  }

  private func action(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 21, weight: .semibold))
          .frame(width: 25, height: 25)
        Text(title)
          .font(.system(size: 11.5, weight: .regular))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
      .foregroundColor(.signalASITextPrimary)
      .frame(maxWidth: .infinity, minHeight: 84)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
