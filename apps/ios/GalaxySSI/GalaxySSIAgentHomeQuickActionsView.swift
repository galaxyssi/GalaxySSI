import SwiftUI

struct GalaxySSIAgentHomeQuickActionsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var t: (String, String) -> String
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void

  var body: some View {
    Group {
      if usesAccessibilityDynamicType {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
          spacing: 0
        ) {
          ForEach(actions) { item in
            action(title: item.title, systemImage: item.systemImage, action: item.perform)
          }
        }
        .frame(height: 176)
      } else {
        HStack(spacing: 0) {
          ForEach(actions) { item in
            action(title: item.title, systemImage: item.systemImage, action: item.perform)
          }
        }
        .frame(height: 96)
      }
    }
    .padding(.horizontal, 8)
  }

  private var actions: [QuickAction] {
    [
      QuickAction(
        id: "new-session",
        title: t("agent_attachment_new_task", "New session"),
        systemImage: "square.and.pencil",
        perform: onNewSession
      ),
      QuickAction(
        id: "sessions",
        title: t("agent_attachment_sessions", "Sessions"),
        systemImage: "tray.full",
        perform: onOpenSessions
      ),
      QuickAction(
        id: "scan",
        title: t("agent_attachment_scan", "Scan Agent"),
        systemImage: "qrcode.viewfinder",
        perform: onScan
      ),
      QuickAction(
        id: "camera",
        title: t("agent_attachment_take_photo", "Take photo"),
        systemImage: "camera",
        perform: onTakePhoto
      ),
      QuickAction(
        id: "file",
        title: t("agent_attachment_add_file", "Add file"),
        systemImage: "paperclip",
        perform: onAddFile
      )
    ]
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
          .font(.system(size: usesAccessibilityDynamicType ? 13 : 11.5, weight: .regular))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(usesAccessibilityDynamicType ? 0.85 : 0.65)
      }
      .foregroundColor(.galaxySSITextPrimary)
      .frame(maxWidth: .infinity, minHeight: 84)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
  }
}

private struct QuickAction: Identifiable {
  var id: String
  var title: String
  var systemImage: String
  var perform: () -> Void
}
