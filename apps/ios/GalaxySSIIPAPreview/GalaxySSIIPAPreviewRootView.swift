import SwiftUI
import UIKit

struct GalaxySSIIPAPreviewRootView: View {
  @State private var selectedTab = 0
  @State private var draft = ""
  @State private var hasScannedAgent = false
  @State private var scanPresented = false
  @State private var executionEnabled = true
  @State private var memoryEnabled = true
  @State private var message = ""

  private var chinese: Bool {
    Locale.current.languageCode?.hasPrefix("zh") == true
  }

  private func text(_ key: String, _ fallback: String) -> String {
    guard chinese,
          let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return fallback
    }
    return bundle.localizedString(forKey: key, value: fallback, table: nil)
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      agentHome
        .tabItem { Label(text("preview.tab.agent", "Agent"), systemImage: "sparkles") }
        .tag(0)
      messages
        .tabItem { Label(text("preview.tab.messages", "Messages"), systemImage: "bubble.left.and.bubble.right") }
        .tag(1)
      devices
        .tabItem { Label(text("preview.tab.devices", "Devices"), systemImage: "laptopcomputer.and.iphone") }
        .tag(2)
      settings
        .tabItem { Label(text("preview.tab.settings", "Settings"), systemImage: "gearshape") }
        .tag(3)
    }
    .accentColor(Color(red: 0.10, green: 0.54, blue: 0.47))
    .sheet(isPresented: $scanPresented) {
      AgentScanSheet(
        title: text("preview.scan.title", "Add agent"),
        subtitle: text("preview.scan.subtitle", "Scan a QR code or enter a pairing code"),
        cancelTitle: text("preview.common.cancel", "Cancel"),
        connectTitle: text("preview.scan.connect", "Connect agent"),
        onConnect: {
          hasScannedAgent = true
          scanPresented = false
        }
      )
    }
  }

  private var agentHome: some View {
    NavigationView {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
              Image("GalaxySSILogo")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
              VStack(alignment: .leading, spacing: 2) {
                Text("GalaxySSI")
                  .font(.headline)
                Text(text("preview.home.subtitle", "Local-first agent"))
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }
              Spacer()
              Button(action: { selectedTab = 3 }) {
                Image(systemName: "slider.horizontal.3")
              }
              .accessibilityLabel(text("preview.tab.settings", "Settings"))
            }

            VStack(alignment: .leading, spacing: 10) {
              Text(text("preview.home.prompt", "What would you like to get done?"))
                .font(.title2)
                .fontWeight(.semibold)
              Text(text("preview.home.approval_notice", "GalaxySSI shows actions that need approval before it runs them."))
                .font(.subheadline)
                .foregroundColor(.secondary)
              HStack(spacing: 10) {
                AgentMetric(value: hasScannedAgent ? "1" : "0", title: text("preview.home.connected_agents", "Connected agents"))
                AgentMetric(value: executionEnabled ? text("preview.state.on", "On") : text("preview.state.paused", "Paused"), title: text("preview.home.execution", "Execution"))
                AgentMetric(value: memoryEnabled ? text("preview.state.on", "On") : text("preview.state.paused", "Paused"), title: text("preview.home.memory", "Memory"))
              }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
              Text(text("preview.home.quick_actions", "Quick actions"))
                .font(.headline)
              HStack(spacing: 10) {
                AgentShortcut(title: text("preview.scan.short_title", "Scan to add"), icon: "qrcode.viewfinder") {
                  scanPresented = true
                }
                AgentShortcut(title: text("preview.home.new_task", "New task"), icon: "plus.message") {
                  message = text("preview.home.new_task_ready", "A new agent task is ready.")
                }
                AgentShortcut(title: text("preview.home.recent_tasks", "Recent tasks"), icon: "clock.arrow.circlepath") {
                  message = text("preview.home.no_completed_tasks", "No completed tasks yet.")
                }
              }
            }

            if !message.isEmpty {
              Text(message)
                .font(.subheadline)
                .foregroundColor(Color(red: 0.08, green: 0.45, blue: 0.38))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.88, green: 0.96, blue: 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 12) {
              Text(text("preview.home.suggested", "Suggested"))
                .font(.headline)
              SuggestionRow(icon: "doc.text.magnifyingglass", title: text("preview.suggestion.organize_tasks", "Organize today's tasks"), subtitle: text("preview.suggestion.organize_tasks_detail", "Extract actions from messages and notes"))
              SuggestionRow(icon: "network", title: text("preview.suggestion.check_devices", "Check connected devices"), subtitle: text("preview.suggestion.check_devices_detail", "Review agent and device status"))
              SuggestionRow(icon: "hand.raised", title: text("preview.suggestion.manage_permissions", "Manage execution permissions"), subtitle: text("preview.suggestion.manage_permissions_detail", "Choose which actions need approval"))
            }
          }
          .padding(16)
        }
        composer
      }
      .navigationBarHidden(true)
    }
  }

  private var composer: some View {
    HStack(spacing: 10) {
      Button(action: { scanPresented = true }) {
        Image(systemName: "qrcode.viewfinder")
          .frame(width: 34, height: 34)
      }
      TextField(text("preview.composer.placeholder", "Enter a goal or question"), text: $draft)
        .textFieldStyle(RoundedBorderTextFieldStyle())
      Button(action: {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        message = text("preview.composer.task_ready", "Task ready: ") + trimmed
        draft = ""
      }) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
      }
      .accessibilityLabel(text("preview.composer.send", "Send"))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(.systemBackground))
  }

  private var messages: some View {
    NavigationView {
      List {
        Section(header: Text(text("preview.messages.section", "Agent conversations"))) {
          MessageRow(title: text("preview.messages.start_goal", "Start a goal"), detail: text("preview.messages.start_goal_detail", "Agent activity will appear here"), icon: "sparkles")
        }
      }
      .listStyle(InsetGroupedListStyle())
      .navigationTitle(text("preview.tab.messages", "Messages"))
    }
  }

  private var devices: some View {
    NavigationView {
      List {
        Section(header: Text(text("preview.devices.agents", "Agents"))) {
          Button(action: { scanPresented = true }) {
            HStack {
              Image(systemName: "qrcode.viewfinder")
              Text(text("preview.devices.scan_agent", "Scan to add agent"))
              Spacer()
              Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
          }
          if hasScannedAgent {
            MessageRow(title: text("preview.devices.paired_agent", "Paired agent"), detail: text("preview.devices.paired_agent_detail", "Online, waiting for tasks"), icon: "cpu")
          }
        }
        Section(header: Text(text("preview.devices.this_device", "This device"))) {
          MessageRow(title: UIDevice.current.name, detail: text("preview.devices.requirement", "iOS 15 or later"), icon: "iphone")
        }
      }
      .listStyle(InsetGroupedListStyle())
      .navigationTitle(text("preview.tab.devices", "Devices"))
    }
  }

  private var settings: some View {
    NavigationView {
      Form {
        Section(header: Text(text("preview.tab.agent", "Agent"))) {
          Toggle(text("preview.settings.allow_execution", "Allow execution"), isOn: $executionEnabled)
          Toggle(text("preview.settings.enable_memory", "Enable memory"), isOn: $memoryEnabled)
          HStack {
            Text(text("preview.settings.confirmation_mode", "Confirmation mode"))
            Spacer()
            Text(text("preview.settings.ask_every_time", "Ask every time")).foregroundColor(.secondary)
          }
        }
        Section(header: Text(text("preview.settings.runtime", "On-device runtime"))) {
          HStack {
            Text(text("preview.settings.model_status", "Model status"))
            Spacer()
            Text(text("preview.settings.not_downloaded", "Not downloaded")).foregroundColor(.secondary)
          }
          HStack {
            Text(text("preview.settings.language", "Language"))
            Spacer()
            Text(text("preview.settings.language_value", "English")).foregroundColor(.secondary)
          }
        }
        Section {
          HStack {
            Image("GalaxySSILogo").resizable().scaledToFit().frame(width: 28, height: 28)
            VStack(alignment: .leading) {
              Text("GalaxySSI")
              Text(text("preview.settings.version", "iOS preview · iOS 15+"))
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
        }
      }
      .navigationTitle(text("preview.tab.settings", "Settings"))
    }
  }
}

private struct AgentMetric: View {
  let value: String
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value).font(.headline)
      Text(title).font(.caption).foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct AgentShortcut: View {
  let title: String
  let icon: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image(systemName: icon).font(.title3)
        Text(title).font(.caption).multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, minHeight: 70)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(PlainButtonStyle())
  }
}

