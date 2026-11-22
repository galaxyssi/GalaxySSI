import SwiftUI

@MainActor
struct GalaxySSIAgentChatShortcuts: View {
  @Environment(\.layoutDirection) private var direction
  @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12
  @StateObject private var scroll = GalaxySSIAgentShortcutScrollReference()
  typealias Action = GalaxySSIAgentChatShortcutLayout.Action
  let feedUnread: Int
  let chatUnread: Int
  let minimumTouchSize: CGFloat
  let onOpenFeed: () -> Void
  let onNewSession: () -> Void
  let onOpenSessions: () -> Void
  let onTakePhoto: () -> Void
  let onAddFile: () -> Void
  let onOpenHealth: () -> Void
  let onScan: () -> Void
  let t: (String, String) -> String

  private var rowHeight: CGFloat {
    GalaxySSIAgentChatShortcutLayout.height(fontSize: labelSize, minimumTouch: minimumTouchSize)
  }

  var body: some View {
    GeometryReader { bounds in
      let widths = GalaxySSIAgentChatShortcutLayout.widths(available: bounds.size.width,
        natural: Action.allCases.map(naturalWidth), minimumTouch: minimumTouchSize)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(Array(Action.allCases.enumerated()), id: \.element.id) { index, action in
            Button { scroll.activate { perform(action) } } label: {
              label(title(action), icon: icon(action), width: widths[index], unread: unread(action), health: action == .health)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(description(action)))
            .accessibilityValue(unreadValue(unread(action) ?? 0))
            .accessibilityIdentifier("ios.agent.shortcuts." + action.rawValue)
            .help(description(action))
          }
        }
        .background(GalaxySSIAgentShortcutScrollResolver(reference: scroll, rtl: direction == .rightToLeft))
      }
    }
    .frame(height: rowHeight)
  }

  private func title(_ action: Action) -> String {
    let fallback: String
    switch action {
    case .feed: fallback = "Feed"
    case .newSession: fallback = "New"
    case .chats: fallback = "Chats"
    case .photo: fallback = "Photo"
    case .files: fallback = "Files"
    case .health: fallback = "Health"
    case .scan: fallback = "Scan"
    }
    return t("galaxyssi.agent.shortcuts." + action.rawValue, fallback)
  }
  private func description(_ action: Action) -> String {
    switch action {
    case .feed: return t("agent_global_insights_title", "GalaxySSI Insights")
    case .newSession: return t("new_conversation", "New conversation")
    case .chats: return t("galaxyssi.agent_sessions.title", "Sessions")
    case .photo: return t("agent_attachment_take_photo", "Take photo")
    case .files: return t("agent_attachment_add_file", "Add file")
    case .health: return t("galaxyssi.health.title", "Health Center")
    case .scan: return t("galaxyssi.agent.shortcuts.scan", "Scan")
    }
  }
  private func icon(_ action: Action) -> String {
    switch action {
    case .feed: return "newspaper"
    case .newSession: return "square.and.pencil"
    case .chats: return "list.bullet"
    case .photo: return "camera"
    case .files: return "doc"
    case .health: return "heart"
    case .scan: return "qrcode.viewfinder"
    }
  }
  private func unread(_ action: Action) -> Int? {
    action == .feed ? feedUnread : action == .chats ? chatUnread : nil
  }
  private func perform(_ action: Action) {
    switch action {
    case .feed: onOpenFeed()
    case .newSession: onNewSession()
    case .chats: onOpenSessions()
    case .photo: onTakePhoto()
    case .files: onAddFile()
    case .health: onOpenHealth()
    case .scan: onScan()
    }
  }
  private func naturalWidth(_ action: Action) -> CGFloat {
    GalaxySSIAgentChatShortcutLayout.naturalWidth(title: title(action), fontSize: labelSize, showsUnread: unread(action) != nil)
  }

  private func label(_ title: String, icon: String, width: CGFloat, unread: Int?, health: Bool) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .foregroundColor(health ? .red : .galaxySSITextPrimary)
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
    .frame(width: width, height: rowHeight)
    .contentShape(Rectangle())
  }

  private func unreadValue(_ count: Int) -> Text {
    Text(count > 0 ? String(format: t("galaxyssi.agent.unread", "%d unread"), count) : "")
  }
}
