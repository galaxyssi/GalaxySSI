import SwiftUI

struct SignalASIMainTabView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var selectedTab: SignalASIMainTab = .agent

  var body: some View {
    selectedContent
      .safeAreaInset(edge: .bottom, spacing: 0) {
        SignalASIMainTabBar(
          selection: $selectedTab,
          interfaceLanguage: interfaceLanguage
        )
      }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .voice:
      SignalASIVoiceTabView(onNavigateToMainTab: { selectedTab = $0 })
    case .agent:
      AgentHomeView(onNavigateToMainTab: { selectedTab = $0 })
    case .messages:
      ChatListView(
        showsBackButton: false,
        onNavigateToMainTab: { selectedTab = $0 }
      )
    case .contacts:
      ContactsView(showsBackButton: false)
    case .discover:
      DiscoverView(showsBackButton: false)
    case .settings:
      SettingsView(
        navigateToMainTab: { tab in
          selectedTab = tab
        },
        showsBackButton: false
      )
    }
  }
}

private struct SignalASIMainTabBar: View {
  @Binding var selection: SignalASIMainTab
  let interfaceLanguage: String

  var body: some View {
    HStack(spacing: 0) {
      ForEach(SignalASIMainTab.allCases) { tab in
        SignalASIMainTabButton(
          tab: tab,
          selected: selection == tab,
          title: title(for: tab)
        ) {
          selection = tab
        }
      }
    }
    .padding(.top, 5)
    .padding(.bottom, 6)
    .background(Color.signalASIBarBackground)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.signalASISeparator)
        .frame(height: 0.5)
    }
  }

  private func title(for tab: SignalASIMainTab) -> String {
    SignalASILocalization.string(
      tab.titleKey,
      fallback: tab.fallbackTitle,
      language: interfaceLanguage
    )
  }
}

private struct SignalASIMainTabButton: View {
  let tab: SignalASIMainTab
  let selected: Bool
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        tabIcon
          .frame(width: 25, height: 25)
        Text(title)
          .font(.system(size: 10, weight: selected ? .semibold : .regular))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundColor(selected ? .signalASIAccent : .signalASITextSecondary)
      .frame(maxWidth: .infinity, minHeight: 45)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  @ViewBuilder
  private var tabIcon: some View {
    if let assetName = selected ? tab.selectedIconAssetName : tab.iconAssetName {
      Image(assetName)
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
    } else {
      Image(systemName: selected ? tab.selectedSystemIconName : tab.systemIconName)
        .font(.system(size: 21, weight: .semibold))
    }
  }
}

enum SignalASIMainTab: String, CaseIterable, Identifiable {
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

  var iconAssetName: String? {
    switch self {
    case .voice:
      return nil
    case .agent:
      return "TabAgent"
    case .messages:
      return "TabMessages"
    case .contacts:
      return "TabContacts"
    case .discover:
      return "TabDiscover"
    case .settings:
      return "TabSettings"
    }
  }

  var selectedIconAssetName: String? {
    switch self {
    case .voice:
      return nil
    case .agent:
      return "TabAgentSelected"
    case .messages:
      return "TabMessagesSelected"
    case .contacts:
      return "TabContactsSelected"
    case .discover:
      return "TabDiscoverSelected"
    case .settings:
      return "TabSettingsSelected"
    }
  }

  var systemIconName: String {
    switch self {
    case .voice:
      return "mic.circle"
    case .agent:
      return "sparkles"
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

  var selectedSystemIconName: String {
    switch self {
    case .voice:
      return "mic.circle.fill"
    case .agent:
      return "sparkles"
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
