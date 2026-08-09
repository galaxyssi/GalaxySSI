import SwiftUI

struct SignalASIMainTabView: View {
  var body: some View {
    AgentHomeView()
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
