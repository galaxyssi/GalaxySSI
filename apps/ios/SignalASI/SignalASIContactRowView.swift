import SwiftUI

struct ContactRow: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  var contact: SignalASIContact
  var summary: ContactConversationSummary
  var showsSummary = true

  private var kindPresentation: SignalASIContactKindPresentation? {
    SignalASIContactKindPresentation.forContact(contact, t: t)
  }

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(contact: contact, size: showsSummary ? 44 : 36)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(contactTitle)
            .font(.system(size: showsSummary ? 15.5 : 15, weight: summary.hasUnreadMessages ? .semibold : .regular))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          if let kindPresentation {
            SignalASIContactKindBadge(presentation: kindPresentation)
          }
          Spacer()
          if showsSummary, let latestMessage = summary.lastMessage {
            Text(
              SignalASIChatListTimeFormatter.string(
                for: latestMessage.createdAt,
                language: interfaceLanguage
              )
            )
              .font(.system(size: 12))
              .foregroundColor(.signalASITextSecondary)
          }
        }
        if showsSummary {
          Text(summary.previewText.ifBlank(t("chat_no_messages", "No messages yet")))
            .lineLimit(1)
            .font(.system(size: 14))
            .foregroundColor(summary.hasUnreadMessages ? .signalASITextPrimary : .signalASITextSecondary)
        }
      }
      if showsSummary, summary.hasUnreadMessages {
        Text(summary.unreadCount > 99 ? "99+" : "\(summary.unreadCount)")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundColor(.white)
          .frame(minWidth: 22)
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.signalASIUnreadRed))
          .accessibilityLabel(Text("\(summary.unreadCount) unread messages"))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, showsSummary ? 10 : 8)
    .frame(minHeight: showsSummary ? 70 : 56)
    .background(Color.signalASISurface)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private var contactTitle: String {
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(SignalASIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }
}
