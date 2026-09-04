import SwiftUI

struct GalaxySSIPrivacyControlCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  private let disclosureStore: AgentDataDisclosureStore
  @State private var records: [AgentDataDisclosureRecord] = []
  @State private var blockedDestinationIds: Set<String> = []

  init(
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    )
  ) {
    self.disclosureStore = disclosureStore
  }

  private var summary: AgentDataDisclosureSummary {
    AgentDataDisclosureLedger.summary(records)
  }

  private var destinations: [GalaxySSIPrivacyDestinationSummary] {
    GalaxySSIPrivacyDestinationSummary.build(
      records: records,
      blockedDestinationIds: blockedDestinationIds,
      cloudContacts: store.cloudModelContacts,
      serverLinks: store.serverLinks
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
            subtitle: t("cc_privacy_dashboard_hero_subtitle", "A metadata-only audit of data sent to cloud models and trusted Desktop Agents"),
            systemImage: "checkmark.shield",
            tint: .galaxySSIAccent,
            badge: t("cc_privacy_metadata_only", "No prompt content stored")
          )
          metricsStrip
          localBanner
          boundarySection
          destinationSection
          recentSection
          if !records.isEmpty {
            historySection
          }
          footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
  }

  private var metricsStrip: some View {
    HStack(spacing: 8) {
      GalaxySSIPrivacyMetric(value: "\(summary.total)", label: t("cc_privacy_metric_events", "Recent flows"), tint: .blue)
      GalaxySSIPrivacyMetric(value: "\(summary.destinations)", label: t("cc_privacy_metric_destinations", "Destinations"), tint: .galaxySSIInsightText)
      GalaxySSIPrivacyMetric(value: "\(summary.cloud)", label: t("cc_privacy_metric_cloud", "Cloud flows"), tint: summary.cloud > 0 ? .orange : .galaxySSIAccent)
    }
  }

  private var localBanner: some View {
    GalaxySSISecurityHeroView(
      title: t("cc_privacy_local_title", "On-device work stays on this iPhone"),
      subtitle: t("cc_privacy_local_subtitle", "Local tools and on-device models are not listed as external disclosures"),
      systemImage: "iphone",
      tint: .galaxySSIAccent,
      badge: String(format: t("cc_privacy_blocked_count", "%d blocked"), summary.blocked)
    )
  }

  private var boundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_privacy_boundary", "Privacy Boundary"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_privacy_planner_title", "Model Planning Data"),
        subtitle: t("cc_privacy_planner_subtitle", "Review whether screen text and Agent output may enter model planning"),
        systemImage: "cpu",
        tint: .blue,
        badge: t("cc_privacy_review", "Review")
      ) {
        AgentModelPlannerSettingsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_permissions_title", "Permissions & Audit"),
        subtitle: t("cc_privacy_permissions_subtitle_ios", "Review iOS access and remembered tool decisions"),
        systemImage: "hand.raised",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        GalaxySSIPermissionsAuditView()
      }
    }
  }

  private var destinationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_destinations_title", "Data Destinations"))
      if destinations.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_privacy_no_destinations", "No external destination configured"),
          subtitle: t("cc_privacy_no_destinations_subtitle", "Add a cloud model or pair a trusted Desktop Agent to see it here"),
          systemImage: "cpu",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(destinations) { destination in
          GalaxySSISecurityNavigationRow(
            title: destination.title,
            subtitle: String(
              format: t("cc_privacy_destination_subtitle", "%@ / %@"),
              destination.locationLabel(language: interfaceLanguage),
              destination.modelLabel(language: interfaceLanguage)
            ),
            systemImage: destination.systemImage,
            tint: destination.blocked ? .orange : .galaxySSIAccent,
            badge: destination.blocked ? t("cc_privacy_blocked", "Blocked") : t("cc_privacy_allowed", "Allowed")
          ) {
            GalaxySSIPrivacyDestinationDetailView(
              destinationId: destination.id,
              disclosureStore: disclosureStore
            )
            .environmentObject(store)
          }
        }
      }
    }
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_recent_title", "Recent Data Flows"))
      if records.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_privacy_no_events", "No external data flow yet"),
          subtitle: t("cc_privacy_no_events_subtitle", "A metadata receipt appears after data is sent or blocked"),
          systemImage: "lock.doc",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(records.prefix(30)) { record in
          GalaxySSISecurityNavigationRow(
            title: record.destinationTitle,
            subtitle: String(
              format: t("cc_privacy_event_subtitle", "%@ / %@"),
              dataKindsLabel(record.dataKinds),
              timeLabel(record.updatedAtMillis)
            ),
            systemImage: locationSystemImage(record.location),
            tint: statusTint(record.status),
            badge: statusLabel(record.status)
          ) {
            GalaxySSIPrivacyEventDetailView(
              eventId: record.eventId,
              disclosureStore: disclosureStore
            )
          }
        }
      }
    }
  }

  private var historySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_history_title", "History"))
      GalaxySSISecurityActionRow(
        title: t("cc_privacy_clear_title", "Clear Data-flow History"),
        subtitle: t("cc_privacy_clear_subtitle", "Remove disclosure metadata while keeping destination blocks"),
        systemImage: "trash",
        tint: .gray,
        badge: ""
      ) {
        disclosureStore.clearHistory()
        refresh()
      }
    }
  }

  private var footer: some View {
    Text(t("cc_privacy_footer", "Prompt text, file contents, API keys, and credentials are never stored in this ledger."))
      .font(.system(size: 12))
      .foregroundColor(.galaxySSITextSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 4)
  }

  private func refresh() {
    records = disclosureStore.list(limit: InMemoryAgentDataDisclosureStore.maxListLimit)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func dataKindsLabel(_ kinds: Set<AgentDisclosedDataKind>) -> String {
    let separator = t("cc_privacy_kind_separator", ", ")
    return kinds
      .sorted { $0.rawValue < $1.rawValue }
      .map { dataKindLabel($0) }
      .joined(separator: separator)
      .ifBlank(t("cc_privacy_no_data", "No content category"))
  }

  private func dataKindLabel(_ kind: AgentDisclosedDataKind) -> String {
    switch kind {
    case .messageText: return t("cc_privacy_kind_message", "Message text")
    case .conversationHistory: return t("cc_privacy_kind_history", "Conversation history")
    case .systemInstructions: return t("cc_privacy_kind_system", "System instructions")
    case .toolOutput: return t("cc_privacy_kind_tool", "Tool output")
    case .screenContext: return t("cc_privacy_kind_screen", "Screen context")
    case .memoryContext: return t("cc_privacy_kind_memory", "Memory context")
    case .knowledgeContext: return t("cc_privacy_kind_knowledge", "Knowledge context")
    case .deviceContext: return t("cc_privacy_kind_device", "Device context")
    case .image: return t("cc_privacy_kind_image", "Image")
    case .audio: return t("cc_privacy_kind_audio", "Audio")
    case .video: return t("cc_privacy_kind_video", "Video")
    case .document: return t("cc_privacy_kind_document", "Document")
    case .otherFile: return t("cc_privacy_kind_file", "Other file")
    }
  }

  private func statusLabel(_ status: AgentDisclosureStatus) -> String {
    switch status {
    case .preparing: return t("cc_privacy_status_preparing", "Preparing")
    case .queued: return t("cc_privacy_status_queued", "Queued")
    case .sent: return t("cc_privacy_status_sent", "Sent")
    case .blocked: return t("cc_privacy_status_blocked", "Blocked")
    case .failed: return t("cc_privacy_status_failed", "Failed")
    }
  }

  private func statusTint(_ status: AgentDisclosureStatus) -> Color {
    switch status {
    case .sent: return .galaxySSIAccent
    case .preparing, .queued: return .blue
    case .blocked, .failed: return .orange
    }
  }

  private func locationSystemImage(_ location: AgentResourceLocation) -> String {
    switch location {
    case .phone: return "iphone"
    case .trustedDesktop: return "desktopcomputer"
    case .privateNetwork: return "network"
    case .cloud: return "cloud"
    }
  }

  private func timeLabel(_ millis: Int64) -> String {
    guard millis > 0 else { return t("cc_privacy_time_unknown", "Unknown time") }
    let elapsed = Swift.max(0, Int64(Date().timeIntervalSince1970 * 1_000) - millis)
    if elapsed < 60_000 {
      return t("cc_privacy_time_now", "Just now")
    }
    if elapsed < 3_600_000 {
      return String(format: t("cc_privacy_time_minutes", "%d min ago"), Int(elapsed / 60_000))
    }
    if elapsed < 86_400_000 {
      return String(format: t("cc_privacy_time_hours", "%d h ago"), Int(elapsed / 3_600_000))
    }
    return Date(timeIntervalSince1970: Double(millis) / 1_000)
      .formatted(date: .abbreviated, time: .shortened)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIPrivacyMetric: View {
  var value: String
  var label: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .padding(.horizontal, 10)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIPrivacyDestinationSummary: Identifiable {
  var id: String
  var title: String
  var providerId: String
  var modelId: String
  var location: AgentResourceLocation
  var blocked: Bool
  var lastUpdatedAtMillis: Int64

  var systemImage: String {
    switch location {
    case .phone: return "iphone"
    case .trustedDesktop: return "desktopcomputer"
    case .privateNetwork: return "network"
    case .cloud: return "cloud"
    }
  }

  func locationLabel(language: String) -> String {
    switch location {
    case .phone:
      return GalaxySSILocalization.string("cc_privacy_location_phone", fallback: "This iPhone", language: language)
    case .trustedDesktop:
      return GalaxySSILocalization.string("cc_privacy_location_desktop", fallback: "Trusted Desktop", language: language)
    case .privateNetwork:
      return GalaxySSILocalization.string("cc_privacy_location_private", fallback: "Private network", language: language)
    case .cloud:
      return GalaxySSILocalization.string("cc_privacy_location_cloud", fallback: "Cloud", language: language)
    }
  }

  func modelLabel(language: String) -> String {
    modelId.ifBlank(providerId).ifBlank(
      GalaxySSILocalization.string("cc_privacy_destination_unspecified", fallback: "Not specified", language: language)
    )
  }

  static func build(
    records: [AgentDataDisclosureRecord],
    blockedDestinationIds: Set<String>,
    cloudContacts: [GalaxySSIContact] = [],
    serverLinks: [ServerLink] = []
  ) -> [GalaxySSIPrivacyDestinationSummary] {
    var summaries: [String: GalaxySSIPrivacyDestinationSummary] = [:]

    for contact in cloudContacts {
      let model = contact.selectedCloudModel
      let id = contact.id.ifBlank(contact.galaxySSIId).ifBlank(contact.displayName)
      guard !id.isEmpty else { continue }
      summaries[id] = GalaxySSIPrivacyDestinationSummary(
        id: id,
        title: contact.displayName.ifBlank(contact.name).ifBlank(id),
        providerId: contact.cloudProvider.ifBlank(model?.provider ?? ""),
        modelId: model?.modelId ?? "",
        location: .cloud,
        blocked: blockedDestinationIds.contains(id),
        lastUpdatedAtMillis: 0
      )
    }

    for link in serverLinks where link.paired {
      let id = link.desktopId.ifBlank(link.desktopName)
      guard !id.isEmpty else { continue }
      summaries[id] = GalaxySSIPrivacyDestinationSummary(
        id: id,
        title: link.desktopName.ifBlank(link.signalName).ifBlank(id),
        providerId: "GalaxySSI Link",
        modelId: link.accessProfile,
        location: .trustedDesktop,
        blocked: blockedDestinationIds.contains(id),
        lastUpdatedAtMillis: Int64(link.updatedAt.timeIntervalSince1970 * 1_000)
      )
    }

    let groupedRecords = Dictionary(grouping: records, by: \.destinationId)
    for (destinationId, destinationRecords) in groupedRecords {
      let ordered = destinationRecords.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
      guard let recent = ordered.first else { continue }
      summaries[destinationId] = GalaxySSIPrivacyDestinationSummary(
        id: destinationId,
        title: recent.destinationTitle,
        providerId: recent.providerId,
        modelId: recent.modelId,
        location: recent.location,
        blocked: blockedDestinationIds.contains(destinationId),
        lastUpdatedAtMillis: recent.updatedAtMillis
      )
    }

    for destinationId in blockedDestinationIds where summaries[destinationId] == nil {
      summaries[destinationId] = GalaxySSIPrivacyDestinationSummary(
        id: destinationId,
        title: destinationId,
        providerId: "",
        modelId: "",
        location: .cloud,
        blocked: true,
        lastUpdatedAtMillis: 0
      )
    }

    return summaries.values.sorted {
      if $0.blocked != $1.blocked {
        return $0.blocked && !$1.blocked
      }
      if $0.lastUpdatedAtMillis != $1.lastUpdatedAtMillis {
        return $0.lastUpdatedAtMillis > $1.lastUpdatedAtMillis
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }
}
