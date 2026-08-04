import SwiftUI

struct SignalASIProtocolQualityView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var snapshot = SignalASILinkTransportDiagnostics.snapshot()

  private var pairedLinks: [ServerLink] {
    store.serverLinks
      .filter(\.paired)
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
  }

  private var allLinks: [ServerLink] {
    store.serverLinks.sorted { lhs, rhs in
      lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
    }
  }

  private var transportConnected: Bool {
    coordinator.mqttClient.isConnected
  }

  private var secureSessionReady: Bool {
    transportConnected && !pairedLinks.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("protocol_quality_title", "Protocol & Quality"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: "SignalASI Link",
            subtitle: t("protocol_quality_hero_subtitle", "Secure communication and Agent collaboration protocol"),
            systemImage: "link.circle",
            tint: Self.linkTint,
            badge: "v1.0.3"
          )
          qualitySection
          securitySection
          protocolSection
          endpointSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshSnapshot)
  }

  private var qualitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_section_quality", "Quality"))
      SignalASISecurityStatusRow(
        title: t("protocol_delivery_ack", "Delivery Acknowledgement"),
        subtitle: t("protocol_delivery_ack_subtitle", "Wait for peer confirmation after a message is sent"),
        systemImage: "paperplane",
        tint: .blue,
        badge: t("common_on", "On")
      )
      SignalASISecurityStatusRow(
        title: t("protocol_offline_queue", "Offline Queue"),
        subtitle: t("protocol_offline_queue_subtitle", "Receive queued messages after the app has been closed"),
        systemImage: "tray.and.arrow.down",
        tint: .orange,
        badge: enabledLabel
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.settings.link_diagnostics", "Link Diagnostics"),
        subtitle: linkDiagnosticsSummary,
        systemImage: "waveform.path.ecg",
        tint: snapshot.totalEvents == 0 ? .signalASIAccent : .orange,
        badge: snapshot.totalEvents == 0 ? stableLabel : "\(snapshot.totalEvents)"
      ) {
        SignalASILinkDiagnosticsView()
      }
    }
  }

  private var securitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_section_security", "Security"))
      SignalASISecurityStatusRow(
        title: t("protocol_identity_key", "Identity Key"),
        subtitle: t("protocol_identity_key_subtitle", "Save peer public keys after the first scan"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: enabledLabel
      )
      SignalASISecurityStatusRow(
        title: t("protocol_session_rotation", "Session Rotation"),
        subtitle: t("protocol_session_rotation_subtitle", "Old devices become invalid after pairing is updated"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: .purple,
        badge: enabledLabel
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.protocol_quality.phone_identity", "Phone Identity"),
        subtitle: SignalASISecurityFormatter.fingerprint(
          store.profile.identityFingerprint,
          unknown: t("signalasi.status.unknown", "Unknown")
        ),
        systemImage: "iphone",
        tint: .signalASIAccent,
        badge: enabledLabel,
        monospacedSubtitle: true
      )
    }
  }

  private var protocolSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: "Signal Link Protocol")
      SignalASISecurityNavigationRow(
        title: "Signal Link Protocol",
        subtitle: secureSessionReady
          ? t("cc_service_link_connected", "SignalASI Link secure session is connected")
          : t("cc_service_link_offline", "SignalASI Link is offline or waiting for a paired endpoint"),
        systemImage: "link",
        tint: secureSessionReady ? .signalASIAccent : .orange,
        badge: secureSessionReady ? stableLabel : disconnectedLabel
      ) {
        SignalASILinkProtocolView()
      }
    }
  }

  private var endpointSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_section_current_endpoint", "Current Endpoint"))
      if allLinks.isEmpty {
        SignalASISecurityNavigationRow(
          title: t("signalasi.protocol_quality.no_endpoint", "No PC endpoint"),
          subtitle: t("signalasi.protocol_quality.no_endpoint_subtitle", "Scan a Desktop QR code to create a SignalASI Link endpoint"),
          systemImage: "qrcode.viewfinder",
          tint: .orange,
          badge: t("signalasi.security_center.scan", "Scan")
        ) {
          AddContactView(autoOpenScanner: true)
        }
      } else {
        ForEach(allLinks.prefix(3)) { link in
          SignalASISecurityStatusRow(
            title: link.desktopName.ifBlank(t("protocol_pc_endpoint", "PC Endpoint")),
            subtitle: link.desktopId,
            systemImage: "desktopcomputer",
            tint: link.paired ? .signalASIAccent : .orange,
            badge: link.paired
              ? t("signalasi.common.paired", "Paired")
              : t("signalasi.security_center.status_pending", "Pending"),
            monospacedSubtitle: true
          )
        }
        if allLinks.count > 3 {
          SignalASISecurityNavigationRow(
            title: t("signalasi.protocol_quality.desktop_endpoints", "Desktop Endpoints"),
            subtitle: String(format: t("signalasi.protocol_quality.endpoint_count", "%d endpoints"), allLinks.count),
            systemImage: "desktopcomputer.and.arrow.down",
            tint: .blue,
            badge: t("signalasi.common.manage", "Manage")
          ) {
            SignalASISecurityCenterView()
          }
        }
      }
    }
  }

  private var linkDiagnosticsSummary: String {
    if snapshot.totalEvents == 0 {
      return t("signalasi.settings.link_stable", "Stable / 0 events")
    }
    return String(
      format: t("signalasi.settings.link.summary", "%d events / %d replay / %d failures"),
      snapshot.totalEvents,
      snapshot.replayCount,
      snapshot.failureCount
    )
  }

  private var enabledLabel: String {
    t("protocol_badge_enabled", "Enabled")
  }

  private var stableLabel: String {
    t("protocol_badge_stable", "Stable")
  }

  private var disconnectedLabel: String {
    t("status_disconnected", "Disconnected")
  }

  private func refreshSnapshot() {
    snapshot = SignalASILinkTransportDiagnostics.snapshot()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private static let linkTint = Color(red: 0.36, green: 0.42, blue: 1)
}

