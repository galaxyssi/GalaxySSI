import SwiftUI

struct SignalASIAgentHomeQuickActionsView: View {
  var t: (String, String) -> String
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onOpenSettings: () -> Void

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
      spacing: 8
    ) {
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
      action(
        title: t("signalasi.tab.settings", "Settings"),
        systemImage: "ellipsis.circle",
        action: onOpenSettings
      )
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 2)
  }

  private func action(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASIAccent)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
