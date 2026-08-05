import SwiftUI

struct SignalASIMainTabView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var selection = SignalASIMainTab.agent

  private var unreadTotal: Int {
    store.visibleContacts.reduce(0) { total, contact in
      total + store.conversationSummary(for: contact.id).unreadCount
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      activeContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
        .background(Color.signalASISeparator)
      tabBar
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
  }

  @ViewBuilder
  private var activeContent: some View {
    switch selection {
    case .voice:
      NavigationView {
        SignalASIVoiceControlCenterView(showsBackButton: false)
      }
      .navigationViewStyle(StackNavigationViewStyle())
    case .agent:
      AgentHomeView()
    case .messages:
      ChatListView()
    case .contacts:
      ContactsView()
    case .discover:
      DiscoverView()
    case .settings:
      SettingsView()
    }
  }

  private var tabBar: some View {
    HStack(spacing: 0) {
      ForEach(SignalASIMainTab.allCases) { tab in
        SignalASIMainTabButton(
          tab: tab,
          title: title(for: tab),
          isSelected: selection == tab,
          badgeCount: badgeCount(for: tab)
        ) {
          withAnimation(.easeOut(duration: 0.14)) {
            selection = tab
          }
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.top, 6)
    .padding(.bottom, 8)
    .background(Color.signalASIBarBackground)
  }

  private func badgeCount(for tab: SignalASIMainTab) -> Int {
    switch tab {
    case .messages:
      return unreadTotal
    case .contacts:
      return store.pendingFriendRequests.count
    case .voice, .agent, .discover, .settings:
      return 0
    }
  }

  private func title(for tab: SignalASIMainTab) -> String {
    SignalASILocalization.string(tab.titleKey, fallback: tab.fallbackTitle, language: interfaceLanguage)
  }
}

private enum SignalASIMainTab: String, CaseIterable, Identifiable {
  case voice
  case agent
  case messages
  case contacts
  case discover
  case settings

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .voice:
      return "signalasi.tab.voice"
    case .agent:
      return "signalasi.tab.agent"
    case .messages:
      return "signalasi.tab.messages"
    case .contacts:
      return "signalasi.tab.contacts"
    case .discover:
      return "signalasi.tab.discover"
    case .settings:
      return "signalasi.tab.settings"
    }
  }

  var fallbackTitle: String {
    switch self {
    case .voice:
      return "Voice"
    case .agent:
      return "Agent"
    case .messages:
      return "Messages"
    case .contacts:
      return "Contacts"
    case .discover:
      return "Discover"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .voice:
      return "waveform"
    case .agent:
      return "cpu"
    case .messages:
      return "message"
    case .contacts:
      return "person.2"
    case .discover:
      return "safari"
    case .settings:
      return "gearshape"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .voice:
      return "waveform.circle.fill"
    case .agent:
      return "cpu.fill"
    case .messages:
      return "message.fill"
    case .contacts:
      return "person.2.fill"
    case .discover:
      return "safari.fill"
    case .settings:
      return "gearshape.fill"
    }
  }
}

private struct SignalASIMainTabButton: View {
  var tab: SignalASIMainTab
  var title: String
  var isSelected: Bool
  var badgeCount: Int
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        ZStack(alignment: .topTrailing) {
          Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 30, height: 24)
          if badgeCount > 0 {
            Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
              .font(.system(size: 9, weight: .bold))
              .foregroundColor(.white)
              .monospacedDigit()
              .padding(.horizontal, 4)
              .frame(minWidth: 16, minHeight: 16)
              .background(Capsule().fill(Color.signalASIUnreadRed))
              .offset(x: 10, y: -7)
          }
        }
        Text(title)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundColor(isSelected ? .signalASIAccent : .signalASITextSecondary)
      .frame(maxWidth: .infinity, minHeight: 54)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
