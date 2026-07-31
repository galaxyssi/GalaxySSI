import SwiftUI

struct AgentDataDisclosureDashboardView: View {
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
      Section("Summary") {
        let summary = AgentDataDisclosureLedger.summary(records)
        metricRow("Events", value: summary.total, subtitle: "Model and Desktop data-sharing receipts", systemImage: "list.bullet.rectangle")
        metricRow("Cloud", value: summary.cloud, subtitle: "Requests sent to configured cloud models", systemImage: "cloud")
        metricRow("Desktop", value: summary.trustedDesktop, subtitle: "SignalASI Link requests to paired Desktop agents", systemImage: "desktopcomputer")
        metricRow("Blocked", value: summary.blocked, subtitle: "Requests stopped by destination controls", systemImage: "hand.raised")
      }

      Section("Destinations") {
        if destinationSummaries.isEmpty {
          Label("No Destinations Yet", systemImage: "checkmark.shield")
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

      Section("Recent Events") {
        if records.isEmpty {
          Label("No Disclosure Events", systemImage: "lock.doc")
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

      Section("History") {
        Button(role: .destructive) {
          disclosureStore.clearHistory()
          refresh()
        } label: {
          Label("Clear Event History", systemImage: "trash")
        }
        .disabled(records.isEmpty)

        Text("Clearing history keeps destination block controls in place.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .navigationTitle("Model Data Sharing")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
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
      Image(systemName: destination.location.systemImage)
        .foregroundColor(destination.blocked ? .orange : .blue)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(destination.title)
        Text(destination.subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
        Text(destination.kindsLabel)
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
      Image(systemName: record.location.systemImage)
        .foregroundColor(record.status.tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(record.destinationTitle)
        Text("\(record.dataKinds.label) / \(record.updatedAtMillis.disclosureTimeLabel)")
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
      Text(record.status.displayTitle)
        .font(.caption.weight(.semibold))
        .foregroundColor(record.status.tint)
    }
  }
}

struct AgentDataDisclosureDestinationDetailView: View {
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
        Section("Destination") {
          row("Name", value: summary.title, systemImage: "person.crop.circle")
          row("Location", value: summary.location.displayTitle, systemImage: summary.location.systemImage)
          row("Trust", value: summary.trust.displayTitle, systemImage: "checkmark.shield")
          row("Protection", value: summary.protection.displayTitle, systemImage: "lock.shield")
        }

        Section("Observed Data") {
          ForEach(summary.dataKinds, id: \.self) { kind in
            row(kind.displayTitle, value: "Metadata only", systemImage: kind.systemImage)
          }
        }

        Section("Controls") {
          Toggle("Block Destination", isOn: Binding(
            get: { blockedDestinationIds.contains(destinationId) },
            set: { value in
              disclosureStore.setDestinationBlocked(destinationId: destinationId, blocked: value)
              refresh()
            }
          ))
          Text("Blocking this destination stops future cloud or Desktop requests before content leaves this iPhone.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Section("Recent Events") {
          ForEach(summary.records.prefix(30)) { record in
            NavigationLink(destination: AgentDataDisclosureEventDetailView(
              eventId: record.eventId,
              disclosureStore: disclosureStore
            )) {
              HStack {
                Text(record.updatedAtMillis.disclosureTimeLabel)
                Spacer()
                Text(record.status.displayTitle)
                  .foregroundColor(record.status.tint)
              }
            }
          }
        }
      } else {
        Section {
          Label("Destination Not Found", systemImage: "questionmark.circle")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(summary?.title ?? "Destination")
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
}

struct AgentDataDisclosureEventDetailView: View {
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
        Section("Event") {
          row("Destination", value: record.destinationTitle, systemImage: record.location.systemImage)
          row("Status", value: record.status.displayTitle, systemImage: record.status.systemImage)
          row("Purpose", value: record.purpose.ifBlank("Unspecified"), systemImage: "target")
          row("Time", value: record.updatedAtMillis.disclosureExactTimeLabel, systemImage: "clock")
        }

        Section("Shared Data") {
          ForEach(record.dataKinds.sortedForDisplay, id: \.self) { kind in
            row(kind.displayTitle, value: "Metadata only", systemImage: kind.systemImage)
          }
        }

        Section("Size") {
          row("Text", value: "\(record.textCharacters) characters", systemImage: "text.alignleft")
          row("Attachments", value: "\(record.attachmentCount) files / \(record.attachmentBytes.byteCountLabel)", systemImage: "paperclip")
        }

        Section("Protection") {
          row("Location", value: record.location.displayTitle, systemImage: record.location.systemImage)
          row("Trust", value: record.trust.displayTitle, systemImage: "checkmark.shield")
          row("Transport", value: record.protection.displayTitle, systemImage: "lock.shield")
          if !record.failureReason.isEmpty {
            row("Reason", value: record.failureReason, systemImage: "exclamationmark.triangle")
          }
        }

        Section("Controls") {
          Toggle("Block Destination", isOn: Binding(
            get: { blockedDestinationIds.contains(record.destinationId) },
            set: { value in
              disclosureStore.setDestinationBlocked(destinationId: record.destinationId, blocked: value)
              refresh()
            }
          ))
        }
      } else {
        Section {
          Label("Event Not Found", systemImage: "questionmark.circle")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Disclosure Event")
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

  var subtitle: String {
    let model = modelId.ifBlank(providerId).ifBlank(location.displayTitle)
    return "\(records.count) events / \(model) / \(protection.displayTitle)"
  }

  var kindsLabel: String {
    dataKinds.isEmpty ? "No data categories" : dataKinds.map(\.displayTitle).joined(separator: ", ")
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
  var displayTitle: String {
    switch self {
    case .preparing: return "Preparing"
    case .queued: return "Queued"
    case .sent: return "Sent"
    case .blocked: return "Blocked"
    case .failed: return "Failed"
    }
  }

  var systemImage: String {
    switch self {
    case .preparing, .queued: return "clock"
    case .sent: return "checkmark.circle"
    case .blocked: return "hand.raised"
    case .failed: return "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .sent: return .green
    case .preparing, .queued: return .blue
    case .blocked, .failed: return .orange
    }
  }
}

private extension AgentDisclosedDataKind {
  var displayTitle: String {
    switch self {
    case .messageText: return "Message Text"
    case .conversationHistory: return "Conversation History"
    case .systemInstructions: return "System Instructions"
    case .toolOutput: return "Tool Output"
    case .screenContext: return "Screen Context"
    case .memoryContext: return "Memory Context"
    case .knowledgeContext: return "Knowledge Context"
    case .deviceContext: return "Device Context"
    case .image: return "Image"
    case .audio: return "Audio"
    case .video: return "Video"
    case .document: return "Document"
    case .otherFile: return "Other File"
    }
  }

  var systemImage: String {
    switch self {
    case .messageText, .conversationHistory: return "text.bubble"
    case .systemInstructions: return "gearshape"
    case .toolOutput: return "wrench.and.screwdriver"
    case .screenContext: return "rectangle.on.rectangle"
    case .memoryContext: return "brain"
    case .knowledgeContext: return "books.vertical"
    case .deviceContext: return "iphone"
    case .image: return "photo"
    case .audio: return "waveform"
    case .video: return "video"
    case .document: return "doc.text"
    case .otherFile: return "paperclip"
    }
  }
}

private extension Set where Element == AgentDisclosedDataKind {
  var sortedForDisplay: [AgentDisclosedDataKind] {
    sorted { $0.rawValue < $1.rawValue }
  }

  var label: String {
    sortedForDisplay.map(\.displayTitle).joined(separator: ", ").ifBlank("No data")
  }
}

private extension Array where Element == AgentDisclosedDataKind {
  var sortedForDisplay: [AgentDisclosedDataKind] {
    sorted { $0.rawValue < $1.rawValue }
  }
}

private extension AgentResourceLocation {
  var displayTitle: String {
    switch self {
    case .phone: return "iPhone"
    case .trustedDesktop: return "Trusted Desktop"
    case .privateNetwork: return "Private Network"
    case .cloud: return "Cloud"
    }
  }

  var systemImage: String {
    switch self {
    case .phone: return "iphone"
    case .trustedDesktop: return "desktopcomputer"
    case .privateNetwork: return "network"
    case .cloud: return "cloud"
    }
  }
}

private extension AgentResourceTrust {
  var displayTitle: String {
    switch self {
    case .phoneSystem: return "Phone System"
    case .verifiedPaired: return "Verified Paired"
    case .privateConfigured: return "Private Configured"
    case .cloudConfigured: return "Cloud Configured"
    case .unknown: return "Unknown"
    }
  }
}

private extension AgentDisclosureProtection {
  var displayTitle: String {
    switch self {
    case .onDevice: return "On Device"
    case .signalE2EE: return "Signal E2EE"
    case .tls: return "TLS"
    }
  }
}

private extension Int64 {
  var disclosureTimeLabel: String {
    guard self > 0 else { return "Unknown time" }
    let elapsed = max(0, Int64(Date().timeIntervalSince1970 * 1_000) - self)
    if elapsed < 60_000 {
      return "Just now"
    }
    if elapsed < 3_600_000 {
      return "\(elapsed / 60_000)m ago"
    }
    if elapsed < 86_400_000 {
      return "\(elapsed / 3_600_000)h ago"
    }
    return disclosureExactTimeLabel
  }

  var disclosureExactTimeLabel: String {
    guard self > 0 else { return "Unknown time" }
    return Date(timeIntervalSince1970: Double(self) / 1_000)
      .formatted(date: .abbreviated, time: .standard)
  }

  var byteCountLabel: String {
    ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
  }
}