struct SignalASILinkProtocolView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var snapshot = SignalASILinkTransportDiagnostics.snapshot()

  private var pairedLinks: [ServerLink] {
    store.serverLinks
      .filter(\.paired)
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
  }

  private var activeLink: ServerLink? {
    pairedLinks.first ?? store.serverLinks.first
  }

  private var transportConnected: Bool {
    coordinator.mqttClient.isConnected
  }

  private var secureSessionReady: Bool {
    transportConnected && activeLink?.paired == true
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: "Signal Link Protocol",
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: "Signal Link Protocol",
            subtitle: secureSessionReady
              ? t("cc_service_link_connected", "SignalASI Link secure session is connected")
              : t("cc_service_link_offline", "SignalASI Link is offline or waiting for a paired endpoint"),
            systemImage: "link.circle",
            tint: secureSessionReady ? .signalASIAccent : .orange,
            badge: secureSessionReady ? stableLabel : disconnectedLabel
          )
          layersSection
          currentEndpointSection
          diagnosticsSection
          recentEventsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshSnapshot)
  }

  private var layersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_section_layers", "Protocol Layers"))
      SignalASISecurityStatusRow(
        title: t("protocol_identity_layer", "Identity Layer"),
        subtitle: t("protocol_identity_layer_subtitle", "Key pairs, identity fingerprints, and first-use verification"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: enabledLabel
      )
      SignalASISecurityStatusRow(
        title: t("protocol_session_layer", "Session Layer"),
        subtitle: t("protocol_session_layer_subtitle", "Signal Protocol encrypted message layer"),
        systemImage: "lock.rotation",
        tint: secureSessionReady ? .signalASIAccent : .orange,
        badge: secureSessionReady ? enabledLabel : disconnectedLabel
      )
      SignalASISecurityStatusRow(
        title: t("protocol_transport_layer", "Transport Layer"),
        subtitle: t("protocol_transport_layer_subtitle", "MQTT / Relay / Local automatic selection"),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: transportConnected ? .blue : .orange,
        badge: transportConnected ? "MQTT" : disconnectedLabel
      )
    }
  }

  private var currentEndpointSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_section_current_endpoint", "Current Endpoint"))
      if let link = activeLink {
        SignalASISecurityStatusRow(
          title: t("protocol_pc_endpoint", "PC Endpoint"),
          subtitle: endpointSubtitle(link),
          systemImage: "desktopcomputer",
          tint: secureSessionReady ? .signalASIAccent : .orange,
          badge: secureSessionReady ? t("protocol_badge_online", "Online") : disconnectedLabel,
          monospacedSubtitle: true
        )
        SignalASISecurityStatusRow(
          title: t("signalasi.protocol_quality.access_profile", "Access Profile"),
          subtitle: link.accessProfile.ifBlank(SignalASILinkProtocol.accessRestricted),
          systemImage: "slider.horizontal.3",
          tint: link.fullDesktopExecutor ? .purple : .blue,
          badge: link.fullDesktopExecutor ? enabledLabel : t("signalasi.status.protected", "Protected")
        )
      } else {
        SignalASISecurityNavigationRow(
          title: t("signalasi.protocol_quality.no_endpoint", "No PC endpoint"),
          subtitle: t("signalasi.protocol_quality.no_endpoint_subtitle", "Scan a Desktop QR code to create a SignalASI Link endpoint"),
          systemImage: "qrcode.viewfinder",
          tint: .orange,
          badge: t("signalasi.security_center.scan", "Scan")
        ) {
          AddContactView(autoOpenScanner: true)
        }
      }
    }
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_transport_diagnostics", "Transport Diagnostics"))
      SignalASISecurityStatusRow(
        title: t("protocol_replay_events", "Replay events"),
        subtitle: t("protocol_replay_events_subtitle", "Encrypted and pending deliveries handled safely"),
        systemImage: "arrow.counterclockwise",
        tint: .blue,
        badge: "\(snapshot.replayCount)"
      )
      SignalASISecurityStatusRow(
        title: t("protocol_duplicate_events", "Duplicate messages"),
        subtitle: t("protocol_duplicate_events_subtitle", "Duplicate messages, receipts, and chunks ignored"),
        systemImage: "doc.on.doc",
        tint: .orange,
        badge: "\(snapshot.duplicateCount)"
      )
      SignalASISecurityStatusRow(
        title: t("protocol_old_counter_events", "Old counters"),
        subtitle: t("protocol_old_counter_events_subtitle", "Signal messages rejected because their counter was stale"),
        systemImage: "clock",
        tint: .purple,
        badge: "\(snapshot.oldCounterCount)"
      )
      SignalASISecurityStatusRow(
        title: t("protocol_transport_failures", "Transport failures"),
        subtitle: t("protocol_transport_failures_subtitle", "Decryption and fragmented-transfer failures"),
        systemImage: "exclamationmark.shield",
        tint: snapshot.failureCount == 0 ? .signalASIAccent : .red,
        badge: "\(snapshot.failureCount)"
      )
    }
  }

  private var recentEventsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("protocol_recent_transport_events", "Recent Transport Events"))
      if snapshot.recentEvents.isEmpty {
        SignalASISecurityStatusRow(
          title: t("protocol_no_transport_anomalies", "No transport anomalies"),
          subtitle: t("protocol_no_transport_anomalies_subtitle", "No replay, duplicate, or stale-counter event has been recorded"),
          systemImage: "checkmark.shield",
          tint: .signalASIAccent,
          badge: stableLabel
        )
      } else {
        ForEach(Array(snapshot.recentEvents.prefix(5))) { event in
          SignalASISecurityStatusRow(
            title: eventLabel(event.kind),
            subtitle: String(
              format: t("protocol_transport_event_subtitle", "%@ - anonymous references %@"),
              protocolTime(event.recordedAtMillis),
              eventReferences(event)
            ),
            systemImage: eventSystemImage(event.kind),
            tint: eventTint(event.kind),
            badge: t("protocol_diagnostic_recorded", "Recorded")
          )
        }
        SignalASISecurityNavigationRow(
          title: t("signalasi.settings.link_diagnostics", "Link Diagnostics"),
          subtitle: String(format: t("signalasi.settings.link.summary", "%d events / %d replay / %d failures"), snapshot.totalEvents, snapshot.replayCount, snapshot.failureCount),
          systemImage: "waveform.path.ecg",
          tint: .blue,
          badge: t("signalasi.common.open", "Open")
        ) {
          SignalASILinkDiagnosticsView()
        }
      }
    }
  }

  private var enabledLabel: String {
    t("protocol_badge_enabled", "Enabled")
  }

  private var stableLabel: String {
    t("protocol_badge_stable", "Stable")
  }

  private var disconnectedLabel: String {
    t("status_disconnected", "Disconnected")
  }

  private func endpointSubtitle(_ link: ServerLink) -> String {
    let name = link.desktopName.ifBlank(t("protocol_pc_endpoint", "PC Endpoint"))
    let status = secureSessionReady
      ? t("cc_service_link_connected", "SignalASI Link secure session is connected")
      : t("cc_service_link_offline", "SignalASI Link is offline or waiting for a paired endpoint")
    return "\(name)\n\(link.desktopId)\n\(status)"
  }

  private func eventLabel(_ kind: SignalASILinkDiagnosticKind) -> String {
    switch kind {
    case .encryptedReplay:
      return t("protocol_event_encrypted_replay", "Encrypted replay handled")
    case .pendingReplay:
      return t("protocol_event_pending_replay", "Pending delivery replayed")
    case .duplicateMessage:
      return t("protocol_event_duplicate_message", "Duplicate message ignored")
    case .duplicateReceipt:
      return t("protocol_event_duplicate_receipt", "Duplicate receipt ignored")
    case .oldCounter:
      return t("protocol_event_old_counter", "Old Signal counter rejected")
    case .decryptFailure:
      return t("protocol_event_decrypt_failure", "Signal decryption failed")
    case .chunkDuplicate:
      return t("protocol_event_chunk_duplicate", "Conflicting duplicate chunk rejected")
    case .fragmentRejected:
      return t("protocol_event_fragment_rejected", "Fragmented transfer rejected")
    }
  }

  private func eventSystemImage(_ kind: SignalASILinkDiagnosticKind) -> String {
    switch kind {
    case .encryptedReplay, .pendingReplay:
      return "arrow.counterclockwise"
    case .duplicateMessage, .duplicateReceipt, .chunkDuplicate:
      return "doc.on.doc"
    case .oldCounter:
      return "clock"
    case .decryptFailure, .fragmentRejected:
      return "exclamationmark.shield"
    }
  }

  private func eventTint(_ kind: SignalASILinkDiagnosticKind) -> Color {
    switch kind {
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

  private func eventReferences(_ event: SignalASILinkDiagnosticEvent) -> String {
    let references = [event.endpointRef, event.messageRef]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if references.isEmpty {
      return t("signalasi.status.unknown", "Unknown")
    }
    return references.joined(separator: " / ")
  }

  private func protocolTime(_ millis: Int64) -> String {
    guard millis > 0 else {
      return t("signalasi.status.unknown", "Unknown")
    }
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = "MM/dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private func refreshSnapshot() {
    snapshot = SignalASILinkTransportDiagnostics.snapshot()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
