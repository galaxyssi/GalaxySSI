import Foundation
import SwiftUI

struct GalaxySSISystemStatusView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var memorySnapshot = AgentMemoryPssSnapshot()
  @State private var linkSnapshot = GalaxySSILinkTransportDiagnostics.snapshot()
  @State private var phoneMemorySnapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
  @State private var phoneStorageSnapshot: AgentMcpJSONObject = [:]
  @State private var phoneBatterySnapshot: AgentMcpJSONObject = [:]
  @State private var phoneNetworkSnapshot: AgentMcpJSONObject = [:]

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_system_status_title", "System Status"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button {
            refresh()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          banner
          GalaxySSISecurityHeroView(
            title: t("cc_system_status_title", "System Status"),
            subtitle: statusSubtitle,
            systemImage: "info.circle",
            tint: needsAttention ? .orange : .galaxySSIAccent,
            badge: needsAttention ? t("cc_status_degraded", "Degraded") : t("cc_status_normal", "Normal")
          )
          metrics
          phoneStatusSection
          coreServicesSection
          diagnosticsSection
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

  private var banner: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill((needsAttention ? Color.orange : Color.galaxySSIAccent).opacity(0.16))
        Image(systemName: needsAttention ? "exclamationmark.triangle" : "checkmark.shield")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(needsAttention ? .orange : .galaxySSIAccent)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 3) {
        Text(needsAttention ? t("cc_services_need_attention", "Some services need attention") : t("cc_all_services_normal", "All core services are operating normally"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(statusSubtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var metrics: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
      ],
      spacing: 8
    ) {
      GalaxySSISystemStatusMetricCard(
        title: t("cc_metric_native_tools", "Native tools"),
        value: "\(nativeToolSummary.available)",
        systemImage: "iphone",
        tint: nativeToolSummary.available > 0 ? .galaxySSIAccent : .orange
      )
      GalaxySSISystemStatusMetricCard(
        title: t("cc_metric_available_resources", "Available resources"),
        value: "\(availableResourceCount)/\(resourceTargetCount)",
        systemImage: "cpu",
        tint: availableResourceCount > 0 ? .blue : .orange
      )
      if GalaxySSIRuntimePlaintextProtection.sensitiveDiagnosticsEnabled {
        GalaxySSISystemStatusMetricCard(
          title: t("cc_metric_agent_memory", "Agent memory"),
          value: formattedBytes(memorySnapshot.processCurrentBytes),
          systemImage: "memorychip",
          tint: .purple
        )
      } else {
        GalaxySSISystemStatusMetricCard(
          title: t("cc_metric_knowledge_sources", "Knowledge sources"),
          value: "\(store.agentKnowledgeStats.sourceCount)",
          systemImage: "books.vertical",
          tint: .blue
        )
      }
    }
  }

  private var phoneStatusSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(
        title: t("galaxyssi.system_status.phone_title", "Phone status")
      )
      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8)
        ],
        spacing: 8
      ) {
        GalaxySSISystemStatusMetricCard(
          title: t("galaxyssi.agent.readiness.phone_battery", "Battery"),
          value: phoneBatteryValue,
          systemImage: "battery.75",
          tint: phoneBatteryTint
        )
        GalaxySSISystemStatusMetricCard(
          title: t("galaxyssi.agent.readiness.phone_storage", "Storage"),
          value: phoneStorageValue,
          systemImage: "internaldrive",
          tint: phoneStorageTint
        )
        GalaxySSISystemStatusMetricCard(
          title: t("galaxyssi.agent.readiness.phone_network", "Network"),
          value: phoneNetworkValue,
          systemImage: "antenna.radiowaves.left.and.right",
          tint: phoneNetworkConnected ? .galaxySSIAccent : .orange
        )
        GalaxySSISystemStatusMetricCard(
          title: t("galaxyssi.agent.readiness.phone_memory", "Phone memory"),
          value: phoneMemoryValue,
          systemImage: phoneMemorySnapshot.lowMemory
            ? "exclamationmark.triangle.fill"
            : "memorychip",
          tint: phoneMemorySnapshot.lowMemory ? .orange : .galaxySSIAccent
        )
      }
    }
  }

  private var coreServicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_core_services", "Core Services"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_service_runtime", "Agent Runtime"),
        subtitle: store.agentSafetySettings.executionPaused
          ? t("cc_agent_paused_subtitle", "Tasks keep their state and can continue after execution is resumed")
          : t("cc_service_runtime_subtitle", "Planning, tools, task state, and recovery"),
        systemImage: "cpu",
        tint: store.agentSafetySettings.executionPaused ? .orange : .galaxySSIAccent,
        badge: store.agentSafetySettings.executionPaused ? t("on_device_agent_status_paused", "Paused") : t("cc_status_online", "Online")
      ) {
        GalaxySSIAgentCoreView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_service_link", "GalaxySSI Link"),
        subtitle: linkReady ? t("cc_service_link_connected", "Secure session connected") : t("cc_service_link_offline", "No trusted Desktop session connected"),
        systemImage: "link",
        tint: linkReady ? .galaxySSIAccent : .orange,
        badge: linkReady ? t("cc_status_online", "Online") : t("cc_status_degraded", "Degraded")
      ) {
        GalaxySSIAgentsModelsNodesView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_service_router", "Resource Router"),
        subtitle: String(
          format: t("cc_service_router_subtitle", "%d of %d intelligence resources available"),
          availableResourceCount,
          resourceTargetCount
        ),
        systemImage: "slider.horizontal.3",
        tint: availableResourceCount > 0 ? .blue : .orange,
        badge: availableResourceCount > 0 ? t("cc_status_ready", "Ready") : t("cc_status_degraded", "Degraded")
      ) {
        GalaxySSIResourceRoutingView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_service_knowledge", "Knowledge Index"),
        subtitle: String(
          format: t("cc_service_knowledge_subtitle", "%d sources are available for retrieval"),
          store.agentKnowledgeStats.sourceCount
        ),
        systemImage: "book.closed",
        tint: store.agentKnowledgeStats.sourceCount > 0 ? .blue : .galaxySSITextSecondary,
        badge: store.agentKnowledgeStats.sourceCount > 0 ? t("cc_status_ready", "Ready") : t("status_needs_setup", "Needs Setup")
      ) {
        GalaxySSIAgentKnowledgeView()
      }
    }
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("advanced_section_diagnostics", "Diagnostics"))
      if GalaxySSIRuntimePlaintextProtection.sensitiveDiagnosticsEnabled {
        GalaxySSISecurityNavigationRow(
          title: t("cc_agent_memory_telemetry_title", "Agent Memory"),
          subtitle: String(
            format: t("cc_agent_memory_telemetry_summary", "Current %@ - peak %@"),
            formattedBytes(memorySnapshot.processCurrentBytes),
            formattedBytes(memorySnapshot.processPeakBytes)
          ),
          systemImage: "memorychip",
          tint: .purple,
          badge: t("cc_agent_memory_pss_badge", "PSS")
        ) {
          GalaxySSIAgentMemoryTelemetryView()
        }
      }
      GalaxySSISecurityNavigationRow(
        title: t("protocol_transport_diagnostics", "Transport Diagnostics"),
        subtitle: linkDiagnosticsSummary,
        systemImage: "antenna.radiowaves.left.and.right",
        tint: linkSnapshot.failureCount > 0 ? .orange : .galaxySSIAccent,
        badge: linkSnapshot.failureCount > 0 ? t("cc_status_degraded", "Degraded") : t("cc_status_normal", "Normal")
      ) {
        GalaxySSILinkDiagnosticsView()
      }
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.system_status.refresh", "Refresh status"),
        subtitle: t(
          "galaxyssi.system_status.refresh_subtitle",
          "Re-read memory, transport, tools, tasks, resource routing, and phone status"
        ),
        systemImage: "arrow.clockwise",
        tint: .blue,
        badge: t("cc_status_ready", "Ready")
      ) {
        refresh()
      }
    }
  }

  private var phoneMemoryValue: String {
    String(
      format: t(
        "galaxyssi.agent.readiness.phone_memory_value",
        "%@ free / %@"
      ),
      formattedBytes(phoneMemorySnapshot.availableBytes),
      formattedBytes(phoneMemorySnapshot.totalBytes)
    )
  }

  private var phoneBatteryValue: String {
    guard let percent = phoneBatterySnapshot["percent"]?.intValue else {
      return t("galaxyssi.agent.readiness.phone_battery_unknown", "Unknown")
    }
    return String(
      format: t("galaxyssi.agent.readiness.phone_battery_value", "%d%%"),
      Int(percent)
    )
  }

  private var phoneBatteryTint: Color {
    guard let percent = phoneBatterySnapshot["percent"]?.intValue else {
      return .galaxySSITextSecondary
    }
    return percent <= 20 ? .orange : .galaxySSIAccent
  }

  private var phoneStorageValue: String {
    String(
      format: t("galaxyssi.agent.readiness.phone_storage_value", "%@ free"),
      formattedBytes(phoneStorageSnapshot["available_bytes"]?.intValue ?? 0)
    )
  }

  private var phoneStorageTint: Color {
    phoneStorageSnapshot["low_storage"]?.boolValue == true
      ? .orange
      : .galaxySSIAccent
  }

  private var phoneNetworkConnected: Bool {
    phoneNetworkSnapshot["connected"]?.boolValue == true
  }

  private var phoneNetworkValue: String {
    phoneNetworkConnected
      ? t("galaxyssi.agent.readiness.phone_network_connected", "Connected")
      : t("galaxyssi.agent.readiness.phone_network_offline", "Offline")
  }

  private var nativeToolSummary: (total: Int, available: Int, needingAttention: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available, max(tools.count - available, 0))
  }

  private var availableResourceCount: Int {
    resourceTargets.filter { $0.status == .available }.count
  }

  private var resourceTargetCount: Int {
    resourceTargets.count
  }

  private var resourceTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  private var linkReady: Bool {
    store.serverLinks.contains(where: \.paired) &&
      coordinator.mqttClient.isConnected &&
      linkSnapshot.failureCount == 0
  }

  private var needsAttention: Bool {
    store.agentSafetySettings.executionPaused ||
      !linkReady ||
      resourceTargets.contains { $0.status == .needsSetup }
  }

  private var statusSubtitle: String {
    needsAttention
      ? t("cc_services_need_attention_subtitle", "Unavailable resources are excluded from automatic routing")
      : t("cc_all_services_normal_subtitle", "Local execution, routing, messaging, and security are available")
  }

  private var linkDiagnosticsSummary: String {
    if linkSnapshot.totalEvents == 0 {
      return t("galaxyssi.settings.link_stable", "Stable / 0 events")
    }
    return String(
      format: t("galaxyssi.settings.link.summary", "%d events / %d replay / %d failures"),
      linkSnapshot.totalEvents,
      linkSnapshot.replayCount,
      linkSnapshot.failureCount
    )
  }

  private func refresh() {
    memorySnapshot = AgentMemoryPssRuntime.snapshot()
    linkSnapshot = GalaxySSILinkTransportDiagnostics.snapshot()
    phoneMemorySnapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
    let nowMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let provider = AgentIOSDefaultHardwareStatusProvider()
    phoneStorageSnapshot = provider.storageStatus(nowMillis: nowMillis)
    phoneBatterySnapshot = provider.batteryStatus(nowMillis: nowMillis)
    phoneNetworkSnapshot = provider.networkStatus(nowMillis: nowMillis)
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .memory)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSISystemStatusMetricCard: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(tint)
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
