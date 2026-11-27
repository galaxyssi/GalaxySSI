import SwiftUI

struct GalaxySSILinkDiagnosticsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var snapshot = GalaxySSILinkTransportDiagnostics.snapshot()
  @State private var transport = MqttTransportDiagnostics.unavailable

  var body: some View {
    List {
      Section(header: Text(t("mqtt_diagnostics_paths", "MQTT Paths"))) {
        ForEach(MqttBrokerEndpoint.catalog, id: \.id) { endpoint in
          mqttPathRow(endpoint)
        }
      }
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
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        refresh()
        let current = await coordinator.mqttTransportDiagnostics()
        guard !Task.isCancelled else { return }
        transport = current
        do { try await Task.sleep(nanoseconds: 1_000_000_000) }
        catch { return }
      }
    }
  }

  private func mqttPathRow(_ endpoint: MqttBrokerEndpoint) -> some View {
    let path = transport.paths[endpoint.id]
    let state = path?.state ?? .unknown
    let name = endpoint.id == "emqx" ? "EMQX" : (endpoint.id == "hivemq" ? "HiveMQ" : "Mosquitto")
    return VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(name).font(.headline)
        Spacer(minLength: 8)
        Text(mqttStateTitle(state))
          .font(.subheadline)
          .foregroundColor(state == .receiveReady ? .galaxySSIAccent : .secondary)
          .multilineTextAlignment(.trailing)
      }
      if let path {
        Text(String(format: t("mqtt_diagnostics_activity", "Reconnects %lld / queued %d / in flight %d"),
          path.reconnectAttempts, path.queuedPublishes, path.inflightPublishes))
        Text(String(format: t("mqtt_diagnostics_subscriptions", "Subscriptions %d/%d / pending %d"),
          path.activeSubscriptions, path.desiredSubscriptions, path.pendingSubscriptions))
      }
      Text(mqttDeliveryDetail(transport.verifiedDelivery[endpoint.id]))
        .foregroundColor(.secondary)
    }
    .font(.caption)
    .padding(.vertical, 4)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func mqttStateTitle(_ state: MqttBrokerPathDiagnostics.State) -> String {
    switch state {
    case .unknown: return t("mqtt_diagnostics_unknown", "Not observed")
    case .disconnected: return t("mqtt_diagnostics_disconnected", "Disconnected")
    case .connecting: return t("mqtt_diagnostics_connecting", "Connecting")
    case .subscribing: return t("mqtt_diagnostics_subscribing", "Subscribing")
    case .receiveReady: return t("mqtt_diagnostics_receive_ready", "Receive subscriptions ready")
    case .recovering: return t("mqtt_diagnostics_recovering", "Recovering")
    case .networkUnavailable: return t("mqtt_diagnostics_network_unavailable", "Network unavailable")
    }
  }

  private func mqttDeliveryDetail(_ stats: MqttMultipathPolicy.DeliveryStats?) -> String {
    guard let stats, stats.samples > 0 else {
      return t("mqtt_diagnostics_no_samples", "No peer-confirmed delivery samples")
    }
    let p50 = stats.p50.map { String(format: t("mqtt_diagnostics_ms", "%lld ms"), $0) }
      ?? t("mqtt_diagnostics_unknown", "Not observed")
    let p95: String
    if stats.samples >= 30, let value = stats.p95 {
      p95 = String(format: t("mqtt_diagnostics_ms", "%lld ms"), value)
    } else {
      p95 = t("mqtt_diagnostics_insufficient_samples", "Insufficient samples")
    }
    return String(format: t("mqtt_diagnostics_delivery_detail", "%d peer-confirmed samples / p50 %@ / p95 %@"),
      stats.samples, p50, p95)
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
    case .decryptDeferred:
      return t("protocol_event_decrypt_deferred", "Repeated decryption deferred", language: language)
    case .chunkDuplicate:
      return t("protocol_event_chunk_duplicate", "Chunk Duplicate", language: language)
    case .fragmentRejected:
      return t("protocol_event_fragment_rejected", "Fragment Rejected", language: language)
    case .publishAdmissionRefused:
      return t("protocol_event_publish_admission_refused", "Publish Admission Refused", language: language)
    }
  }

  var systemImage: String {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return "arrow.clockwise"
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return "doc.on.doc"
    case .oldCounter, .decryptDeferred:
      return "shield"
    case .decryptFailure, .fragmentRejected, .publishAdmissionRefused:
      return "exclamationmark.triangle"
    }
  }

  var tint: Color {
    switch self {
    case .encryptedReplay, .pendingReplay:
      return .blue
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return .orange
    case .oldCounter, .decryptDeferred:
      return .purple
    case .decryptFailure, .fragmentRejected, .publishAdmissionRefused:
      return .red
    }
  }

  private func t(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
