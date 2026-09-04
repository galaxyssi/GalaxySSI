import SwiftUI

struct AgentDataDisclosureDashboardView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
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

  var body: some View {
    List {
      Section(t("galaxyssi.data_disclosure.summary", "Summary")) {
        let summary = AgentDataDisclosureLedger.summary(records)
        metricRow(
          t("cc_privacy_metric_events", "Recent flows"),
          value: summary.total,
          subtitle: t("galaxyssi.data_disclosure.events_subtitle", "Model and Desktop data-sharing receipts"),
          systemImage: "list.bullet.rectangle"
        )
        metricRow(
          t("cc_privacy_metric_cloud", "Cloud flows"),
          value: summary.cloud,
          subtitle: t("galaxyssi.data_disclosure.cloud_subtitle", "Requests sent to configured cloud models"),
          systemImage: "cloud"
        )
        metricRow(
          t("cc_privacy_location_desktop", "Trusted Desktop"),
          value: summary.trustedDesktop,
          subtitle: t("galaxyssi.data_disclosure.desktop_subtitle", "GalaxySSI Link requests to paired Desktop agents"),
          systemImage: "desktopcomputer"
        )
        metricRow(
          t("cc_privacy_blocked", "Blocked"),
          value: summary.blocked,
          subtitle: t("galaxyssi.data_disclosure.blocked_subtitle", "Requests stopped by destination controls"),
          systemImage: "hand.raised"
        )
      }

      Section(t("cc_privacy_destinations_title", "Data Destinations")) {
        if destinationSummaries.isEmpty {
          Label(t("cc_privacy_no_destinations", "No external destination configured"), systemImage: "checkmark.shield")
            .foregroundColor(.secondary)
        } else {
          ForEach(destinationSummaries) { destination in
            NavigationLink(destination: AgentDataDisclosureDestinationDetailView(
              destinationId: destination.id,
              disclosureStore: disclosureStore
            )) {
              destinationRow(destination)
            }
          }
        }
      }

      Section(t("cc_privacy_recent_title", "Recent Data Flows")) {
        if records.isEmpty {
          Label(t("cc_privacy_no_events", "No external data flow yet"), systemImage: "lock.doc")
            .foregroundColor(.secondary)
        } else {
          ForEach(records.prefix(30)) { record in
            NavigationLink(destination: AgentDataDisclosureEventDetailView(
              eventId: record.eventId,
              disclosureStore: disclosureStore
            )) {
              eventRow(record)
            }
          }
        }
      }

      Section(t("cc_privacy_history_title", "History")) {
        Button(role: .destructive) {
          disclosureStore.clearHistory()
          refresh()
        } label: {
          Label(t("cc_privacy_clear_title", "Clear Data-flow History"), systemImage: "trash")
        }
        .disabled(records.isEmpty)

        Text(t("cc_privacy_clear_subtitle", "Remove disclosure metadata while keeping destination blocks"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .navigationTitle(t("cc_privacy_dashboard_title", "Privacy Dashboard"))
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          refresh()
        } label: {
          Label(t("galaxyssi.common.refresh", "Refresh"), systemImage: "arrow.clockwise")
        }
      }
    }
    .onAppear(perform: refresh)
  }

  private var destinationSummaries: [AgentDisclosureDestinationSummary] {
    AgentDisclosureDestinationSummary.build(
      records: records,
      blockedDestinationIds: blockedDestinationIds
    )
  }

  private func refresh() {
    records = disclosureStore.list(limit: InMemoryAgentDataDisclosureStore.maxListLimit)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func metricRow(
    _ title: String,
    value: Int,
    subtitle: String,
    systemImage: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .foregroundColor(.blue)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Text("\(value)")
        .font(.headline.monospacedDigit())
    }
  }

  private func destinationRow(_ destination: AgentDisclosureDestinationSummary) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: GalaxySSIPrivacyLabels.destinationIcon(destination.location))
        .foregroundColor(destination.blocked ? .orange : .blue)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(destination.title)
        Text(destination.subtitle(language: interfaceLanguage))
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
        Text(destination.kindsLabel(language: interfaceLanguage))
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if destination.blocked {
        Image(systemName: "hand.raised.fill")
          .foregroundColor(.orange)
      }
    }
  }

  private func eventRow(_ record: AgentDataDisclosureRecord) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: GalaxySSIPrivacyLabels.destinationIcon(record.location))
        .foregroundColor(GalaxySSIPrivacyLabels.statusTint(record.status))
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(record.destinationTitle)
        Text(String(
          format: t("cc_privacy_event_subtitle", "%@ / %@"),
          dataKindsLabel(record.dataKinds),
          GalaxySSIPrivacyLabels.relativeTime(record.updatedAtMillis, language: interfaceLanguage)
        ))
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
        if !record.failureReason.isEmpty {
          Text(record.failureReason)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      Spacer()
      Text(GalaxySSIPrivacyLabels.status(record.status, language: interfaceLanguage))
        .font(.caption.weight(.semibold))
        .foregroundColor(GalaxySSIPrivacyLabels.statusTint(record.status))
    }
  }

  private func dataKindsLabel(_ kinds: Set<AgentDisclosedDataKind>) -> String {
    let separator = t("cc_privacy_kind_separator", ", ")
    return kinds.sortedForDisplay.map {
      GalaxySSIPrivacyLabels.dataKind($0, language: interfaceLanguage)
    }
    .joined(separator: separator)
    .ifBlank(t("cc_privacy_no_data", "No content category"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AgentDataDisclosureDestinationDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var destinationId: String
  private let disclosureStore: AgentDataDisclosureStore
  @State private var records: [AgentDataDisclosureRecord] = []
  @State private var blockedDestinationIds: Set<String> = []

  init(destinationId: String, disclosureStore: AgentDataDisclosureStore) {
    self.destinationId = destinationId
    self.disclosureStore = disclosureStore
  }

  var body: some View {
    List {
      if let summary {
        Section(t("cc_privacy_destination_details", "Destination")) {
          row(t("galaxyssi.data_disclosure.name", "Name"), value: summary.title, systemImage: "person.crop.circle")
          row(
            t("cc_privacy_location", "Processing location"),
            value: GalaxySSIPrivacyLabels.location(summary.location, language: interfaceLanguage),
            systemImage: GalaxySSIPrivacyLabels.destinationIcon(summary.location)
          )
          row(
            t("cc_privacy_trust", "Trust level"),
            value: GalaxySSIPrivacyLabels.trust(summary.trust, language: interfaceLanguage),
            systemImage: "checkmark.shield"
          )
          row(
            t("cc_privacy_protection", "Transport protection"),
            value: GalaxySSIPrivacyLabels.protection(summary.protection, language: interfaceLanguage),
            systemImage: "lock.shield"
          )
        }

        Section(t("cc_privacy_observed_data_title", "Observed Data Types")) {
          ForEach(summary.dataKinds, id: \.self) { kind in
            row(
              GalaxySSIPrivacyLabels.dataKind(kind, language: interfaceLanguage),
              value: t("cc_privacy_metadata_not_content", "Only type and size metadata is retained"),
              systemImage: GalaxySSIPrivacyLabels.dataKindIcon(kind)
            )
          }
        }

        Section(t("cc_privacy_control_title", "Data Control")) {
          Toggle(t("cc_privacy_allow_destination", "Allow data sharing"), isOn: Binding(
            get: { !blockedDestinationIds.contains(destinationId) },
            set: { allowed in
              disclosureStore.setDestinationBlocked(destinationId: destinationId, blocked: !allowed)
              refresh()
            }
          ))
          Text(t(
            "cc_privacy_allow_destination_subtitle",
            "Turning this off blocks future model and Agent requests to this exact destination"
          ))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Section(t("cc_privacy_recent_title", "Recent Data Flows")) {
          ForEach(summary.records.prefix(30)) { record in
            NavigationLink(destination: AgentDataDisclosureEventDetailView(
              eventId: record.eventId,
              disclosureStore: disclosureStore
            )) {
              HStack {
                Text(GalaxySSIPrivacyLabels.relativeTime(record.updatedAtMillis, language: interfaceLanguage))
                Spacer()
                Text(GalaxySSIPrivacyLabels.status(record.status, language: interfaceLanguage))
                  .foregroundColor(GalaxySSIPrivacyLabels.statusTint(record.status))
              }
            }
          }
        }
      } else {
        Section {
          Label(t("galaxyssi.data_disclosure.destination_not_found", "Destination not found"), systemImage: "questionmark.circle")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(summary?.title ?? t("cc_privacy_destination_details", "Destination"))
    .onAppear(perform: refresh)
  }

  private var summary: AgentDisclosureDestinationSummary? {
    AgentDisclosureDestinationSummary
      .build(records: records, blockedDestinationIds: blockedDestinationIds)
      .first { $0.id == destinationId }
  }

  private func refresh() {
    records = disclosureStore.list(limit: InMemoryAgentDataDisclosureStore.maxListLimit)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func row(_ title: String, value: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundColor(.blue)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(value)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AgentDataDisclosureEventDetailView: View {
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
    List {
      if let record {
        Section(t("cc_privacy_event_title", "Data-flow Receipt")) {
          row(
            t("cc_privacy_destination_details", "Destination"),
            value: record.destinationTitle,
            systemImage: GalaxySSIPrivacyLabels.destinationIcon(record.location)
          )
          row(
            t("galaxyssi.data_disclosure.status", "Status"),
            value: GalaxySSIPrivacyLabels.status(record.status, language: interfaceLanguage),
            systemImage: record.status.systemImage
          )
          row(
            t("cc_privacy_purpose", "Purpose"),
            value: record.purpose.ifBlank(t("cc_privacy_destination_unspecified", "Not specified")),
            systemImage: "target"
          )
          row(
            t("cc_privacy_time", "Time"),
            value: GalaxySSIPrivacyLabels.exactTime(record.updatedAtMillis, language: interfaceLanguage),
            systemImage: "clock"
          )
        }

        Section(t("cc_privacy_shared_data_title", "Data Shared")) {
          ForEach(record.dataKinds.sortedForDisplay, id: \.self) { kind in
            row(
              GalaxySSIPrivacyLabels.dataKind(kind, language: interfaceLanguage),
              value: t("cc_privacy_metadata_not_content", "Only type and size metadata is retained"),
              systemImage: GalaxySSIPrivacyLabels.dataKindIcon(kind)
            )
          }
        }

        Section(t("galaxyssi.data_disclosure.size_section", "Size")) {
          row(
            t("cc_privacy_text_size", "Text size"),
            value: String(format: t("cc_privacy_character_count", "%d characters"), record.textCharacters),
            systemImage: "text.alignleft"
          )
          row(
            t("cc_privacy_attachments", "Attachments"),
            value: String(
              format: t("cc_privacy_attachment_summary", "%d files / %@"),
              record.attachmentCount,
              ByteCountFormatter.string(fromByteCount: record.attachmentBytes, countStyle: .file)
            ),
            systemImage: "paperclip"
          )
        }

        Section(t("cc_privacy_protection", "Transport protection")) {
          row(
            t("cc_privacy_location", "Processing location"),
            value: GalaxySSIPrivacyLabels.location(record.location, language: interfaceLanguage),
            systemImage: GalaxySSIPrivacyLabels.destinationIcon(record.location)
          )
          row(
            t("cc_privacy_trust", "Trust level"),
            value: GalaxySSIPrivacyLabels.trust(record.trust, language: interfaceLanguage),
            systemImage: "checkmark.shield"
          )
          row(
            t("cc_privacy_protection", "Transport protection"),
            value: GalaxySSIPrivacyLabels.protection(record.protection, language: interfaceLanguage),
            systemImage: "lock.shield"
          )
          if !record.failureReason.isEmpty {
            row(t("galaxyssi.data_disclosure.reason", "Reason"), value: record.failureReason, systemImage: "exclamationmark.triangle")
          }
        }

        Section(t("cc_privacy_control_title", "Data Control")) {
          Toggle(t("cc_privacy_allow_destination", "Allow data sharing"), isOn: Binding(
            get: { !blockedDestinationIds.contains(record.destinationId) },
            set: { allowed in
              disclosureStore.setDestinationBlocked(destinationId: record.destinationId, blocked: !allowed)
              refresh()
            }
          ))
        }
      } else {
        Section {
          Label(t("galaxyssi.data_disclosure.event_not_found", "Event not found"), systemImage: "questionmark.circle")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("cc_privacy_event_title", "Data-flow Receipt"))
    .onAppear(perform: refresh)
  }

  private func refresh() {
    record = disclosureStore.find(eventId: eventId)
    blockedDestinationIds = disclosureStore.blockedDestinationIds()
  }

  private func row(_ title: String, value: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundColor(.blue)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        Text(value)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentDisclosureDestinationSummary: Identifiable, Equatable {
  var id: String
  var title: String
  var providerId: String
  var modelId: String
  var location: AgentResourceLocation
  var trust: AgentResourceTrust
  var protection: AgentDisclosureProtection
  var dataKinds: [AgentDisclosedDataKind]
  var records: [AgentDataDisclosureRecord]
  var blocked: Bool

  func subtitle(language: String) -> String {
    let model = modelId.ifBlank(providerId).ifBlank(GalaxySSIPrivacyLabels.location(location, language: language))
    return String(
      format: GalaxySSILocalization.string(
        "galaxyssi.data_disclosure.destination_summary",
        fallback: "%d events / %@ / %@",
        language: language
      ),
      records.count,
      model,
      GalaxySSIPrivacyLabels.protection(protection, language: language)
    )
  }

  func kindsLabel(language: String) -> String {
    let separator = GalaxySSILocalization.string("cc_privacy_kind_separator", fallback: ", ", language: language)
    return dataKinds.map {
      GalaxySSIPrivacyLabels.dataKind($0, language: language)
    }
    .joined(separator: separator)
    .ifBlank(GalaxySSILocalization.string("cc_privacy_no_data", fallback: "No content category", language: language))
  }

  static func build(
    records: [AgentDataDisclosureRecord],
    blockedDestinationIds: Set<String>
  ) -> [AgentDisclosureDestinationSummary] {
    Dictionary(grouping: records, by: \.destinationId)
      .map { destinationId, records in
        let ordered = records.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        let recent = ordered[0]
        let kinds = Set(ordered.flatMap { $0.dataKinds }).sortedForDisplay
        return AgentDisclosureDestinationSummary(
          id: destinationId,
          title: recent.destinationTitle,
          providerId: recent.providerId,
          modelId: recent.modelId,
          location: recent.location,
          trust: recent.trust,
          protection: recent.protection,
          dataKinds: kinds,
          records: ordered,
          blocked: blockedDestinationIds.contains(destinationId)
        )
      }
      .sorted {
        if $0.blocked != $1.blocked {
          return $0.blocked && !$1.blocked
        }
        return ($0.records.first?.updatedAtMillis ?? 0) > ($1.records.first?.updatedAtMillis ?? 0)
      }
  }
}

private extension AgentDisclosureStatus {
  var systemImage: String {
    switch self {
    case .preparing, .queued: return "clock"
    case .sent: return "checkmark.circle"
    case .blocked: return "hand.raised"
    case .failed: return "exclamationmark.triangle"
    }
  }
}

private extension Set where Element == AgentDisclosedDataKind {
  var sortedForDisplay: [AgentDisclosedDataKind] {
    sorted { $0.rawValue < $1.rawValue }
  }
}
