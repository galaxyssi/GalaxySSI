import SwiftUI
import UIKit
import UniformTypeIdentifiers

private func signalASIColor(light: UInt32, dark: UInt32) -> UIColor {
  UIColor { traits in
    signalASIColor(traits.userInterfaceStyle == .dark ? dark : light)
  }
}

private func signalASIColor(_ rgb: UInt32) -> UIColor {
  UIColor(
    red: CGFloat(Double((rgb >> 16) & 0xFF) / 255.0),
    green: CGFloat(Double((rgb >> 8) & 0xFF) / 255.0),
    blue: CGFloat(Double(rgb & 0xFF) / 255.0),
    alpha: 1.0
  )
}

extension Color {
  static var signalASIPageBackground: Color { Color(signalASIColor(light: 0xF6F7F8, dark: 0x15171B)) }
  static var signalASIBarBackground: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x202329)) }
  static var signalASISurface: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASISearchBackground: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x2B3038)) }
  static var signalASITextPrimary: Color { Color(signalASIColor(light: 0x111111, dark: 0xF2F4F7)) }
  static var signalASITextSecondary: Color { Color(signalASIColor(light: 0x8E8E93, dark: 0xA5ABB6)) }
  static var signalASIAgentSessionTitle: Color { Color(signalASIColor(light: 0x505052, dark: 0xCCD0D7)) }
  static var signalASIAccent: Color { Color(signalASIColor(light: 0x14C66A, dark: 0x19D36B)) }
  static var signalASISentBubble: Color { Color(signalASIColor(light: 0x95EC69, dark: 0x2E8B57)) }
  static var signalASIIncomingBubble: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASIButtonSoft: Color { Color(signalASIColor(light: 0xE9EAEC, dark: 0x363B44)) }
  static var signalASIInputStroke: Color { Color(signalASIColor(light: 0xC7C7CC, dark: 0x363B44)) }
  static var signalASIUnreadRed: Color { Color(signalASIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
  static var signalASISeparator: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x343841)) }
  static var signalASIInsightBackground: Color { Color(signalASIColor(light: 0xF2F6FE, dark: 0x202A36)) }
  static var signalASIInsightStroke: Color { Color(signalASIColor(light: 0xD8E6FB, dark: 0x34475C)) }
  static var signalASIInsightText: Color { Color(signalASIColor(light: 0x315B86, dark: 0xB8D5F2)) }
}

struct SignalASILogoView: View {
  var size: CGFloat
  var cornerRadius: CGFloat = 9

  var body: some View {
    Image("SignalASILogo")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct SignalASITopBar<Leading: View, Trailing: View>: View {
  var title: String
  let leading: Leading
  let trailing: Trailing

  init(
    title: String,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.leading = leading()
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 0) {
      leading
        .frame(width: 40, height: 56)
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .frame(maxWidth: .infinity, minHeight: 56)
      trailing
        .frame(width: 40, height: 56)
    }
    .padding(.horizontal, 16)
    .frame(height: 56)
    .background(Color.signalASIBarBackground)
  }
}

struct SignalASIBackButton: View {
  @Environment(\.presentationMode) private var presentationMode

  var body: some View {
    Button {
      presentationMode.wrappedValue.dismiss()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
    }
  }
}

struct SignalASIAndroidIconButton: View {
  var systemName: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 40, height: 40)
    }
    .buttonStyle(.plain)
  }
}

private extension View {
  func agentDeviceTouchTarget(_ policy: AgentDeviceInputTargetPolicy) -> some View {
    frame(
      minWidth: CGFloat(policy.minimumTouchTargetDp),
      minHeight: CGFloat(policy.minimumTouchTargetDp)
    )
    .contentShape(Rectangle())
  }
}

