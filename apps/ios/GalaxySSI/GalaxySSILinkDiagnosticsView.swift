import SwiftUI

struct GalaxySSILinkDiagnosticsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var snapshot = GalaxySSILinkTransportDiagnostics.snapshot()

  var body: some View {
    List {
      Section(header: Text(t("protocol_transport_summary", "Summary"))) {
        metricRow(
          t("protocol_replay_events", "Replay Events"),
          value: snapshot.replayCount,
          subtitle: t("protocol_replay_events_subtitle", "Encrypted and pending replay handling"),
          systemImage: "arrow.clockwise",
          tint: .blue
        )
        metricRow(
          t("protocol_duplicate_events", "Duplicate Events"),
          value: snapshot.duplicateCount,
          subtitle: t("protocol_duplicate_events_subtitle", "Duplicate messages, receipts, and chunks"),
          systemImage: "doc.on.doc",
          tint: .orange
        )
        metricRow(
          t("protocol_old_counter_events", "Old Counter Events"),
          value: snapshot.oldCounterCount,
          subtitle: t("protocol_old_counter_events_subtitle", "Rejected stale encrypted counters"),
          systemImage: "shield",
          tint: .purple
        )
        metricRow(
          t("protocol_transport_failures", "Transport Failures"),
          value: snapshot.failureCount,
          subtitle: t("protocol_transport_failures_subtitle", "Decrypt and fragment rejection events"),
          systemImage: "exclamationmark.triangle",
          tint: .red
        )
      }

      Section(header: Text(t("protocol_recent_transport_events", "Recent Events"))) {
        if snapshot.recentEvents.isEmpty {
          Label(t("protocol_no_transport_anomalies", "No Transport Anomalies"), systemImage: "checkmark.shield")
            .foregroundColor(.secondary)
        } else {
          ForEach(Array(snapshot.recentEvents.prefix(20))) { event in
            eventRow(event)
          }
        }
      }
    }
    .navigationTitle(t("galaxyssi.settings.link_diagnostics", "Link Diagnostics"))
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          GalaxySSILinkTransportDiagnostics.clear()
          refresh()
        } label: {
          Label(t("common_clear", "Clear"), systemImage: "trash")
        }
        .disabled(snapshot.totalEvents == 0)
      }
    }
    .onAppear(perform: refresh)
  }

  private func refresh() {
    snapshot = GalaxySSILinkTransportDiagnostics.snapshot()
  }

  private func metricRow(
    _ title: String,
    value: Int64,
    subtitle: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundColor(tint)
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

  private func eventRow(_ event: GalaxySSILinkDiagnosticEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: event.kind.systemImage)
        .foregroundColor(event.kind.tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(event.kind.displayTitle(language: interfaceLanguage))
        Text(eventSubtitle(event))
          .font(.caption)
          .foregroundColor(.secondary)
        if !event.detailCode.isEmpty {
          Text(event.detailCode)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }

  private func eventSubtitle(_ event: GalaxySSILinkDiagnosticEvent) -> String {
    let date = formattedEventTime(event.recordedAtMillis)
    let references = [event.endpointRef, event.messageRef]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " / ")
    if references.isEmpty {
      return String(
        format: t("protocol_transport_event_subtitle", "%@ / anonymous references %@"),
        date,
        t("protocol_unknown_reference", "Unknown reference")
      )
    }
    return String(format: t("protocol_transport_event_subtitle", "%@ / anonymous references %@"), date, references)
  }

  private func formattedEventTime(_ timestampMillis: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestampMillis) / 1_000))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private extension GalaxySSILinkDiagnosticKind {
  func displayTitle(language: String) -> String {
    switch self {
    case .encryptedReplay:
      return t("protocol_event_encrypted_replay", "Encrypted Replay", language: language)
    case .pendingReplay:
      return t("protocol_event_pending_replay", "Pending Replay", language: language)
    case .duplicateMessage:
      return t("protocol_event_duplicate_message", "Duplicate Message", language: language)
    case .duplicateReceipt:
      return t("protocol_event_duplicate_receipt", "Duplicate Receipt", language: language)
    case .oldCounter:
      return t("protocol_event_old_counter", "Old Counter", language: language)
    case .decryptFailure:
      return t("protocol_event_decrypt_failure", "Decrypt Failure", language: language)
    case .chunkDuplicate:
      return t("protocol_event_chunk_duplicate", "Chunk Duplicate", language: language)
    case .fragmentRejected:
      return t("protocol_event_fragment_rejected", "Fragment Rejected", language: language)
    }
  }

  var systemImage: String {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return "arrow.clockwise"
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return "doc.on.doc"
    case .oldCounter:
      return "shield"
    case .decryptFailure, .fragmentRejected:
      return "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return .blue
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return .orange
    case .oldCounter:
      return .purple
    case .decryptFailure, .fragmentRejected:
      return .red
    }
  }

  private func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
