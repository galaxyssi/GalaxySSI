import SwiftUI

struct GalaxySSIContactDirectoryActionsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSIDirectoryMenuLink(
        title: t("galaxyssi.new_friends", "New Friends"),
        subtitle: newFriendsSubtitle,
        systemImage: "person.badge.plus",
        tint: .red,
        badge: pendingBadge
      ) {
        GalaxySSINewFriendsView()
      }
      GalaxySSIDirectoryDivider()
      GalaxySSIDirectoryMenuLink(
        title: t("galaxyssi.group_chats", "Group Chats"),
        subtitle: t("galaxyssi.group_feature_subtitle", "Secure multi-person communication, coming later"),
        systemImage: "person.3.fill",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.badge.planned", "Planned")
      ) {
        GalaxySSIGroupChatsView()
      }
      GalaxySSIDirectoryDivider()
      GalaxySSIDirectoryMenuLink(
        title: t("galaxyssi.my_agents", "My Agents"),
        subtitle: String(format: t("galaxyssi.agent_directory.count", "%d available agents"), agentCount),
        systemImage: "cpu",
        tint: .galaxySSIAccent,
        badge: "\(agentCount)"
      ) {
        GalaxySSIMyAgentsView()
      }
      GalaxySSIDirectoryDivider()
      GalaxySSIDirectoryMenuLink(
        title: t("galaxyssi.my_devices", "My Devices"),
        subtitle: deviceSubtitle,
        systemImage: "desktopcomputer",
        tint: .blue,
        badge: deviceCount > 0 ? "\(deviceCount)" : t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIDeviceContactsView()
      }
    }
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var pendingBadge: String {
    let count = store.unreadFriendRequestCount
    return count > 0 ? "\(count)" : t("galaxyssi.common.view", "View")
  }

  private var newFriendsSubtitle: String {
    let count = store.pendingFriendRequests.count
    guard count > 0 else {
      return t("galaxyssi.friend_request.empty_subtitle", "Scanned QR codes and incoming requests will appear here")
    }
    return String(format: t("galaxyssi.friend_request.pending_count", "%d pending requests"), count)
  }

  private var agentCount: Int {
    GalaxySSIAgentDirectorySnapshot(store: store, language: interfaceLanguage).items.count
  }

  private var deviceCount: Int {
    let deviceContacts = store.contactList(matching: "").filter { contact in
      contact.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device" ||
        contact.agentKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "device"
    }
    let representedDesktopIds = Set(deviceContacts.flatMap { contact in
      [contact.desktopId, contact.galaxySSIId].filter { !$0.isEmpty }
    })
    let unrepresentedPairedLinks = store.serverLinks.filter { link in
      link.paired && !representedDesktopIds.contains(link.desktopId)
    }
    return deviceContacts.count + unrepresentedPairedLinks.count
  }

  private var deviceSubtitle: String {
    guard deviceCount > 0 else {
      return t("galaxyssi.device.management_subtitle", "Secure connection between people, AI, and devices")
    }
    return String(format: t("galaxyssi.device.contacts_count", "%d devices"), deviceCount)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSINewFriendsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusText = ""
  @State private var statusIsError = false
  var onContactAccepted: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.new_friends", "New Friends"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if visibleRequests.isEmpty {
            GalaxySSIDirectoryHeroCard(
              title: t("galaxyssi.friend_request.empty_title", "No New Friends"),
              subtitle: t("galaxyssi.friend_request.empty_subtitle", "Scanned QR codes and incoming requests will appear here"),
              systemImage: "person.2",
              tint: .galaxySSITextSecondary,
              badge: t("galaxyssi.common.empty", "Empty")
            )
          } else {
            requestSection(
              title: t("galaxyssi.friend_request.received_section", "Requests Received"),
              requests: incomingRequests,
              allowsDecision: true
            )
            requestSection(
              title: t("galaxyssi.friend_request.sent_section", "Requests Sent"),
              requests: outgoingRequests,
              allowsDecision: false
            )
          }
          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 13))
              .foregroundColor(statusIsError ? .red : .galaxySSITextSecondary)
              .padding(.horizontal, 4)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      _ = store.markIncomingFriendRequestsRead()
    }
  }

  private var incomingRequests: [GalaxySSIFriendRequest] {
    visibleRequests.filter { $0.direction == .incoming }
  }

  private var outgoingRequests: [GalaxySSIFriendRequest] {
    visibleRequests.filter { $0.direction == .outgoing }
  }

  private var visibleRequests: [GalaxySSIFriendRequest] {
    store.visibleFriendRequests
  }

  @ViewBuilder
  private func requestSection(
    title: String,
    requests: [GalaxySSIFriendRequest],
    allowsDecision: Bool
  ) -> some View {
    if !requests.isEmpty {
      sectionTitle(title)
      VStack(spacing: 8) {
        ForEach(requests) { request in
          let added = isAdded(request)
          GalaxySSINewFriendCard(
            request: request,
            trailingTitle: allowsDecision
              ? t("friend_request_view", "View")
              : (added
                ? t("galaxyssi.friend_request.status_added", "Added")
                : t("galaxyssi.friend_request.waiting", "Waiting")),
            approveTitle: t("galaxyssi.friend_request.approve", "Approve"),
            rejectTitle: t("galaxyssi.friend_request.reject", "Reject"),
            allowsDecision: allowsDecision && request.status == .pending && !added,
            isAdded: added,
            onContactAccepted: onContactAccepted,
            onApprove: { approve(request) },
            onReject: { reject(request) }
          )
        }
      }
    }
  }

  private func approve(_ request: GalaxySSIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.galaxySSIId,
          approved: true
        )
        guard result.accepted else {
          statusText = t("galaxyssi.friend_request.decision_failed", "The contact decision could not be sent.")
          statusIsError = true
          return
        }
      }
      if store.approveFriendRequest(id: request.id) {
        await coordinator.recoverPhoneContactSessionIfNeeded(contactId: request.galaxySSIId)
        statusText = t("galaxyssi.friend_request.added_to_contacts", "Added to Contacts")
        statusIsError = false
        onContactAccepted()
      } else {
        statusText = t("galaxyssi.friend_request.not_found", "Friend request not found.")
        statusIsError = true
      }
    }
  }

  private func reject(_ request: GalaxySSIFriendRequest) {
    Task { @MainActor in
      if request.opaquePhoneRoutes != nil {
        let result = await coordinator.publishPhoneContactDecision(
          contactId: request.galaxySSIId,
          approved: false
        )
        guard result.accepted else {
          statusText = t("galaxyssi.friend_request.decision_failed", "The contact decision could not be sent.")
          statusIsError = true
          return
        }
      }
      if store.rejectFriendRequest(id: request.id) {
        statusText = t("galaxyssi.common.rejected", "Rejected")
        statusIsError = false
      } else {
        statusText = t("galaxyssi.friend_request.not_found", "Friend request not found.")
        statusIsError = true
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
  }

  private func isAdded(_ request: GalaxySSIFriendRequest) -> Bool {
    GalaxySSIFriendRequestPresentationPolicy.isAdded(
      request,
      contactIsVerified: store.contact(id: request.galaxySSIId)?.isCommunicable == true
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIGroupChatsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.group_feature.title", "Group Chats"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSIDirectoryHeroCard(
            title: t("galaxyssi.group_feature.title", "Group Chats"),
            subtitle: t("galaxyssi.group_feature_subtitle", "Secure multi-person communication, coming later"),
            systemImage: "person.3.fill",
            tint: .galaxySSIInsightText,
            badge: t("galaxyssi.badge.planned", "Planned")
          )
          sectionTitle(t("galaxyssi.section.current", "Current"))
          VStack(spacing: 8) {
            GalaxySSIDirectoryMenuLink(
              title: t("galaxyssi.discover.create_group_title", "Create Group"),
              subtitle: t("galaxyssi.discover.create_group_subtitle", "Secure multi-person communication"),
              systemImage: "person.3.fill",
              tint: .galaxySSIInsightText,
              badge: t("galaxyssi.common.next_step", "Next Step")
            ) {
              GalaxySSICreateGroupView()
            }
          }
          sectionTitle(t("galaxyssi.section.capabilities", "Capabilities"))
          VStack(spacing: 8) {
            GalaxySSIDirectoryInfoRow(
              title: t("galaxyssi.group.member_verification", "Member Verification"),
              subtitle: t("galaxyssi.group.member_verification_subtitle", "Each member must confirm fingerprints independently"),
              systemImage: "checkmark.shield",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.badge.designing", "Designing")
            )
            GalaxySSIDirectoryInfoRow(
              title: t("galaxyssi.group.message_encryption", "Group Message Encryption"),
              subtitle: t("galaxyssi.group.message_encryption_subtitle", "Group session keys and member state management"),
              systemImage: "lock.shield",
              tint: .galaxySSIInsightText,
              badge: t("galaxyssi.badge.designing", "Designing")
            )
          }
          NavigationLink(destination: GalaxySSICreateGroupView()) {
            Text(t("galaxyssi.discover.create_group_title", "Create Group"))
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 46)
              .background(Color.galaxySSIAccent)
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSICreateGroupView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.discover.create_group_title", "Create Group"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSIDirectoryHeroCard(
            title: t("galaxyssi.discover.create_group_title", "Create Group"),
            subtitle: t("galaxyssi.group.create_subtitle", "Select contacts first, then complete group identity verification"),
            systemImage: "person.3.fill",
            tint: .galaxySSIInsightText,
            badge: t("galaxyssi.badge.unavailable", "Unavailable")
          )
          sectionTitle(t("galaxyssi.section.flow", "Flow"))
          VStack(spacing: 8) {
            GalaxySSIDirectoryInfoRow(
              title: t("galaxyssi.group.select_members", "Select Members"),
              subtitle: t("galaxyssi.group.select_members_subtitle", "Choose from verified contacts"),
              systemImage: "person.2.fill",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.common.next_step", "Next Step")
            )
            GalaxySSIDirectoryInfoRow(
              title: t("galaxyssi.group.member_verification", "Member Verification"),
              subtitle: t("galaxyssi.group.member_verification_subtitle", "Each member must confirm fingerprints independently"),
              systemImage: "checkmark.shield",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.badge.designing", "Designing")
            )
            GalaxySSIDirectoryInfoRow(
              title: t("galaxyssi.group.create_session", "Create Session"),
              subtitle: t("galaxyssi.group.create_session_subtitle", "Generate group session keys and notify members"),
              systemImage: "key.fill",
              tint: .galaxySSIInsightText,
              badge: t("galaxyssi.badge.designing", "Designing")
            )
          }
          sectionTitle(t("galaxyssi.section.status", "Status"))
          GalaxySSIDirectoryInfoRow(
            title: t("galaxyssi.group.feature_status", "Group Feature"),
            subtitle: t("galaxyssi.group.feature_status_subtitle", "Group chat implementation is not enabled in this version"),
            systemImage: "person.3.fill",
            tint: .galaxySSITextSecondary,
            badge: t("galaxyssi.badge.planned", "Planned")
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMyAgentsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var selectedSegment = "all"

  private var snapshot: GalaxySSIAgentDirectorySnapshot {
    GalaxySSIAgentDirectorySnapshot(store: store, language: interfaceLanguage)
  }

  private var filteredItems: [GalaxySSIAgentDirectoryItem] {
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
      GalaxySSITopBar(
        title: t("galaxyssi.discover.ai_agent_title", "AI Agent"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSIDirectorySegmentedControl(
            segments: segmentOptions,
            selection: $selectedSegment
          )
          GalaxySSIDirectoryMenuLink(
            title: t("galaxyssi.discover.add_cloud_model", "Add Cloud Model"),
            subtitle: t(
              "galaxyssi.discover.add_cloud_model_subtitle",
              "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
            ),
            systemImage: "cloud.fill",
            tint: .galaxySSIInsightText,
            badge: "+"
          ) {
            CloudModelProviderSelectionView()
          }
          if hasTrustedDesktop {
            GalaxySSIDirectoryMenuLink(
              title: t("galaxyssi.agent_connection.scan_qr", "Scan or Paste Agent QR"),
              subtitle: t(
                "galaxyssi.agent_connection.scan_qr_subtitle",
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
            GalaxySSIDirectoryMenuLink(
              title: t("cc_no_desktop_title", "No trusted Desktop node"),
              subtitle: t("cc_no_desktop_subtitle", "Scan a GalaxySSI Desktop QR code to add its available Agents"),
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
                NavigationLink(destination: GalaxySSILocalModelLabView()) {
                  GalaxySSIAgentDirectoryRow(item: item)
                }
                .buttonStyle(.plain)
              } else if item.connected {
                NavigationLink(destination: ContactDetailView(contactId: item.contactId)) {
                  GalaxySSIAgentDirectoryRow(item: item)
                }
                .buttonStyle(.plain)
              } else {
                NavigationLink(destination: GalaxySSIAgentConnectionDetailView(item: item)) {
                  GalaxySSIAgentDirectoryRow(item: item)
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var hasTrustedDesktop: Bool {
    store.serverLinks.contains { $0.paired }
  }

  private var segmentOptions: [GalaxySSIDirectorySegment] {
    [
      GalaxySSIDirectorySegment(id: "all", title: t("galaxyssi.discover.segment_all", "All")),
      GalaxySSIDirectorySegment(id: "local", title: t("galaxyssi.discover.segment_local", "Local")),
      GalaxySSIDirectorySegment(id: "official", title: t("galaxyssi.discover.segment_official", "Official")),
      GalaxySSIDirectorySegment(id: "running", title: t("galaxyssi.discover.segment_running", "Running"))
    ]
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

@MainActor
private struct GalaxySSIAgentDirectorySnapshot {
  private let store: GalaxySSIStore
  private let language: String

  init(store: GalaxySSIStore, language: String) {
    self.store = store
    self.language = language
  }

  var items: [GalaxySSIAgentDirectoryItem] {
    coreItems + dynamicItems + plannedItems
  }

  private var coreItems: [GalaxySSIAgentDirectoryItem] {
    [
      coreItem(
        id: "hermes",
        fallbackTitle: "Hermes",
        subtitleKey: "galaxyssi.agent.private_assistant_subtitle",
        subtitleFallback: "Private AI assistant connected through the PC endpoint",
        systemImage: "sparkles",
        assetName: AgentAvatarStyle.hermes.androidParityAssetName,
        tint: .galaxySSIAccent,
        category: .official,
        fallbackStatus: connected("hermes") ? t("galaxyssi.status.running", "Running") : t("galaxyssi.status.pending_pairing", "Pending Pairing"),
        fallbackStatusKey: connected("hermes") ? "running" : "pending_pairing"
      ),
      coreItem(
        id: "codex",
        fallbackTitle: "Codex",
        subtitleKey: "galaxyssi.agent.codex_subtitle",
        subtitleFallback: "Local coding and engineering collaboration assistant",
        systemImage: "chevron.left.forwardslash.chevron.right",
        assetName: AgentAvatarStyle.codex.androidParityAssetName,
        tint: .galaxySSIInsightText,
        category: .official
      ),
      coreItem(
        id: "claude",
        fallbackTitle: "Claude Code",
        subtitleKey: "galaxyssi.agent.claude_subtitle",
        subtitleFallback: "Terminal collaboration and code editing assistant",
        systemImage: "terminal",
        assetName: AgentAvatarStyle.claude.androidParityAssetName,
        tint: .orange,
        category: .official
      ),
      coreItem(
        id: "openclaw",
        fallbackTitle: "OpenClaw",
        subtitleKey: "galaxyssi.agent.openclaw_subtitle",
        subtitleFallback: "Independent automation Agent through Desktop",
        systemImage: "bolt.horizontal",
        customAgentAvatar: true,
        tint: .blue,
        category: .official
      ),
      coreItem(
        id: "local-llm",
        fallbackTitle: "Local LLM",
        subtitleKey: "galaxyssi.agent.local_llm_subtitle",
        subtitleFallback: "Local model inference and task planning",
        systemImage: "memorychip",
        customAgentAvatar: true,
        tint: .teal,
        category: .local
      ),
      coreItem(
        id: "custom-agent",
        fallbackTitle: "Custom Agent",
        subtitleKey: "galaxyssi.agent.custom_subtitle",
        subtitleFallback: "Any CLI or MCP wrapper command",
        systemImage: "slider.horizontal.3",
        customAgentAvatar: true,
        tint: .gray,
        category: .local
      )
    ]
  }

  private var dynamicItems: [GalaxySSIAgentDirectoryItem] {
    let fixedIds: Set<String> = ["hermes", "codex", "claude", "openclaw", "local-llm", "custom-agent"]
    return store.contactList(matching: "")
      .filter { contact in
        !fixedIds.contains(contact.id) &&
          !fixedIds.contains(contact.galaxySSIId) &&
          isAgentContact(contact)
      }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
      .map(dynamicItem)
  }

  private var plannedItems: [GalaxySSIAgentDirectoryItem] {
    [
      GalaxySSIAgentDirectoryItem(
        id: "news_agent",
        contactId: "news_agent",
        title: "News Agent",
        subtitle: t("galaxyssi.agent.news_subtitle", "News collection and morning briefs"),
        systemImage: "newspaper",
        assetName: nil,
        tint: .orange,
        badge: t("galaxyssi.badge.automation", "Automation"),
        statusKey: "automation",
        connected: connected("news_agent"),
        category: .official
      ),
      GalaxySSIAgentDirectoryItem(
        id: "home_hub",
        contactId: "home_hub",
        title: "Home Agent",
        subtitle: t("galaxyssi.agent.home_subtitle", "Home device and smart home control"),
        systemImage: "house.fill",
        assetName: nil,
        tint: .gray,
        badge: t("galaxyssi.badge.device", "Device"),
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
    category: GalaxySSIAgentDirectoryCategory,
    fallbackStatus: String? = nil,
    fallbackStatusKey: String? = nil
  ) -> GalaxySSIAgentDirectoryItem {
    let contact = store.contact(id: id)
    let setupStatus = contact?.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let isConnected = connected(id)
    let badge = id == "local-llm"
      ? localModelStatusBadge()
      : statusBadge(setupStatus: setupStatus, connected: isConnected, fallback: fallbackStatus)
    let fallbackSubtitle = t(subtitleKey, subtitleFallback)
    return GalaxySSIAgentDirectoryItem(
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

  private func dynamicItem(_ contact: GalaxySSIContact) -> GalaxySSIAgentDirectoryItem {
    let setupStatus = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let badge = statusBadge(
      setupStatus: setupStatus,
      connected: connected(contact.id),
      fallback: t("galaxyssi.common.paired", "Paired")
    )
    return GalaxySSIAgentDirectoryItem(
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

  private func isAgentContact(_ contact: GalaxySSIContact) -> Bool {
    contact.id == "hermes" ||
      contact.type == "agent" ||
      contact.deliveryMode == .cloudAPI ||
      ["local-cli", "local-model", "cloud-model", "cloud-api", "custom-cli", "desktop-agent"].contains(contact.agentKind)
  }

  private func usesGenericAgentAvatar(_ contact: GalaxySSIContact) -> Bool {
    let agentID = contact.id.lowercased()
    let galaxySSIID = contact.galaxySSIId.lowercased()
    return [agentID, galaxySSIID].contains(where: { id in
      id == "openclaw" || id == "local-llm" || id == "custom-agent"
    }) || ["local-model", "cloud-model", "custom-cli"].contains(contact.agentKind.lowercased())
  }

  private func connectorDetail(_ contact: GalaxySSIContact, fallback: String) -> String {
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
        t("galaxyssi.local_model.runtime_unavailable", "Unavailable"),
        "unavailable"
      )
    }
    guard runtime.ready() else {
      return (
        t("galaxyssi.local_model.download_ready", "Needs model"),
        "needs_setup"
      )
    }
    return (t("galaxyssi.status.ready", "Ready"), "ready")
  }

  private func statusBadge(
    setupStatus: String,
    connected: Bool,
    fallback: String?
  ) -> (text: String, key: String) {
    switch setupStatus {
    case "ready":
      return (t("galaxyssi.status.ready", "Ready"), "ready")
    case "needs_setup", "needs-pairing", "needs_pairing":
      return (t("galaxyssi.status.needs_setup", "Needs Setup"), "needs_setup")
    case "pairing":
      return (t("galaxyssi.status.pending_pairing", "Pending Pairing"), "pending_pairing")
    default:
      if let fallback {
        return (fallback, connected ? "paired" : "pending_connection")
      }
      return connected
        ? (t("galaxyssi.common.paired", "Paired"), "paired")
        : (t("galaxyssi.status.pending_connection", "Pending Connection"), "pending_connection")
    }
  }

  private func statusTint(setupStatus: String, fallback: Color) -> Color {
    switch setupStatus {
    case "ready":
      return .galaxySSIAccent
    case "needs_setup", "needs-pairing", "needs_pairing", "pairing":
      return .orange
    default:
      return fallback
    }
  }

  private func agentKindSubtitle(_ kind: String) -> String {
    switch kind {
    case "local-cli":
      return t("galaxyssi.agent.connector_local_cli", "Desktop local command connector")
    case "local-model":
      return t("galaxyssi.agent.connector_local_model", "Desktop local model connector")
    case "cloud-model", "cloud-api":
      return t("galaxyssi.agent.connector_cloud_model", "Desktop cloud model connector")
    default:
      return t("galaxyssi.agent.connector_custom", "Desktop custom Agent connector")
    }
  }

  private func systemImage(for contact: GalaxySSIContact) -> String {
    if contact.deliveryMode == .cloudAPI || contact.agentKind == "cloud-api" || contact.agentKind == "cloud-model" {
      return "cloud.fill"
    }
    if contact.agentKind == "local-model" {
      return "memorychip"
    }
    return "cpu"
  }

  private func assetName(for contact: GalaxySSIContact) -> String? {
    let identityFields = [
      contact.id,
      contact.galaxySSIId,
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
      return GalaxySSIAgentAvatarAssetCatalog.cloudProviderAssetName(for: identityFields)
    }
    return GalaxySSIAgentAvatarAssetCatalog.assetName(for: identityFields)
  }

  private func tint(for contact: GalaxySSIContact) -> Color {
    if contact.deliveryMode == .cloudAPI || contact.agentKind == "cloud-api" || contact.agentKind == "cloud-model" {
      return .galaxySSIInsightText
    }
    if contact.agentKind == "local-model" {
      return .teal
    }
    return .galaxySSIAccent
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

enum GalaxySSIAgentDirectoryCategory {
  case local
  case official
}

struct GalaxySSIAgentDirectoryItem: Identifiable {
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
  var category: GalaxySSIAgentDirectoryCategory
}

private struct GalaxySSIDirectorySegment: Identifiable {
  var id: String
  var title: String
}

private struct GalaxySSIDirectorySegmentedControl: View {
  var segments: [GalaxySSIDirectorySegment]
  @Binding var selection: String

  var body: some View {
    HStack(spacing: 6) {
      ForEach(segments) { segment in
        Button {
          selection = segment.id
        } label: {
          Text(segment.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(selection == segment.id ? .white : .galaxySSITextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selection == segment.id ? Color.galaxySSIAccent : Color.galaxySSIButtonSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct GalaxySSIAgentDirectoryRow: View {
  var item: GalaxySSIAgentDirectoryItem

  var body: some View {
    HStack(spacing: 12) {
      GalaxySSIDirectoryIcon(
        systemImage: item.systemImage,
        assetName: item.assetName,
        customAgentAvatar: item.customAgentAvatar,
        tint: item.tint,
        size: 44
      )
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Text(item.subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
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
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSINewFriendCard: View {
  var request: GalaxySSIFriendRequest
  var trailingTitle: String
  var approveTitle: String
  var rejectTitle: String
  var allowsDecision: Bool
  var isAdded: Bool
  var onContactAccepted: () -> Void
  var onApprove: () -> Void
  var onReject: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        GalaxySSIDirectoryIcon(systemImage: "person.2.fill", tint: .galaxySSIAccent, size: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(request.name)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(request.galaxySSIId)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        NavigationLink(
          destination: FriendRequestDetailView(
            requestId: request.id,
            onContactAccepted: onContactAccepted
          )
        ) {
          Label(
            trailingTitle,
            systemImage: allowsDecision ? "eye" : (isAdded ? "checkmark.circle" : "clock")
          )
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(Color.galaxySSIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      Text(request.identityFingerprint.galaxySSIDirectoryFingerprint)
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if allowsDecision {
        HStack(spacing: 10) {
          Button(action: onApprove) {
            Label(approveTitle, systemImage: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(Color.galaxySSIAccent)
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
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIDirectoryMenuLink<Destination: View>: View {
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
      GalaxySSIDirectoryRowContent(
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

private struct GalaxySSIDirectoryInfoRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    GalaxySSIDirectoryRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct GalaxySSIDirectoryRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool = true

  var body: some View {
    HStack(spacing: 12) {
      GalaxySSIDirectoryIcon(systemImage: systemImage, tint: tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
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
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
  }
}

private struct GalaxySSIDirectoryHeroCard: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(spacing: 12) {
      GalaxySSIDirectoryIcon(systemImage: systemImage, tint: tint, size: 48)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextSecondary)
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
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIDirectoryIcon: View {
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

private struct GalaxySSIDirectoryDivider: View {
  var body: some View {
    Divider()
      .background(Color.galaxySSISeparator)
      .padding(.leading, 70)
  }
}

private extension String {
  var galaxySSIDirectoryFingerprint: String {
    String(filter { $0.isLetter || $0.isNumber }.prefix(64))
      .galaxySSIDirectoryChunked(into: 32)
      .joined(separator: "\n")
  }

  func galaxySSIDirectoryChunked(into size: Int) -> [String] {
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
