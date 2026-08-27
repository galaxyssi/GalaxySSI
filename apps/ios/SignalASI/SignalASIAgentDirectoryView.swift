import SwiftUI

struct SignalASIContactDirectoryActionsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    VStack(spacing: 0) {
      SignalASIDirectoryMenuLink(
        title: t("signalasi.new_friends", "New Friends"),
        subtitle: newFriendsSubtitle,
        systemImage: "person.badge.plus",
        tint: .red,
        badge: pendingBadge
      ) {
        SignalASINewFriendsView()
      }
      SignalASIDirectoryDivider()
      SignalASIDirectoryMenuLink(
        title: t("signalasi.group_chats", "Group Chats"),
        subtitle: t("signalasi.group_feature_subtitle", "Secure multi-person communication, coming later"),
        systemImage: "person.3.fill",
        tint: .signalASIInsightText,
        badge: t("signalasi.badge.planned", "Planned")
      ) {
        SignalASIGroupChatsView()
      }
      SignalASIDirectoryDivider()
      SignalASIDirectoryMenuLink(
        title: t("signalasi.my_agents", "My Agents"),
        subtitle: String(format: t("signalasi.agent_directory.count", "%d available agents"), agentCount),
        systemImage: "cpu",
        tint: .signalASIAccent,
        badge: "\(agentCount)"
      ) {
        SignalASIMyAgentsView()
      }
      SignalASIDirectoryDivider()
      SignalASIDirectoryMenuLink(
        title: t("signalasi.my_devices", "My Devices"),
        subtitle: deviceSubtitle,
        systemImage: "desktopcomputer",
        tint: .blue,
        badge: deviceCount > 0 ? "\(deviceCount)" : t("signalasi.common.view", "View")
      ) {
        SignalASIDeviceContactsView()
      }
    }
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var pendingBadge: String {
    let count = store.unreadFriendRequestCount
    return count > 0 ? "\(count)" : t("signalasi.common.view", "View")
  }

  private var newFriendsSubtitle: String {
    let count = store.pendingFriendRequests.count
    guard count > 0 else {
      return t("signalasi.friend_request.empty_subtitle", "Scanned QR codes and incoming requests will appear here")
    }
    return String(format: t("signalasi.friend_request.pending_count", "%d pending requests"), count)
  }

  private var agentCount: Int {
    SignalASIAgentDirectorySnapshot(store: store, language: interfaceLanguage).items.count
  }

  private var deviceCount: Int {
    let deviceContacts = store.contactList(matching: "").filter { contact in
      contact.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device" ||
        contact.agentKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device"
    }
    let representedDesktopIds = Set(deviceContacts.flatMap { contact in
      [contact.desktopId, contact.signalASIId].filter { !$0.isEmpty }
    })
    let unrepresentedPairedLinks = store.serverLinks.filter { link in
      link.paired && !representedDesktopIds.contains(link.desktopId)
    }
    return deviceContacts.count + unrepresentedPairedLinks.count
  }

  private var deviceSubtitle: String {
    guard deviceCount > 0 else {
      return t("signalasi.device.management_subtitle", "Secure connection between people, AI, and devices")
    }
    return String(format: t("signalasi.device.contacts_count", "%d devices"), deviceCount)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASINewFriendsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusText = ""
  @State private var statusIsError = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.new_friends", "New Friends"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if store.pendingFriendRequests.isEmpty {
            SignalASIDirectoryHeroCard(
              title: t("signalasi.friend_request.empty_title", "No New Friends"),
              subtitle: t("signalasi.friend_request.empty_subtitle", "Scanned QR codes and incoming requests will appear here"),
              systemImage: "person.2",
              tint: .signalASITextSecondary,
              badge: t("signalasi.common.empty", "Empty")
            )
          } else {
            requestSection(
              title: t("signalasi.friend_request.received_section", "Requests Received"),
              requests: incomingRequests,
              allowsDecision: true
            )
            requestSection(
              title: t("signalasi.friend_request.sent_section", "Requests Sent"),
              requests: outgoingRequests,
              allowsDecision: false
            )
          }
          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 13))
              .foregroundColor(statusIsError ? .red : .signalASITextSecondary)
              .padding(.horizontal, 4)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      _ = store.markIncomingFriendRequestsRead()
    }
  }

  private var incomingRequests: [SignalASIFriendRequest] {
    store.pendingFriendRequests.filter { $0.direction == .incoming }
  }

  private var outgoingRequests: [SignalASIFriendRequest] {
    store.pendingFriendRequests.filter { $0.direction == .outgoing }
  }

  @ViewBuilder
  private func requestSection(
    title: String,
    requests: [SignalASIFriendRequest],
    allowsDecision: Bool
  ) -> some View {
    if !requests.isEmpty {
      sectionTitle(title)
      VStack(spacing: 8) {
        ForEach(requests) { request in
          SignalASINewFriendCard(
            request: request,
            trailingTitle: allowsDecision
              ? t("friend_request_view", "View")
              : t("signalasi.friend_request.waiting", "Waiting"),
            approveTitle: t("signalasi.friend_request.approve", "Approve"),
            rejectTitle: t("signalasi.friend_request.reject", "Reject"),
            allowsDecision: allowsDecision,
            onApprove: { approve(request) },
            onReject: { reject(request) }
          )
        }
      }
    }
  }

  private func approve(_ request: SignalASIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.signalASIId,
          approved: true
        )
        guard result.accepted else {
          statusText = t("signalasi.friend_request.decision_failed", "The contact decision could not be sent.")
          statusIsError = true
          return
        }
      }
      if store.approveFriendRequest(id: request.id) {
        await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.signalASIId)
        statusText = t("signalasi.friend_request.added_to_contacts", "Added to Contacts")
        statusIsError = false
      } else {
        statusText = t("signalasi.friend_request.not_found", "Friend request not found.")
        statusIsError = true
      }
    }
  }

  private func reject(_ request: SignalASIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.signalASIId,
          approved: false
        )
        guard result.accepted else {
          statusText = t("signalasi.friend_request.decision_failed", "The contact decision could not be sent.")
          statusIsError = true
          return
        }
      }
      if store.rejectFriendRequest(id: request.id) {
        statusText = t("signalasi.common.rejected", "Rejected")
        statusIsError = false
      } else {
        statusText = t("signalasi.friend_request.not_found", "Friend request not found.")
        statusIsError = true
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIGroupChatsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.group_feature.title", "Group Chats"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIDirectoryHeroCard(
            title: t("signalasi.group_feature.title", "Group Chats"),
            subtitle: t("signalasi.group_feature_subtitle", "Secure multi-person communication, coming later"),
            systemImage: "person.3.fill",
            tint: .signalASIInsightText,
            badge: t("signalasi.badge.planned", "Planned")
          )
          sectionTitle(t("signalasi.section.current", "Current"))
          VStack(spacing: 8) {
            SignalASIDirectoryMenuLink(
              title: t("signalasi.discover.create_group_title", "Create Group"),
              subtitle: t("signalasi.discover.create_group_subtitle", "Secure multi-person communication"),
              systemImage: "person.3.fill",
              tint: .signalASIInsightText,
              badge: t("signalasi.common.next_step", "Next Step")
            ) {
              SignalASICreateGroupView()
            }
          }
          sectionTitle(t("signalasi.section.capabilities", "Capabilities"))
          VStack(spacing: 8) {
            SignalASIDirectoryInfoRow(
              title: t("signalasi.group.member_verification", "Member Verification"),
              subtitle: t("signalasi.group.member_verification_subtitle", "Each member must confirm fingerprints independently"),
              systemImage: "checkmark.shield",
              tint: .signalASIAccent,
              badge: t("signalasi.badge.designing", "Designing")
            )
            SignalASIDirectoryInfoRow(
              title: t("signalasi.group.message_encryption", "Group Message Encryption"),
              subtitle: t("signalasi.group.message_encryption_subtitle", "Group session keys and member state management"),
              systemImage: "lock.shield",
              tint: .signalASIInsightText,
              badge: t("signalasi.badge.designing", "Designing")
            )
          }
          NavigationLink(destination: SignalASICreateGroupView()) {
            Text(t("signalasi.discover.create_group_title", "Create Group"))
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 46)
              .background(Color.signalASIAccent)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASICreateGroupView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.discover.create_group_title", "Create Group"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIDirectoryHeroCard(
            title: t("signalasi.discover.create_group_title", "Create Group"),
            subtitle: t("signalasi.group.create_subtitle", "Select contacts first, then complete group identity verification"),
            systemImage: "person.3.fill",
            tint: .signalASIInsightText,
            badge: t("signalasi.badge.unavailable", "Unavailable")
          )
          sectionTitle(t("signalasi.section.flow", "Flow"))
          VStack(spacing: 8) {
            SignalASIDirectoryInfoRow(
              title: t("signalasi.group.select_members", "Select Members"),
              subtitle: t("signalasi.group.select_members_subtitle", "Choose from verified contacts"),
              systemImage: "person.2.fill",
              tint: .signalASIAccent,
              badge: t("signalasi.common.next_step", "Next Step")
            )
            SignalASIDirectoryInfoRow(
              title: t("signalasi.group.member_verification", "Member Verification"),
              subtitle: t("signalasi.group.member_verification_subtitle", "Each member must confirm fingerprints independently"),
              systemImage: "checkmark.shield",
              tint: .signalASIAccent,
              badge: t("signalasi.badge.designing", "Designing")
            )
            SignalASIDirectoryInfoRow(
              title: t("signalasi.group.create_session", "Create Session"),
              subtitle: t("signalasi.group.create_session_subtitle", "Generate group session keys and notify members"),
              systemImage: "key.fill",
              tint: .signalASIInsightText,
              badge: t("signalasi.badge.designing", "Designing")
            )
          }
          sectionTitle(t("signalasi.section.status", "Status"))
          SignalASIDirectoryInfoRow(
            title: t("signalasi.group.feature_status", "Group Feature"),
            subtitle: t("signalasi.group.feature_status_subtitle", "Group chat implementation is not enabled in this version"),
            systemImage: "person.3.fill",
            tint: .signalASITextSecondary,
            badge: t("signalasi.badge.planned", "Planned")
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMyAgentsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedSegment = "all"

  private var snapshot: SignalASIAgentDirectorySnapshot {
    SignalASIAgentDirectorySnapshot(store: store, language: interfaceLanguage)
  }

  private var filteredItems: [SignalASIAgentDirectoryItem] {
    switch selectedSegment {
    case "local":
      return snapshot.items.filter { $0.category == .local }
    case "official":
      return snapshot.items.filter { $0.category == .official }
    case "running":
      return snapshot.items.filter { $0.connected || $0.statusKey == "ready" || $0.statusKey == "running" }
    default:
      return snapshot.items
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.discover.ai_agent_title", "AI Agent"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIDirectorySegmentedControl(
            segments: segmentOptions,
            selection: $selectedSegment
          )
          SignalASIDirectoryMenuLink(
            title: t("signalasi.discover.add_cloud_model", "Add Cloud Model"),
            subtitle: t(
              "signalasi.discover.add_cloud_model_subtitle",
              "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
            ),
            systemImage: "cloud.fill",
            tint: .signalASIInsightText,
            badge: "+"
          ) {
            CloudModelProviderSelectionView()
          }
          if hasTrustedDesktop {
            SignalASIDirectoryMenuLink(
              title: t("signalasi.agent_connection.scan_qr", "Scan or Paste Agent QR"),
              subtitle: t(
                "signalasi.agent_connection.scan_qr_subtitle",
                "Pair Codex, Claude Code, local models, or desktop Agents with the Android-compatible QR flow"
              ),
              systemImage: "qrcode.viewfinder",
              tint: .orange,
              badge: t("security_scan", "Scan")
            ) {
              AddContactView(autoOpenScanner: true)
            }
          }
          if !hasTrustedDesktop {
            SignalASIDirectoryMenuLink(
              title: t("cc_no_desktop_title", "No trusted Desktop node"),
              subtitle: t("cc_no_desktop_subtitle", "Scan a SignalASI Desktop QR code to add its available Agents"),
              systemImage: "qrcode.viewfinder",
              tint: .orange,
              badge: t("security_scan", "Scan")
            ) {
              AddContactView(autoOpenScanner: true)
            }
          }
          VStack(spacing: 8) {
            ForEach(filteredItems) { item in
              if item.id == "local-llm" {
                NavigationLink(destination: SignalASILocalModelLabView()) {
                  SignalASIAgentDirectoryRow(item: item)
                }
                .buttonStyle(.plain)
              } else if item.connected {
                NavigationLink(destination: ContactDetailView(contactId: item.contactId)) {
                  SignalASIAgentDirectoryRow(item: item)
                }
                .buttonStyle(.plain)
              } else {
                NavigationLink(destination: SignalASIAgentConnectionDetailView(item: item)) {
                  SignalASIAgentDirectoryRow(item: item)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var hasTrustedDesktop: Bool {
    store.serverLinks.contains { $0.paired }
  }

  private var segmentOptions: [SignalASIDirectorySegment] {
    [
      SignalASIDirectorySegment(id: "all", title: t("signalasi.discover.segment_all", "All")),
      SignalASIDirectorySegment(id: "local", title: t("signalasi.discover.segment_local", "Local")),
      SignalASIDirectorySegment(id: "official", title: t("signalasi.discover.segment_official", "Official")),
      SignalASIDirectorySegment(id: "running", title: t("signalasi.discover.segment_running", "Running"))
    ]
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

@MainActor
private struct SignalASIAgentDirectorySnapshot {
  private let store: SignalASIStore
  private let language: String

  init(store: SignalASIStore, language: String) {
    self.store = store
    self.language = language
  }

  var items: [SignalASIAgentDirectoryItem] {
    coreItems + dynamicItems + plannedItems
  }

  private var coreItems: [SignalASIAgentDirectoryItem] {
    [
      coreItem(
        id: "hermes",
        fallbackTitle: "Hermes",
        subtitleKey: "signalasi.agent.private_assistant_subtitle",
        subtitleFallback: "Private AI assistant connected through the PC endpoint",
        systemImage: "sparkles",
        assetName: AgentAvatarStyle.hermes.androidParityAssetName,
        tint: .signalASIAccent,
        category: .official,
        fallbackStatus: connected("hermes") ? t("signalasi.status.running", "Running") : t("signalasi.status.pending_pairing", "Pending Pairing"),
        fallbackStatusKey: connected("hermes") ? "running" : "pending_pairing"
      ),
      coreItem(
        id: "codex",
        fallbackTitle: "Codex",
        subtitleKey: "signalasi.agent.codex_subtitle",
        subtitleFallback: "Local coding and engineering collaboration assistant",
        systemImage: "chevron.left.forwardslash.chevron.right",
        assetName: AgentAvatarStyle.codex.androidParityAssetName,
        tint: .signalASIInsightText,
        category: .official
      ),
      coreItem(
        id: "claude",
        fallbackTitle: "Claude Code",
        subtitleKey: "signalasi.agent.claude_subtitle",
        subtitleFallback: "Terminal collaboration and code editing assistant",
        systemImage: "terminal",
        assetName: AgentAvatarStyle.claude.androidParityAssetName,
        tint: .orange,
        category: .official
      ),
      coreItem(
        id: "openclaw",
        fallbackTitle: "OpenClaw",
        subtitleKey: "signalasi.agent.openclaw_subtitle",
        subtitleFallback: "Independent automation Agent through Desktop",
        systemImage: "bolt.horizontal",
        customAgentAvatar: true,
        tint: .blue,
        category: .official
      ),
      coreItem(
        id: "local-llm",
        fallbackTitle: "Local LLM",
        subtitleKey: "signalasi.agent.local_llm_subtitle",
        subtitleFallback: "Local model inference and task planning",
        systemImage: "memorychip",
        customAgentAvatar: true,
        tint: .teal,
        category: .local
      ),
      coreItem(
        id: "custom-agent",
        fallbackTitle: "Custom Agent",
        subtitleKey: "signalasi.agent.custom_subtitle",
        subtitleFallback: "Any CLI or MCP wrapper command",
        systemImage: "slider.horizontal.3",
        customAgentAvatar: true,
        tint: .gray,
        category: .local
      )
    ]
  }

  private var dynamicItems: [SignalASIAgentDirectoryItem] {
    let fixedIds: Set<String> = ["hermes", "codex", "claude", "openclaw", "local-llm", "custom-agent"]
    return store.contactList(matching: "")
      .filter { contact in
        !fixedIds.contains(contact.id) &&
          !fixedIds.contains(contact.signalASIId) &&
          isAgentContact(contact)
      }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
      .map(dynamicItem)
  }

  private var plannedItems: [SignalASIAgentDirectoryItem] {
    [
      SignalASIAgentDirectoryItem(
        id: "news_agent",
        contactId: "news_agent",
        title: "News Agent",
        subtitle: t("signalasi.agent.news_subtitle", "News collection and morning briefs"),
        systemImage: "newspaper",
        assetName: nil,
        tint: .orange,
        badge: t("signalasi.badge.automation", "Automation"),
        statusKey: "automation",
        connected: connected("news_agent"),
        category: .official
      ),
      SignalASIAgentDirectoryItem(
        id: "home_hub",
        contactId: "home_hub",
        title: "Home Agent",
        subtitle: t("signalasi.agent.home_subtitle", "Home device and smart home control"),
        systemImage: "house.fill",
        assetName: nil,
        tint: .gray,
        badge: t("signalasi.badge.device", "Device"),
        statusKey: "device",
        connected: connected("home_hub"),
        category: .official
      )
    ]
  }

  private func coreItem(
    id: String,
    fallbackTitle: String,
    subtitleKey: String,
    subtitleFallback: String,
    systemImage: String,
    assetName: String? = nil,
    customAgentAvatar: Bool = false,
    tint: Color,
    category: SignalASIAgentDirectoryCategory,
    fallbackStatus: String? = nil,
    fallbackStatusKey: String? = nil
  ) -> SignalASIAgentDirectoryItem {
    let contact = store.contact(id: id)
    let setupStatus = contact?.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let isConnected = connected(id)
    let badge = id == "local-llm"
      ? localModelStatusBadge()
      : statusBadge(setupStatus: setupStatus, connected: isConnected, fallback: fallbackStatus)
    let fallbackSubtitle = t(subtitleKey, subtitleFallback)
    return SignalASIAgentDirectoryItem(
      id: id,
      contactId: contact?.id ?? id,
      title: contact?.displayName.ifBlank(fallbackTitle) ?? fallbackTitle,
      subtitle: contact.map { connectorDetail($0, fallback: fallbackSubtitle) } ?? fallbackSubtitle,
      systemImage: systemImage,
      assetName: assetName,
      customAgentAvatar: customAgentAvatar,
      tint: statusTint(setupStatus: setupStatus, fallback: tint),
      badge: badge.text,
      statusKey: fallbackStatusKey ?? badge.key,
      connected: isConnected,
      category: category
    )
  }

  private func dynamicItem(_ contact: SignalASIContact) -> SignalASIAgentDirectoryItem {
    let setupStatus = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let badge = statusBadge(
      setupStatus: setupStatus,
      connected: connected(contact.id),
      fallback: t("signalasi.common.paired", "Paired")
    )
    return SignalASIAgentDirectoryItem(
      id: contact.id,
      contactId: contact.id,
      title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
      subtitle: connectorDetail(contact, fallback: agentKindSubtitle(contact.agentKind)),
      systemImage: systemImage(for: contact),
      assetName: assetName(for: contact),
      customAgentAvatar: usesGenericAgentAvatar(contact),
      tint: statusTint(setupStatus: setupStatus, fallback: tint(for: contact)),
      badge: badge.text,
      statusKey: badge.key,
      connected: connected(contact.id),
      category: contact.deliveryMode == .cloudAPI ? .official : .local
    )
  }

  private func isAgentContact(_ contact: SignalASIContact) -> Bool {
    contact.id == "hermes" ||
      contact.type == "agent" ||
      contact.deliveryMode == .cloudAPI ||
      ["local-cli", "local-model", "cloud-model", "cloud-api", "custom-cli", "desktop-agent"].contains(contact.agentKind)
  }

  private func usesGenericAgentAvatar(_ contact: SignalASIContact) -> Bool {
    let agentID = contact.id.lowercased()
    let signalASIID = contact.signalASIId.lowercased()
    return [agentID, signalASIID].contains(where: { id in
      id == "openclaw" || id == "local-llm" || id == "custom-agent"
    }) || ["local-model", "cloud-model", "custom-cli"].contains(contact.agentKind.lowercased())
  }

  private func connectorDetail(_ contact: SignalASIContact, fallback: String) -> String {
    contact.setupDetail
      .ifBlank(contact.connectorSetupNextStep)
      .ifBlank(fallback)
  }

  private func connected(_ id: String) -> Bool {
    guard let contact = store.contact(id: id), !contact.deleted, contact.trustState != .deleted else {
      return false
    }
    return contact.trustState == .verified ||
      contact.setupStatus == "ready" ||
      contact.deliveryMode == .cloudAPI
  }

  private func localModelStatusBadge() -> (text: String, key: String) {
    let runtime = LocalModelInferenceRuntime.shared
    guard runtime.available else {
      return (
        t("signalasi.local_model.runtime_unavailable", "Unavailable"),
        "unavailable"
      )
    }
    guard runtime.ready() else {
      return (
        t("signalasi.local_model.download_ready", "Needs model"),
        "needs_setup"
      )
    }
    return (t("signalasi.status.ready", "Ready"), "ready")
  }

  private func statusBadge(
    setupStatus: String,
    connected: Bool,
    fallback: String?
  ) -> (text: String, key: String) {
    switch setupStatus {
    case "ready":
      return (t("signalasi.status.ready", "Ready"), "ready")
    case "needs_setup", "needs-pairing", "needs_pairing":
      return (t("signalasi.status.needs_setup", "Needs Setup"), "needs_setup")
    case "pairing":
      return (t("signalasi.status.pending_pairing", "Pending Pairing"), "pending_pairing")
    default:
      if let fallback {
        return (fallback, connected ? "paired" : "pending_connection")
      }
      return connected
        ? (t("signalasi.common.paired", "Paired"), "paired")
        : (t("signalasi.status.pending_connection", "Pending Connection"), "pending_connection")
    }
  }

  private func statusTint(setupStatus: String, fallback: Color) -> Color {
    switch setupStatus {
    case "ready":
      return .signalASIAccent
    case "needs_setup", "needs-pairing", "needs_pairing", "pairing":
      return .orange
    default:
      return fallback
    }
  }

  private func agentKindSubtitle(_ kind: String) -> String {
    switch kind {
    case "local-cli":
      return t("signalasi.agent.connector_local_cli", "Desktop local command connector")
    case "local-model":
      return t("signalasi.agent.connector_local_model", "Desktop local model connector")
    case "cloud-model", "cloud-api":
      return t("signalasi.agent.connector_cloud_model", "Desktop cloud model connector")
    default:
      return t("signalasi.agent.connector_custom", "Desktop custom Agent connector")
    }
  }

  private func systemImage(for contact: SignalASIContact) -> String {
    if contact.deliveryMode == .cloudAPI || contact.agentKind == "cloud-api" || contact.agentKind == "cloud-model" {
      return "cloud.fill"
    }
    if contact.agentKind == "local-model" {
      return "memorychip"
    }
    return "cpu"
  }

  private func assetName(for contact: SignalASIContact) -> String? {
    let identityFields = [
      contact.id,
      contact.signalASIId,
      contact.name,
      contact.displayName,
      contact.type,
      contact.agentKind
    ] + [
      contact.cloudProvider,
      contact.selectedCloudModel?.provider ?? "",
      contact.selectedCloudModel?.modelId ?? ""
    ]
    if contact.deliveryMode == .cloudAPI {
      return SignalASIAgentAvatarAssetCatalog.cloudProviderAssetName(for: identityFields)
    }
    return SignalASIAgentAvatarAssetCatalog.assetName(for: identityFields)
  }

  private func tint(for contact: SignalASIContact) -> Color {
    if contact.deliveryMode == .cloudAPI || contact.agentKind == "cloud-api" || contact.agentKind == "cloud-model" {
      return .signalASIInsightText
    }
    if contact.agentKind == "local-model" {
      return .teal
    }
    return .signalASIAccent
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: language)
  }
}

enum SignalASIAgentDirectoryCategory {
  case local
  case official
}

struct SignalASIAgentDirectoryItem: Identifiable {
  var id: String
  var contactId: String
  var title: String
  var subtitle: String
  var systemImage: String
  var assetName: String? = nil
  var customAgentAvatar: Bool = false
  var tint: Color
  var badge: String
  var statusKey: String
  var connected: Bool
  var category: SignalASIAgentDirectoryCategory
}

private struct SignalASIDirectorySegment: Identifiable {
  var id: String
  var title: String
}

private struct SignalASIDirectorySegmentedControl: View {
  var segments: [SignalASIDirectorySegment]
  @Binding var selection: String

  var body: some View {
    HStack(spacing: 6) {
      ForEach(segments) { segment in
        Button {
          selection = segment.id
        } label: {
          Text(segment.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(selection == segment.id ? .white : .signalASITextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selection == segment.id ? Color.signalASIAccent : Color.signalASIButtonSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct SignalASIAgentDirectoryRow: View {
  var item: SignalASIAgentDirectoryItem

  var body: some View {
    HStack(spacing: 12) {
      SignalASIDirectoryIcon(
        systemImage: item.systemImage,
        assetName: item.assetName,
        customAgentAvatar: item.customAgentAvatar,
        tint: item.tint,
        size: 44
      )
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Text(item.subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(item.badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(item.tint)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .frame(width: 68, height: 34)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASINewFriendCard: View {
  var request: SignalASIFriendRequest
  var trailingTitle: String
  var approveTitle: String
  var rejectTitle: String
  var allowsDecision: Bool
  var onApprove: () -> Void
  var onReject: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        SignalASIDirectoryIcon(systemImage: "person.2.fill", tint: .signalASIAccent, size: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(request.name)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(request.signalASIId)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        NavigationLink(destination: FriendRequestDetailView(requestId: request.id)) {
          Label(trailingTitle, systemImage: allowsDecision ? "eye" : "clock")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(Color.signalASIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      Text(request.identityFingerprint.signalASIDirectoryFingerprint)
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if allowsDecision {
        HStack(spacing: 10) {
          Button(action: onApprove) {
            Label(approveTitle, systemImage: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(Color.signalASIAccent)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          Button(action: onReject) {
            Label(rejectTitle, systemImage: "xmark.circle")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.red)
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIDirectoryMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      SignalASIDirectoryRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge
      )
    }
    .buttonStyle(.plain)
  }
}

private struct SignalASIDirectoryInfoRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    SignalASIDirectoryRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct SignalASIDirectoryRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool = true

  var body: some View {
    HStack(spacing: 12) {
      SignalASIDirectoryIcon(systemImage: systemImage, tint: tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
  }
}

private struct SignalASIDirectoryHeroCard: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(spacing: 12) {
      SignalASIDirectoryIcon(systemImage: systemImage, tint: tint, size: 48)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIDirectoryIcon: View {
  var systemImage: String
  var assetName: String? = nil
  var customAgentAvatar = false
  var tint: Color
  var size: CGFloat = 38

  var body: some View {
    ZStack {
      if customAgentAvatar && assetName == nil {
        Circle()
          .fill(Color(red: 0.424, green: 0.478, blue: 0.537))
        Image(systemName: "cube.transparent")
          .font(.system(size: size * 0.54, weight: .semibold))
          .foregroundColor(.white)
        Image(systemName: "person.fill")
          .font(.system(size: size * 0.22, weight: .bold))
          .foregroundColor(.white)
          .offset(y: size * 0.06)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
      }
      if let assetName {
        Image(assetName)
          .resizable()
          .scaledToFill()
          .accessibilityHidden(true)
      } else if !customAgentAvatar {
        Image(systemName: systemImage)
          .font(.system(size: size >= 44 ? 18 : 16, weight: .semibold))
          .foregroundColor(tint)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIDirectoryDivider: View {
  var body: some View {
    Divider()
      .background(Color.signalASISeparator)
      .padding(.leading, 70)
  }
}

private extension String {
  var signalASIDirectoryFingerprint: String {
    String(filter { $0.isLetter || $0.isNumber }.prefix(64))
      .signalASIDirectoryChunked(into: 32)
      .joined(separator: "\n")
  }

  func signalASIDirectoryChunked(into size: Int) -> [String] {
    var chunks: [String] = []
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(String(self[index..<next]))
      index = next
    }
    return chunks
  }
}