struct AgentHomeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [SignalASIDraftAttachment] = []
  @State private var fileImporterPresented = false
  @State private var photoPickerPresented = false
  @State private var attachmentError = ""
  @State private var selectedMessageForDetails: ChatMessage?

  private var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  private var messages: [ChatMessage] {
    store.messages(for: contact.id)
  }

  private var unreadTotal: Int {
    store.visibleContacts.reduce(0) { total, contact in
      total + store.conversationSummary(for: contact.id).unreadCount
    }
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        header
        agentOutput
        Divider()
          .background(Color.signalASISeparator)
        agentComposer
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .onAppear {
        store.markContactRead(contact.id)
      }
      .fileImporter(
        isPresented: $fileImporterPresented,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true
      ) { result in
        switch result {
        case .success(let urls):
          urls.forEach(addAttachment)
        case .failure(let error):
          attachmentError = error.localizedDescription
        }
      }
      .sheet(isPresented: $photoPickerPresented) {
        PhotoLibraryPickerView { attachment in
          appendAttachment(attachment)
        }
      }
      .sheet(item: $selectedMessageForDetails) { message in
        MessageDetailView(message: message, contact: contact)
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var agentOutput: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          if messages.isEmpty {
            AgentInsightBanner(unreadTotal: unreadTotal)
            AgentProcessCard()
            AgentInfoCard(
              currentApp: "SignalASI iOS",
              callableTargets: store.visibleContacts.count,
              runningTasks: 0
            )
          } else {
            ForEach(messages) { message in
              MessageBubble(message: message)
                .id(message.id)
                .contextMenu {
                  Button {
                    selectedMessageForDetails = message
                  } label: {
                    Label(t("signalasi.message.details", "Details"), systemImage: "info.circle")
                  }
                  Button {
                    UIPasteboard.general.string = message.content
                  } label: {
                    Label(t("signalasi.common.copy", "Copy"), systemImage: "doc.on.doc")
                  }
                  Button(role: .destructive) {
                    store.deleteMessage(message.id, contactId: contact.id)
                  } label: {
                    Label(t("signalasi.message.delete", "Delete Message"), systemImage: "trash")
                  }
                }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
      }
      .background(Color.signalASIPageBackground)
      .onChange(of: messages.count) { _ in
        if let last = messages.last {
          withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
        store.markContactRead(contact.id)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      SignalASILogoView(size: 39, cornerRadius: 8)
      VStack(alignment: .center, spacing: 2) {
        Text("SignalASI")
          .font(.system(size: 14.5, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Text(t("signalasi.agent.brand.subtitle", "Super Agent"))
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 4) {
        Text(t("signalasi.agent.session.new", "New session"))
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.signalASIAgentSessionTitle)
          .lineLimit(1)
        Text(unreadTotal > 0 ? String(format: t("signalasi.agent.unread", "%d unread"), unreadTotal) : t("signalasi.agent.tab.subtitle", "Phone-native super agent"))
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      .frame(width: 96, alignment: .trailing)
      NavigationLink(destination: OnDeviceAgentPermissionsView()) {
        Image(systemName: "cpu")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 36, height: 44)
      }
      .buttonStyle(.plain)
      NavigationLink(destination: SettingsView()) {
        Image(systemName: "ellipsis")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 36, height: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(height: 76)
    .background(Color.signalASIPageBackground)
  }

  private var agentComposer: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        AttachmentPreviewStrip(attachments: attachments) { attachment in
          attachments.removeAll { $0.id == attachment.id }
        }
      }
      if !attachmentError.isEmpty {
        Text(attachmentError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 4) {
        NavigationLink(destination: VoiceSettingsView()) {
          Text(t("signalasi.agent.voice_button", "Hold to Talk"))
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color(signalASIColor(0x087CFF)))
            .frame(width: 112, height: 54)
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .agentDeviceTouchTarget(deviceInputPolicy)

        HStack(spacing: 6) {
          TextField(t("signalasi.agent.goal_hint", "Type a message..."), text: $draft)
            .textInputAutocapitalization(.sentences)
            .lineLimit(1)
          Button {
            fileImporterPresented = true
          } label: {
            Image(systemName: "plus.circle")
              .font(.system(size: 21, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
          .agentDeviceTouchTarget(deviceInputPolicy)
          Button {
            photoPickerPresented = true
          } label: {
            Image(systemName: "photo")
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
          .agentDeviceTouchTarget(deviceInputPolicy)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        Button {
          sendAgentMessage()
        } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(canSend ? .white : .signalASITextSecondary)
            .frame(width: 54, height: 54)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(canSend ? Color.signalASIAccent : Color.signalASIButtonSoft)
            )
        }
        .buttonStyle(.plain)
        .agentDeviceTouchTarget(deviceInputPolicy)
        .disabled(!canSend)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
  }

  private func sendAgentMessage() {
    let text = draft
    let outgoingAttachments = attachments
    draft = ""
    attachments.removeAll()
    attachmentError = ""
    Task {
      await coordinator.send(text, to: contact, attachments: outgoingAttachments)
    }
  }

  private func addAttachment(url: URL) {
    do {
      let attachment = try SignalASIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
    } catch {
      attachmentError = error.localizedDescription
    }
  }

  private func appendAttachment(_ attachment: SignalASIDraftAttachment) {
    guard SignalASIAttachmentPayloadBuilder.accepted(attachment, existing: attachments) else {
      attachmentError = t("signalasi.attachment.limit", "Attachment limit reached or file is too large.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentProcessCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("signalasi.agent.section.process", "Process"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      AgentProcessStepRow(
        title: t("signalasi.agent.step.observe", "Read current screen structure"),
        status: t("signalasi.agent.step.current", "Current"),
        active: true
      )
      AgentProcessStepRow(
        title: t("signalasi.agent.step.analyze", "Analyze user goal"),
        status: t("signalasi.agent.step.waiting", "Waiting"),
        active: false
      )
      AgentProcessStepRow(
        title: t("signalasi.agent.step.plan", "Generate executable plan"),
        status: t("signalasi.agent.step.waiting", "Waiting"),
        active: false
      )
      AgentProcessStepRow(
        title: t("signalasi.agent.step.act", "Execute after confirmation"),
        status: t("signalasi.agent.step.safe", "Safe"),
        active: false
      )
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentProcessStepRow: View {
  var title: String
  var status: String
  var active: Bool

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(active ? Color.signalASIAccent : Color.signalASISeparator)
        .frame(width: 9, height: 9)
      Text(title)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
      Spacer(minLength: 8)
      Text(status)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(active ? .signalASIAccent : .signalASITextSecondary)
    }
  }
}

private struct AgentInfoCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var currentApp: String
  var callableTargets: Int
  var runningTasks: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("signalasi.agent.section.info", "Info"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      Text(String(format: t("signalasi.agent.current_app", "Current App: %@"), currentApp))
      Text(String(format: t("signalasi.agent.callable_targets", "Callable targets: %d"), callableTargets))
      Text(String(format: t("signalasi.agent.running_tasks", "Running tasks: %d"), runningTasks))
    }
    .font(.system(size: 13))
    .foregroundColor(.signalASIInsightText)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct DiscoverView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var myQRCodePresented = false

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.discover.title", "Discover"),
          leading: { Color.clear },
          trailing: { Color.clear }
        )
        ScrollView {
          VStack(spacing: 10) {
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.ai_agent_title", "AI Agent"),
              subtitle: t("signalasi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
              systemImage: "cpu",
              tint: .signalASIAccent
            ) {
              SignalASIMyAgentsView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.scan_title", "Scan"),
              subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              AddContactView(autoOpenScanner: true)
            }
            SignalASIAndroidMenuButton(
              title: t("signalasi.discover.my_qr_title", "My QR Code"),
              subtitle: t("signalasi.discover.my_qr_subtitle", "Show this device identity"),
              systemImage: "qrcode",
              tint: .signalASITextPrimary
            ) {
              myQRCodePresented = true
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.security_center_title", "Security Center"),
              subtitle: t("signalasi.discover.security_center_subtitle", "View security status and permissions"),
              systemImage: "checkmark.shield",
              tint: .signalASIAccent
            ) {
              SignalASISecurityCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_data_title", "Data & Backup"),
              subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
              systemImage: "externaldrive",
              tint: .signalASIInsightText
            ) {
              SignalASIDataBackupView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.pairing", "Pairing"),
              subtitle: t("signalasi.discover.pairing.subtitle", "Scan QR codes and connect SignalASI Desktop"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              PairingView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.voice", "Voice"),
              subtitle: t("signalasi.discover.voice.subtitle", "Wake, transcription and local voice models"),
              systemImage: "waveform",
              tint: .signalASIInsightText
            ) {
              VoiceSettingsView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.automation.title", "Automation"),
              subtitle: t("signalasi.automation.hero_subtitle", "Let AI actively handle fixed tasks"),
              systemImage: "clock",
              tint: .orange
            ) {
              SignalASIAutomationView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.lab_title", "Lab"),
              subtitle: t("signalasi.discover.lab_subtitle", "Explore frontier features"),
              systemImage: "sparkles",
              tint: .purple
            ) {
              SignalASILocalModelLabView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.device_center", "Device Center"),
              subtitle: t("signalasi.discover.device.subtitle", "Custom devices, Home Assistant and connectors"),
              systemImage: "antenna.radiowaves.left.and.right",
              tint: .signalASIAccent
            ) {
              DeviceManagementView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.model_planner", "Model Planner"),
              subtitle: t("signalasi.discover.planner.subtitle", "Agent planning, budget and model routing"),
              systemImage: "slider.horizontal.3",
              tint: .signalASIInsightText
            ) {
              AgentModelPlannerSettingsView()
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .sheet(isPresented: $myQRCodePresented) {
        MyContactQRCodeView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentInsightBanner: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var unreadTotal: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        SignalASILogoView(size: 34, cornerRadius: 7)
        VStack(alignment: .leading, spacing: 2) {
          Text("SignalASI Agent")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(
            unreadTotal > 0
              ? String(format: t("signalasi.agent.insight.unread", "You have %d unread agent messages."), unreadTotal)
              : t("signalasi.agent.insight.ready", "Native tool pipeline is ready.")
          )
            .font(.system(size: 12))
            .foregroundColor(.signalASIInsightText)
            .lineLimit(2)
        }
        Spacer()
      }
      HStack(spacing: 8) {
        AgentStatusChip(title: "iOS 15+", value: t("signalasi.status.ready", "Ready"))
        AgentStatusChip(title: t("signalasi.agent.safety", "Safety"), value: t("signalasi.status.on", "On"))
      }
    }
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentStatusChip: View {
  var title: String
  var value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .foregroundColor(.signalASITextSecondary)
      Text(value)
        .fontWeight(.bold)
        .foregroundColor(.signalASITextPrimary)
    }
    .font(.system(size: 11))
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIAndroidMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct SignalASIAndroidMenuButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
