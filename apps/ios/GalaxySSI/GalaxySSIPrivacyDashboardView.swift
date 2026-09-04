import SwiftUI

struct GalaxySSIPrivacyDashboardView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var records: [AgentDataDisclosureRecord] = []
  @State private var blockedDestinationIds: Set<String> = []

  private let disclosureStore: AgentDataDisclosureStore

  init(
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    )
  ) {
    self.disclosureStore = disclosureStore
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise", action: refresh)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          heroSection
          localBoundaryBanner
          privacyBoundarySection
          destinationsSection
          recentSection
          historySection
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

  private var heroSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      GalaxySSISecurityHeroView(
        title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
        subtitle: t(
          "cc_privacy_dashboard_hero_subtitle",
          "A metadata-only audit of data sent to cloud models and trusted Desktop Agents"
        ),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("cc_privacy_metadata_only", "No prompt content stored")
      )
      HStack(spacing: 8) {
        GalaxySSIPrivacyMetricPill(
          value: "\(summary.total)",
          label: t("cc_privacy_metric_events", "Recent flows"),
          tint: .galaxySSIAccent
        )
        GalaxySSIPrivacyMetricPill(
          value: "\(summary.destinations)",
          label: t("cc_privacy_metric_destinations", "Destinations"),
          tint: .blue
        )
        GalaxySSIPrivacyMetricPill(
          value: "\(summary.cloud)",
          label: t("cc_privacy_metric_cloud", "Cloud flows"),
          tint: .purple
        )
      }
      HStack(spacing: 8) {
        Text(t("cc_privacy_metadata_only", "No prompt content stored"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
          .padding(.horizontal, 8)
          .frame(minHeight: 24)
          .background(Color.galaxySSIAccent.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        Text(String(format: t("cc_privacy_blocked_count", "%d blocked"), summary.blocked))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(summary.blocked > 0 ? .orange : .galaxySSITextSecondary)
          .padding(.horizontal, 8)
          .frame(minHeight: 24)
          .background((summary.blocked > 0 ? Color.orange : Color.gray).opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }

  private var localBoundaryBanner: some View {
    GalaxySSISecurityStatusRow(
      title: t("cc_privacy_local_title", "On-device work stays on this phone"),
      subtitle: t(
        "cc_privacy_local_subtitle",
        "Local tools and on-device models are not listed as external disclosures"
      ),
      systemImage: "iphone",
      tint: .galaxySSIAccent,
      badge: t("cc_privacy_metadata_only", "No prompt content stored")
    )
  }

  private var privacyBoundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_privacy_boundary", "Privacy Boundary"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_privacy_planner_title", "Model Planning Data"),
        subtitle: t(
          "cc_privacy_planner_subtitle",
          "Review whether screen text and Agent output may enter model planning"
        ),
        systemImage: "cpu",
        tint: .blue,
        badge: t("cc_privacy_review", "Review")
      ) {
        AgentModelPlannerSettingsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_permissions_title", "Permissions & Audit"),
        subtitle: t("cc_privacy_permissions_subtitle", "Review iOS access and remembered tool decisions"),
        systemImage: "hand.raised",
        tint: .purple,
        badge: t("cc_privacy_review", "Review")
      ) {
        GalaxySSIPermissionsAuditView()
      }
    }
  }

  private var destinationsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_destinations_title", "Data Destinations"))
      if destinations.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_privacy_no_destinations", "No external destination configured"),
          subtitle: t(
            "cc_privacy_no_destinations_subtitle",
            "Add a cloud model or pair a trusted Desktop Agent to see it here"
          ),
          systemImage: "checkmark.shield",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(destinations) { destination in
          GalaxySSISecurityNavigationRow(
            title: destination.title,
            subtitle: String(
              format: t("cc_privacy_destination_subtitle", "%@ / %@"),
              locationLabel(destination.location),
              destination.modelOrProvider.ifBlank(t("cc_privacy_destination_unspecified", "Not specified"))
            ),
            systemImage: destinationIcon(destination.location),
            tint: destination.blocked ? .orange : .galaxySSIAccent,
            badge: destination.blocked
              ? t("cc_privacy_blocked", "Blocked")
              : t("cc_privacy_allowed", "Allowed")
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
          subtitle: t(
            "cc_privacy_no_events_subtitle",
            "A metadata receipt appears after data is sent or blocked"
          ),
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
            systemImage: destinationIcon(record.location),
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

  @ViewBuilder
  private var historySection: some View {
    if !records.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("cc_privacy_history_title", "History"))
        GalaxySSISecurityActionRow(
          title: t("cc_privacy_clear_title", "Clear Data-flow History"),
          subtitle: t(
            "cc_privacy_clear_subtitle",
            "Remove disclosure metadata while keeping destination blocks"
          ),
          systemImage: "trash",
          tint: .gray,
          badge: t("common_clear", "Clear")
        ) {
          disclosureStore.clearHistory()
          refresh()
        }
      }
    }
  }

  private var footer: some View {
    Text(t(
      "cc_privacy_footer",
      "Prompt text, file contents, API keys, and credentials are never stored in this ledger."
    ))
    .font(.system(size: 12))
    .foregroundColor(.galaxySSITextSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 4)
    .padding(.top, 2)
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

  private func refresh() {
    records = disclosureStore.list(limit: 80)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func destinationIcon(_ location: AgentResourceLocation) -> String {
    switch location {
    case .trustedDesktop:
      return "desktopcomputer"
    case .privateNetwork:
      return "network"
    case .phone:
      return "iphone"
    case .cloud:
      return "cloud"
    }
  }

  private func locationLabel(_ location: AgentResourceLocation) -> String {
    GalaxySSIPrivacyLabels.location(location, language: interfaceLanguage)
  }

  private func dataKindsLabel(_ kinds: Set<AgentDisclosedDataKind>) -> String {
    let separator = t("cc_privacy_kind_separator", ", ")
    return kinds.sortedForGalaxySSIPrivacy.map { dataKindLabel($0) }
      .joined(separator: separator)
      .ifBlank(t("cc_privacy_no_data", "No content category"))
  }

  private func dataKindLabel(_ kind: AgentDisclosedDataKind) -> String {
    GalaxySSIPrivacyLabels.dataKind(kind, language: interfaceLanguage)
  }

  private func statusLabel(_ status: AgentDisclosureStatus) -> String {
    GalaxySSIPrivacyLabels.status(status, language: interfaceLanguage)
  }

  private func statusTint(_ status: AgentDisclosureStatus) -> Color {
    GalaxySSIPrivacyLabels.statusTint(status)
  }

  private func timeLabel(_ timestamp: Int64) -> String {
    GalaxySSIPrivacyLabels.relativeTime(timestamp, language: interfaceLanguage)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIPrivacyDestinationDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  var destinationId: String
  private let disclosureStore: AgentDataDisclosureStore
  @State private var records: [AgentDataDisclosureRecord] = []
  @State private var blockedDestinationIds: Set<String> = []

  init(destinationId: String, disclosureStore: AgentDataDisclosureStore) {
    self.destinationId = destinationId
    self.disclosureStore = disclosureStore
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: destination.title,
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise", action: refresh)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          heroSection
          detailsSection
          observedDataSection
          controlSection
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

  private var heroSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      GalaxySSISecurityHeroView(
        title: destination.title,
        subtitle: String(
          format: t("cc_privacy_destination_subtitle", "%@ / %@"),
          locationLabel(destination.location),
          destination.modelOrProvider.ifBlank(t("cc_privacy_destination_unspecified", "Not specified"))
        ),
        systemImage: destinationIcon(destination.location),
        tint: destination.blocked ? .orange : .galaxySSIAccent,
        badge: destination.blocked
          ? t("cc_privacy_blocked", "Blocked")
          : t("cc_privacy_allowed", "Allowed")
      )
      HStack(spacing: 8) {
        GalaxySSIPrivacyMetricPill(
          value: "\(destination.records.count)",
          label: t("cc_privacy_metric_events", "Recent flows"),
          tint: .galaxySSIAccent
        )
        GalaxySSIPrivacyMetricPill(
          value: "\(destination.dataKinds.count)",
          label: t("cc_privacy_metric_data_types", "Data types"),
          tint: .blue
        )
        GalaxySSIPrivacyMetricPill(
          value: protectionShortLabel(destination.protection, location: destination.location),
          label: t("cc_privacy_metric_protection", "Protection"),
          tint: .purple
        )
      }
    }
  }

  private var detailsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_destination_details", "Destination"))
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_provider", "Provider"),
        subtitle: destination.provider.ifBlank(t("cc_privacy_destination_unspecified", "Not specified")),
        systemImage: "cloud",
        tint: .gray,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_model", "Model"),
        subtitle: destination.model.ifBlank(t("cc_privacy_destination_unspecified", "Not specified")),
        systemImage: "cpu",
        tint: .gray,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_location", "Processing location"),
        subtitle: locationLabel(destination.location),
        systemImage: destinationIcon(destination.location),
        tint: .blue,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_trust", "Trust level"),
        subtitle: trustLabel(destination.trust),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: ""
      )
    }
  }

  private var observedDataSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_observed_data_title", "Observed Data Types"))
      if destination.dataKinds.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_privacy_no_events", "No external data flow yet"),
          subtitle: t(
            "cc_privacy_no_events_subtitle",
            "A metadata receipt appears after data is sent or blocked"
          ),
          systemImage: "info.circle",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(destination.dataKinds, id: \.self) { kind in
          GalaxySSISecurityStatusRow(
            title: dataKindLabel(kind),
            subtitle: t("cc_privacy_metadata_not_content", "Only type and size metadata is retained"),
            systemImage: dataKindIcon(kind),
            tint: .blue,
            badge: ""
          )
        }
      }
    }
  }

  private var controlSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_control_title", "Data Control"))
      GalaxySSIPrivacyToggleRow(
        title: t("cc_privacy_allow_destination", "Allow data sharing"),
        subtitle: t(
          "cc_privacy_allow_destination_subtitle",
          "Turning this off blocks future model and Agent requests to this exact destination"
        ),
        systemImage: "checkmark.shield",
        tint: destination.blocked ? .orange : .galaxySSIAccent,
        isOn: Binding(
          get: { !destination.blocked },
          set: { allowed in
            disclosureStore.setDestinationBlocked(destinationId: destination.id, blocked: !allowed)
            refresh()
          }
        )
      )
    }
  }

  private var footer: some View {
    Text(t(
      "cc_privacy_block_scope_footer",
      "Destination blocks are enforced before a cloud request or encrypted Desktop task is published."
    ))
    .font(.system(size: 12))
    .foregroundColor(.galaxySSITextSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  private var destination: GalaxySSIPrivacyDestinationSummary {
    GalaxySSIPrivacyDestinationSummary.build(
      records: records,
      blockedDestinationIds: blockedDestinationIds,
      cloudContacts: store.cloudModelContacts,
      serverLinks: store.serverLinks
    ).first { $0.id == destinationId } ?? .placeholder(
      id: destinationId,
      blocked: blockedDestinationIds.contains(destinationId)
    )
  }

  private func refresh() {
    records = disclosureStore.list(limit: 250)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func destinationIcon(_ location: AgentResourceLocation) -> String {
    GalaxySSIPrivacyLabels.destinationIcon(location)
  }

  private func locationLabel(_ location: AgentResourceLocation) -> String {
    GalaxySSIPrivacyLabels.location(location, language: interfaceLanguage)
  }

  private func trustLabel(_ trust: AgentResourceTrust) -> String {
    GalaxySSIPrivacyLabels.trust(trust, language: interfaceLanguage)
  }

  private func protectionShortLabel(_ protection: AgentDisclosureProtection?, location: AgentResourceLocation) -> String {
    GalaxySSIPrivacyLabels.protection(protection ?? defaultProtection(for: location), language: interfaceLanguage)
  }

  private func defaultProtection(for location: AgentResourceLocation) -> AgentDisclosureProtection {
    location == .trustedDesktop ? .signalE2EE : .tls
  }

  private func dataKindLabel(_ kind: AgentDisclosedDataKind) -> String {
    GalaxySSIPrivacyLabels.dataKind(kind, language: interfaceLanguage)
  }

  private func dataKindIcon(_ kind: AgentDisclosedDataKind) -> String {
    GalaxySSIPrivacyLabels.dataKindIcon(kind)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIPrivacyEventDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var eventId: String
  private let disclosureStore: AgentDataDisclosureStore
  @State private var record: AgentDataDisclosureRecord?
  @State private var blockedDestinationIds: Set<String> = []

  init(eventId: String, disclosureStore: AgentDataDisclosureStore) {
    self.eventId = eventId
    self.disclosureStore = disclosureStore
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_privacy_event_title", "Data-flow Receipt"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise", action: refresh)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let record {
            hero(record)
            sharedDataSection(record)
            eventDetailsSection(record)
            controlSection(record)
            footer
          } else {
            GalaxySSISecurityStatusRow(
              title: t("cc_privacy_no_events", "No external data flow yet"),
              subtitle: t("cc_privacy_no_events_subtitle", "A metadata receipt appears after data is sent or blocked"),
              systemImage: "questionmark.circle",
              tint: .gray,
              badge: ""
            )
          }
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

  private func hero(_ record: AgentDataDisclosureRecord) -> some View {
    GalaxySSISecurityHeroView(
      title: record.destinationTitle,
      subtitle: String(
        format: t("cc_privacy_event_subtitle", "%@ / %@"),
        dataKindsLabel(record.dataKinds),
        GalaxySSIPrivacyLabels.relativeTime(record.updatedAtMillis, language: interfaceLanguage)
      ),
      systemImage: GalaxySSIPrivacyLabels.destinationIcon(record.location),
      tint: GalaxySSIPrivacyLabels.statusTint(record.status),
      badge: GalaxySSIPrivacyLabels.status(record.status, language: interfaceLanguage)
    )
  }

  private func sharedDataSection(_ record: AgentDataDisclosureRecord) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_shared_data_title", "Data Shared"))
      if record.dataKinds.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_privacy_no_data", "No content category"),
          subtitle: t("cc_privacy_no_data_subtitle", "This event contains routing metadata only"),
          systemImage: "info.circle",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(record.dataKinds.sortedForGalaxySSIPrivacy, id: \.self) { kind in
          GalaxySSISecurityStatusRow(
            title: GalaxySSIPrivacyLabels.dataKind(kind, language: interfaceLanguage),
            subtitle: t("cc_privacy_metadata_not_content", "Only type and size metadata is retained"),
            systemImage: GalaxySSIPrivacyLabels.dataKindIcon(kind),
            tint: .blue,
            badge: ""
          )
        }
      }
    }
  }

  private func eventDetailsSection(_ record: AgentDataDisclosureRecord) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_event_details", "Receipt Details"))
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_purpose", "Purpose"),
        subtitle: record.purpose.ifBlank(t("cc_privacy_destination_unspecified", "Not specified")),
        systemImage: "target",
        tint: .gray,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_text_size", "Text size"),
        subtitle: String(format: t("cc_privacy_character_count", "%d characters"), record.textCharacters),
        systemImage: "text.alignleft",
        tint: .gray,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_attachments", "Attachments"),
        subtitle: String(
          format: t("cc_privacy_attachment_summary", "%d files / %@"),
          record.attachmentCount,
          ByteCountFormatter.string(fromByteCount: record.attachmentBytes, countStyle: .file)
        ),
        systemImage: "paperclip",
        tint: .gray,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_protection", "Transport protection"),
        subtitle: GalaxySSIPrivacyLabels.protection(record.protection, language: interfaceLanguage),
        systemImage: "lock.shield",
        tint: .galaxySSIAccent,
        badge: ""
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_privacy_time", "Time"),
        subtitle: GalaxySSIPrivacyLabels.exactTime(record.updatedAtMillis, language: interfaceLanguage),
        systemImage: "clock",
        tint: .gray,
        badge: ""
      )
    }
  }

  private func controlSection(_ record: AgentDataDisclosureRecord) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_privacy_control_title", "Data Control"))
      GalaxySSIPrivacyToggleRow(
        title: t("cc_privacy_allow_destination", "Allow data sharing"),
        subtitle: t(
          "cc_privacy_allow_destination_subtitle",
          "Turning this off blocks future model and Agent requests to this exact destination"
        ),
        systemImage: "checkmark.shield",
        tint: blockedDestinationIds.contains(record.destinationId) ? .orange : .galaxySSIAccent,
        isOn: Binding(
          get: { !blockedDestinationIds.contains(record.destinationId) },
          set: { allowed in
            disclosureStore.setDestinationBlocked(destinationId: record.destinationId, blocked: !allowed)
            refresh()
          }
        )
      )
    }
  }

  private var footer: some View {
    Text(t(
      "cc_privacy_event_footer",
      "Identifiers are stored as hashes. Message and attachment contents are not copied into the privacy ledger."
    ))
    .font(.system(size: 12))
    .foregroundColor(.galaxySSITextSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  private func refresh() {
    record = disclosureStore.find(eventId: eventId)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func dataKindsLabel(_ kinds: Set<AgentDisclosedDataKind>) -> String {
    let separator = t("cc_privacy_kind_separator", ", ")
    return kinds.sortedForGalaxySSIPrivacy.map {
      GalaxySSIPrivacyLabels.dataKind($0, language: interfaceLanguage)
    }
    .joined(separator: separator)
    .ifBlank(t("cc_privacy_no_data", "No content category"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIPrivacyDestinationSummary: Identifiable, Equatable {
  var id: String
  var title: String
  var provider: String
  var model: String
  var location: AgentResourceLocation
  var trust: AgentResourceTrust
  var protection: AgentDisclosureProtection?
  var dataKinds: [AgentDisclosedDataKind]
  var records: [AgentDataDisclosureRecord]
  var blocked: Bool

  var modelOrProvider: String {
    model.ifBlank(provider)
  }

  static func placeholder(id: String, blocked: Bool) -> GalaxySSIPrivacyDestinationSummary {
    GalaxySSIPrivacyDestinationSummary(
      id: id,
      title: id,
      provider: "",
      model: "",
      location: .cloud,
      trust: .unknown,
      protection: nil,
      dataKinds: [],
      records: [],
      blocked: blocked
    )
  }

  static func build(
    records: [AgentDataDisclosureRecord],
    blockedDestinationIds: Set<String>,
    cloudContacts: [GalaxySSIContact],
    serverLinks: [ServerLink]
  ) -> [GalaxySSIPrivacyDestinationSummary] {
    var summaries: [String: GalaxySSIPrivacyDestinationSummary] = [:]

    for contact in cloudContacts {
      let model = contact.selectedCloudModel
      let id = contact.id.ifBlank(contact.galaxySSIId).ifBlank(contact.displayName)
      summaries[id] = GalaxySSIPrivacyDestinationSummary(
        id: id,
        title: contact.displayName.ifBlank(contact.name).ifBlank(id),
        provider: contact.cloudProvider.ifBlank(model?.provider ?? ""),
        model: model?.modelId ?? "",
        location: .cloud,
        trust: .cloudConfigured,
        protection: .tls,
        dataKinds: [],
        records: [],
        blocked: blockedDestinationIds.contains(id)
      )
    }

    for link in serverLinks where link.paired {
      let id = link.desktopId.ifBlank(link.desktopName)
      guard !id.isEmpty else { continue }
      summaries[id] = GalaxySSIPrivacyDestinationSummary(
        id: id,
        title: link.desktopName.ifBlank(link.signalName).ifBlank(id),
        provider: "GalaxySSI Link",
        model: link.accessProfile,
        location: .trustedDesktop,
        trust: .verifiedPaired,
        protection: .signalE2EE,
        dataKinds: [],
        records: [],
        blocked: blockedDestinationIds.contains(id)
      )
    }

    let groupedRecords = Dictionary(grouping: records, by: \.destinationId)
    for (destinationId, destinationRecords) in groupedRecords {
      let ordered = destinationRecords.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
      guard let recent = ordered.first else { continue }
      let kinds = Set(ordered.flatMap { $0.dataKinds }).sortedForGalaxySSIPrivacy
      summaries[destinationId] = GalaxySSIPrivacyDestinationSummary(
        id: destinationId,
        title: recent.destinationTitle,
        provider: recent.providerId,
        model: recent.modelId,
        location: recent.location,
        trust: recent.trust,
        protection: recent.protection,
        dataKinds: kinds,
        records: ordered,
        blocked: blockedDestinationIds.contains(destinationId)
      )
    }

    for destinationId in blockedDestinationIds where summaries[destinationId] == nil {
      summaries[destinationId] = .placeholder(id: destinationId, blocked: true)
    }

    return summaries.values.sorted {
      if $0.blocked != $1.blocked {
        return $0.blocked && !$1.blocked
      }
      let leftTime = $0.records.first?.updatedAtMillis ?? 0
      let rightTime = $1.records.first?.updatedAtMillis ?? 0
      if leftTime != rightTime {
        return leftTime > rightTime
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }
}

private struct GalaxySSIPrivacyMetricPill: View {
  var value: String
  var label: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 19, weight: .bold, design: .rounded))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(tint.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIPrivacyToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @Binding var isOn: Bool

  var body: some View {
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
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(tint)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

enum GalaxySSIPrivacyLabels {
  static func destinationIcon(_ location: AgentResourceLocation) -> String {
    switch location {
    case .trustedDesktop:
      return "desktopcomputer"
    case .privateNetwork:
      return "network"
    case .phone:
      return "iphone"
    case .cloud:
      return "cloud"
    }
  }

  static func dataKindIcon(_ kind: AgentDisclosedDataKind) -> String {
    switch kind {
    case .memoryContext:
      return "brain"
    case .knowledgeContext:
      return "books.vertical"
    case .audio:
      return "waveform"
    case .image, .screenContext:
      return "viewfinder"
    case .deviceContext:
      return "iphone"
    case .toolOutput:
      return "wrench.and.screwdriver"
    case .video:
      return "video"
    case .document:
      return "doc.text"
    case .otherFile:
      return "paperclip"
    case .messageText, .conversationHistory:
      return "text.bubble"
    case .systemInstructions:
      return "gearshape"
    }
  }

  static func location(_ location: AgentResourceLocation, language: String) -> String {
    switch location {
    case .phone:
      return t("cc_privacy_location_phone", "This phone", language: language)
    case .trustedDesktop:
      return t("cc_privacy_location_desktop", "Trusted Desktop", language: language)
    case .privateNetwork:
      return t("cc_privacy_location_private", "Private network", language: language)
    case .cloud:
      return t("cc_privacy_location_cloud", "Cloud", language: language)
    }
  }

  static func trust(_ trust: AgentResourceTrust, language: String) -> String {
    switch trust {
    case .phoneSystem:
      return t("cc_privacy_trust_phone", "Phone system", language: language)
    case .verifiedPaired:
      return t("cc_privacy_trust_verified", "Verified pairing", language: language)
    case .privateConfigured:
      return t("cc_privacy_trust_private", "Private configuration", language: language)
    case .cloudConfigured:
      return t("cc_privacy_trust_cloud", "Configured cloud service", language: language)
    case .unknown:
      return t("cc_privacy_trust_unknown", "Unknown", language: language)
    }
  }

  static func protection(_ protection: AgentDisclosureProtection, language: String) -> String {
    switch protection {
    case .onDevice:
      return t("cc_privacy_protection_on_device", "Processed on device", language: language)
    case .signalE2EE:
      return t("cc_privacy_protection_signal", "GalaxySSI end-to-end encryption", language: language)
    case .tls:
      return t("cc_privacy_protection_tls", "Provider TLS transport", language: language)
    }
  }

  static func status(_ status: AgentDisclosureStatus, language: String) -> String {
    switch status {
    case .preparing:
      return t("cc_privacy_status_preparing", "Preparing", language: language)
    case .queued:
      return t("cc_privacy_status_queued", "Queued", language: language)
    case .sent:
      return t("cc_privacy_status_sent", "Sent", language: language)
    case .blocked:
      return t("cc_privacy_status_blocked", "Blocked", language: language)
    case .failed:
      return t("cc_privacy_status_failed", "Failed", language: language)
    }
  }

  static func statusTint(_ status: AgentDisclosureStatus) -> Color {
    switch status {
    case .sent:
      return .galaxySSIAccent
    case .preparing, .queued:
      return .blue
    case .blocked, .failed:
      return .orange
    }
  }

  static func dataKind(_ kind: AgentDisclosedDataKind, language: String) -> String {
    switch kind {
    case .messageText:
      return t("cc_privacy_kind_message", "Message text", language: language)
    case .conversationHistory:
      return t("cc_privacy_kind_history", "Conversation history", language: language)
    case .systemInstructions:
      return t("cc_privacy_kind_system", "System instructions", language: language)
    case .toolOutput:
      return t("cc_privacy_kind_tool", "Tool output", language: language)
    case .screenContext:
      return t("cc_privacy_kind_screen", "Screen context", language: language)
    case .memoryContext:
      return t("cc_privacy_kind_memory", "Memory context", language: language)
    case .knowledgeContext:
      return t("cc_privacy_kind_knowledge", "Knowledge context", language: language)
    case .deviceContext:
      return t("cc_privacy_kind_device", "Device context", language: language)
    case .image:
      return t("cc_privacy_kind_image", "Image", language: language)
    case .audio:
      return t("cc_privacy_kind_audio", "Audio", language: language)
    case .video:
      return t("cc_privacy_kind_video", "Video", language: language)
    case .document:
      return t("cc_privacy_kind_document", "Document", language: language)
    case .otherFile:
      return t("cc_privacy_kind_file", "Other file", language: language)
    }
  }

  static func relativeTime(_ timestamp: Int64, language: String) -> String {
    guard timestamp > 0 else {
      return t("cc_privacy_time_unknown", "Unknown time", language: language)
    }
    let elapsed = max(0, Int64(Date().timeIntervalSince1970 * 1_000) - timestamp)
    if elapsed < 60_000 {
      return t("cc_privacy_time_now", "Just now", language: language)
    }
    if elapsed < 3_600_000 {
      return String(
        format: t("cc_privacy_time_minutes", "%d min ago", language: language),
        Int(elapsed / 60_000)
      )
    }
    if elapsed < 86_400_000 {
      return String(
        format: t("cc_privacy_time_hours", "%d h ago", language: language),
        Int(elapsed / 3_600_000)
      )
    }
    return exactTime(timestamp, language: language)
  }

  static func exactTime(_ timestamp: Int64, language: String) -> String {
    guard timestamp > 0 else {
      return t("cc_privacy_time_unknown", "Unknown time", language: language)
    }
    let formatter = DateFormatter()
    formatter.locale = GalaxySSILocalization.dateLocale(language: language)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1_000))
  }

  private static func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private extension Set where Element == AgentDisclosedDataKind {
  var sortedForGalaxySSIPrivacy: [AgentDisclosedDataKind] {
    sorted { $0.rawValue < $1.rawValue }
  }
}

private extension Array where Element == AgentDisclosedDataKind {
  var sortedForGalaxySSIPrivacy: [AgentDisclosedDataKind] {
    sorted { $0.rawValue < $1.rawValue }
  }
}