private struct SuggestionRow: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(Color(red: 0.10, green: 0.54, blue: 0.47))
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline).fontWeight(.medium)
        Text(subtitle).font(.footnote).foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(.vertical, 3)
  }
}

private struct MessageRow: View {
  let title: String
  let detail: String
  let icon: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .frame(width: 26)
        .foregroundColor(Color(red: 0.10, green: 0.54, blue: 0.47))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
        Text(detail).font(.footnote).foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct AgentScanSheet: View {
  let title: String
  let subtitle: String
  let cancelTitle: String
  let connectTitle: String
  let onConnect: () -> Void
  @State private var pairingCode = ""
  @Environment(\.presentationMode) private var presentationMode

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        Image(systemName: "qrcode.viewfinder")
          .font(.system(size: 64))
          .foregroundColor(Color(red: 0.10, green: 0.54, blue: 0.47))
        Text(subtitle)
          .multilineTextAlignment(.center)
          .foregroundColor(.secondary)
        TextField("SIG-0000", text: $pairingCode)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .autocapitalization(.allCharacters)
          .padding(.horizontal, 24)
        Button(action: onConnect) {
          Text(connectTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 0.10, green: 0.54, blue: 0.47))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 24)
        Spacer()
      }
      .padding(.top, 42)
      .navigationTitle(title)
      .navigationBarItems(trailing: Button(cancelTitle) { presentationMode.wrappedValue.dismiss() })
    }
  }
}
