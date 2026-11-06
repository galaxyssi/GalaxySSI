import SwiftUI

struct GalaxySSIAgentChatShortcuts: View {
  @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12
  let feedUnread: Int
  let chatUnread: Int
  let minimumTouchSize: CGFloat
  let onNewSession: () -> Void
  let onOpenSessions: () -> Void
  let onTakePhoto: () -> Void
  let onAddFile: () -> Void
  let t: (String, String) -> String

  private var rowHeight: CGFloat {
    max(44, max(minimumTouchSize, ceil(labelSize * 1.4) + 16))
  }

  var body: some View {
    GeometryReader { bounds in
      let width = max(max(44, minimumTouchSize), bounds.size.width / 5)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          NavigationLink(destination: GalaxySSIGlobalAgentInsightInboxView()) {
            label(t("galaxyssi.agent.shortcuts.feed", "Feed"), icon: "newspaper",
              width: width, unread: feedUnread)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("agent_global_insights_title", "GalaxySSI Insights")))
          .accessibilityValue(unreadValue(feedUnread))
          .accessibilityIdentifier("ios.agent.shortcuts.feed")

          action(t("galaxyssi.agent.shortcuts.new", "New"), description: t("new_conversation", "New conversation"),
            icon: "square.and.pencil", id: "new", width: width, perform: onNewSession)
          action(t("galaxyssi.agent.shortcuts.chats", "Chats"),
            description: t("galaxyssi.agent_sessions.title", "Sessions"),
            icon: "list.bullet", id: "chats", width: width, unread: chatUnread, perform: onOpenSessions)
          action(t("galaxyssi.agent.shortcuts.photo", "Photo"), description: t("agent_attachment_take_photo", "Take photo"),
            icon: "camera", id: "photo", width: width, perform: onTakePhoto)
          action(t("galaxyssi.agent.shortcuts.files", "Files"), description: t("agent_attachment_add_file", "Add file"),
            icon: "doc", id: "files", width: width, perform: onAddFile)
        }
      }
    }
    .frame(height: rowHeight)
  }

  private func action(_ title: String, description: String, icon: String, id: String,
                      width: CGFloat, unread: Int? = nil, perform: @escaping () -> Void) -> some View {
    Button(action: perform) {
      label(title, icon: icon, width: width, unread: unread)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(description))
    .accessibilityValue(unreadValue(unread ?? 0))
    .accessibilityIdentifier("ios.agent.shortcuts." + id)
  }

  private func label(_ title: String, icon: String, width: CGFloat, unread: Int?) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: max(16, labelSize), weight: .medium))
        .frame(width: max(17, labelSize + 1))
        .accessibilityHidden(true)
      HStack(alignment: .top, spacing: 2) {
        Text(title)
          .font(.system(size: labelSize))
          .fixedSize(horizontal: true, vertical: false)
        if let unread {
          Circle()
            .fill(Color.galaxySSITextPrimary)
            .frame(width: 4, height: 4)
            .opacity(unread > 0 ? 1 : 0)
            .accessibilityHidden(true)
        }
      }
    }
    .foregroundColor(.galaxySSITextPrimary)
    .padding(.horizontal, 4)
    .frame(minWidth: width, minHeight: rowHeight)
    .contentShape(Rectangle())
  }

  private func unreadValue(_ count: Int) -> Text {
    Text(count > 0 ? String(format: t("galaxyssi.agent.unread", "%d unread"), count) : "")
  }
}
