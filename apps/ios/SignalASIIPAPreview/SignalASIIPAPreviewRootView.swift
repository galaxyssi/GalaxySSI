import SwiftUI
import UIKit

struct SignalASIIPAPreviewRootView: View {
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

  private func text(_ zh: String, _ en: String) -> String {
    chinese ? zh : en
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      agentHome
        .tabItem { Label(text("智能体", "Agent"), systemImage: "sparkles") }
        .tag(0)
      messages
        .tabItem { Label(text("消息", "Messages"), systemImage: "bubble.left.and.bubble.right") }
        .tag(1)
      devices
        .tabItem { Label(text("设备", "Devices"), systemImage: "laptopcomputer.and.iphone") }
        .tag(2)
      settings
        .tabItem { Label(text("设置", "Settings"), systemImage: "gearshape") }
        .tag(3)
    }
    .accentColor(Color(red: 0.10, green: 0.54, blue: 0.47))
    .sheet(isPresented: $scanPresented) {
      AgentScanSheet(
        title: text("添加智能体", "Add agent"),
        subtitle: text("扫描二维码或输入配对代码", "Scan a QR code or enter a pairing code"),
        cancelTitle: text("取消", "Cancel"),
        connectTitle: text("连接智能体", "Connect agent"),
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
              Image("SignalASILogo")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
              VStack(alignment: .leading, spacing: 2) {
                Text("SignalASI")
                  .font(.headline)
                Text(text("本地优先智能体", "Local-first agent"))
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }
              Spacer()
              Button(action: { selectedTab = 3 }) {
                Image(systemName: "slider.horizontal.3")
              }
              .accessibilityLabel(text("设置", "Settings"))
            }

            VStack(alignment: .leading, spacing: 10) {
              Text(text("今天想完成什么？", "What would you like to get done?"))
                .font(.title2)
                .fontWeight(.semibold)
              Text(text("SignalASI 会在执行前展示需要确认的操作。", "SignalASI shows actions that need approval before it runs them."))
                .font(.subheadline)
                .foregroundColor(.secondary)
              HStack(spacing: 10) {
                AgentMetric(value: hasScannedAgent ? "1" : "0", title: text("已连接智能体", "Connected agents"))
                AgentMetric(value: executionEnabled ? text("开启", "On") : text("暂停", "Paused"), title: text("执行", "Execution"))
                AgentMetric(value: memoryEnabled ? text("开启", "On") : text("暂停", "Paused"), title: text("记忆", "Memory"))
              }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
              Text(text("快捷操作", "Quick actions"))
                .font(.headline)
              HStack(spacing: 10) {
                AgentShortcut(title: text("扫描添加", "Scan to add"), icon: "qrcode.viewfinder") {
                  scanPresented = true
                }
                AgentShortcut(title: text("新任务", "New task"), icon: "plus.message") {
                  message = text("已创建新的智能体任务。", "A new agent task is ready.")
                }
                AgentShortcut(title: text("最近任务", "Recent tasks"), icon: "clock.arrow.circlepath") {
                  message = text("暂无已完成任务。", "No completed tasks yet.")
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
              Text(text("建议", "Suggested"))
                .font(.headline)
              SuggestionRow(icon: "doc.text.magnifyingglass", title: text("整理今天的待办", "Organize today's tasks"), subtitle: text("从消息和笔记中提取行动项", "Extract actions from messages and notes"))
              SuggestionRow(icon: "network", title: text("检查已连接设备", "Check connected devices"), subtitle: text("查看 Agent 与设备状态", "Review agent and device status"))
              SuggestionRow(icon: "hand.raised", title: text("管理执行权限", "Manage execution permissions"), subtitle: text("选择需要确认的操作", "Choose which actions need approval"))
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
      TextField(text("输入目标或问题", "Enter a goal or question"), text: $draft)
        .textFieldStyle(RoundedBorderTextFieldStyle())
      Button(action: {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        message = text("已准备任务：", "Task ready: ") + trimmed
        draft = ""
      }) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
      }
      .accessibilityLabel(text("发送", "Send"))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(.systemBackground))
  }

  private var messages: some View {
    NavigationView {
      List {
        Section(header: Text(text("智能体会话", "Agent conversations"))) {
          MessageRow(title: text("开始一个目标", "Start a goal"), detail: text("智能体会在这里显示执行过程", "Agent activity will appear here"), icon: "sparkles")
        }
      }
      .listStyle(InsetGroupedListStyle())
      .navigationTitle(text("消息", "Messages"))
    }
  }

  private var devices: some View {
    NavigationView {
      List {
        Section(header: Text(text("智能体", "Agents"))) {
          Button(action: { scanPresented = true }) {
            HStack {
              Image(systemName: "qrcode.viewfinder")
              Text(text("扫描添加智能体", "Scan to add agent"))
              Spacer()
              Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
          }
          if hasScannedAgent {
            MessageRow(title: text("已配对智能体", "Paired agent"), detail: text("在线，等待任务", "Online, waiting for tasks"), icon: "cpu")
          }
        }
        Section(header: Text(text("本机", "This device"))) {
          MessageRow(title: UIDevice.current.name, detail: text("iOS 15 或更高版本", "iOS 15 or later"), icon: "iphone")
        }
      }
      .listStyle(InsetGroupedListStyle())
      .navigationTitle(text("设备", "Devices"))
    }
  }

  private var settings: some View {
    NavigationView {
      Form {
        Section(header: Text(text("智能体", "Agent"))) {
          Toggle(text("允许执行", "Allow execution"), isOn: $executionEnabled)
          Toggle(text("启用记忆", "Enable memory"), isOn: $memoryEnabled)
          HStack {
            Text(text("确认模式", "Confirmation mode"))
            Spacer()
            Text(text("每次询问", "Ask every time")).foregroundColor(.secondary)
          }
        }
        Section(header: Text(text("本地运行时", "On-device runtime"))) {
          HStack {
            Text(text("模型状态", "Model status"))
            Spacer()
            Text(text("未下载", "Not downloaded")).foregroundColor(.secondary)
          }
          HStack {
            Text(text("语言", "Language"))
            Spacer()
            Text(chinese ? "简体中文" : "English").foregroundColor(.secondary)
          }
        }
        Section {
          HStack {
            Image("SignalASILogo").resizable().scaledToFit().frame(width: 28, height: 28)
            VStack(alignment: .leading) {
              Text("SignalASI")
              Text(text("iOS 预览版 · iOS 15+", "iOS preview · iOS 15+"))
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
        }
      }
      .navigationTitle(text("设置", "Settings"))
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
