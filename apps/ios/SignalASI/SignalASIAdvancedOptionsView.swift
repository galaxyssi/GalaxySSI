import SwiftUI
import UIKit

struct SignalASIAdvancedOptionsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var cacheBytes: Int64 = 0
  @State private var maintenanceStatus = ""

  private var webSourceCount: Int {
    AgentIOSWebIntelligenceSourceCatalog.sourceCount
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("advanced_options_title", "Advanced Options"),
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
            title: t("cc_advanced_diagnostics_title", "Diagnostics with explicit controls"),
            subtitle: t(
              "cc_advanced_diagnostics_subtitle",
              "Inspect protocol health, permissions, and audit history without exposing private content"
            ),
            systemImage: "waveform.path.ecg",
            tint: .blue,
            badge: t("advanced_badge_careful", "Careful")
          )
          diagnosticsSection
          maintenanceSection
          footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshCacheSize)
  }

  private var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("advanced_section_diagnostics", "Diagnostics"))
      SignalASISecurityNavigationRow(
        title: t("voice_performance_title", "Voice Performance"),
        subtitle: t("voice_performance_subtitle", "Latency, reliability, thermal state, and automatic fallback"),
        systemImage: "waveform",
        tint: .signalASIAccent,
        badge: t("common_view", "View")
      ) {
        SignalASIVoicePerformanceDashboardView()
      }
      SignalASISecurityNavigationRow(
        title: t("web_sources_title", "Web intelligence sources"),
        subtitle: t(
          "web_sources_subtitle",
          "287 sources across daily life, technology, research, media, and local evidence"
        ),
        systemImage: "network",
        tint: .signalASIAccent,
        badge: String(format: t("web_sources_count", "%d sources"), webSourceCount)
      ) {
        SignalASIWebIntelligenceSourcesView()
      }
      SignalASISecurityNavigationRow(
        title: t("advanced_protocol_logs", "Protocol Diagnostics"),
        subtitle: t("advanced_protocol_logs_subtitle", "Inspect the live transport, secure session, and endpoint state"),
        systemImage: "link",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        SignalASILinkDiagnosticsView()
      }
      SignalASISecurityNavigationRow(
        title: t("self_model_title", "Agent self model"),
        subtitle: t(
          "self_model_subtitle",
          "Review learned strengths, limitations, and route calibration from completed tasks"
        ),
        systemImage: "brain.head.profile",
        tint: .signalASIInsightText,
        badge: String(format: t("self_model_runs_badge", "%d runs"), UserDefaultsAgentSelfModelStore.shared.snapshot().totalRuns)
      ) {
        SignalASIAgentSelfModelView()
      }
    }
  }

  private var maintenanceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_advanced_maintenance_section", "App Maintenance"))
      SignalASISecurityActionRow(
        title: t("cc_advanced_app_details_title", "iOS app settings"),
        subtitle: t("cc_advanced_app_details_subtitle", "System permissions, storage, notifications, and defaults"),
        systemImage: "info.circle",
        tint: .gray,
        badge: ""
      ) {
        openAppSettings()
      }
      SignalASISecurityActionRow(
        title: t("cc_clear_cache_title", "Clear Rebuildable Cache"),
        subtitle: t("cc_clear_cache_subtitle", "Remove temporary files without deleting identity or user data"),
        systemImage: "trash",
        tint: .orange,
        badge: formatBytes(cacheBytes)
      ) {
        clearRebuildableCache()
      }
      if !maintenanceStatus.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.advanced.maintenance_status", "Maintenance Status"),
          subtitle: maintenanceStatus,
          systemImage: "checkmark.circle",
          tint: .signalASIAccent,
          badge: t("signalasi.status.ready", "Ready")
        )
      }
    }
  }

  private var footer: some View {
    Text(t(
      "cc_advanced_footer",
      "These tools change diagnostics and app-level settings only. Identity and private data remain protected."
    ))
    .font(.system(size: 12))
    .foregroundColor(.signalASITextSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func clearRebuildableCache() {
    URLCache.shared.removeAllCachedResponses()
    let removedBytes = cacheBytes
    let fileManager = FileManager.default
    if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
       let children = try? fileManager.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
      children.forEach { child in
        try? fileManager.removeItem(at: child)
      }
    }
    refreshCacheSize()
    maintenanceStatus = String(
      format: t("signalasi.advanced.cache_cleared", "Cleared %@ of rebuildable cache"),
      formatBytes(removedBytes)
    )
  }

  private func refreshCacheSize() {
    let fileManager = FileManager.default
    guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      cacheBytes = 0
      return
    }
    cacheBytes = directorySize(cachesURL, fileManager: fileManager)
  }

  private func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true else {
        continue
      }
      total += Int64(values.fileSize ?? 0)
    }
    return total
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIVoicePerformanceDashboardView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var export = VoiceLatencyTelemetry.contentFreeDiagnostics()

  private var summary: VoiceDiagnosticSummary {
    export.summary
  }

  private var healthLabel: String {
    if summary.traceCount == 0 {
      return t("voice_performance_health_no_data", "No data")
    }
    if summary.failureRate >= 0.20 || summary.nativeCrashCount > 0 {
      return t("voice_performance_health_degraded", "Degraded")
    }
    if summary.fallbackRate >= 0.10 || summary.thermalDegradeCount > 0 {
      return t("voice_performance_health_watch", "Watch")
    }
    return t("voice_performance_health_healthy", "Healthy")
  }

  private var healthTint: Color {
    if summary.traceCount == 0 { return .orange }
    if summary.failureRate >= 0.20 || summary.nativeCrashCount > 0 { return .red }
    if summary.fallbackRate >= 0.10 || summary.thermalDegradeCount > 0 { return .orange }
    return .signalASIAccent
  }

  private var metrics: [(String, VoiceLatencyPercentiles)] {
    summary.metrics.sorted { lhs, rhs in
      lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("voice_performance_title", "Voice Performance"),
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
            title: t("voice_performance_hero_title", "Voice pipeline health"),
            subtitle: t("voice_performance_hero_subtitle", "Content-free measurements from this device"),
            systemImage: "waveform.path.ecg",
            tint: healthTint,
            badge: healthLabel
          )
          healthSection
          latencySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      export = VoiceLatencyTelemetry.contentFreeDiagnostics()
    }
  }

  private var healthSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_performance_health_section", "HEALTH AND RECOVERY"))
      SignalASISecurityStatusRow(
        title: t("voice_performance_success_rate", "Session success rate"),
        subtitle: String(format: t("voice_performance_session_count", "%d measured sessions"), summary.traceCount),
        systemImage: "checkmark.circle",
        tint: healthTint,
        badge: percent(summary.successRate)
      )
      SignalASISecurityStatusRow(
        title: t("voice_performance_fallback_rate", "Fallback rate"),
        subtitle: String(format: t("voice_performance_failure_rate_value", "Failure rate %.1f%%"), summary.failureRate * 100),
        systemImage: "arrow.triangle.2.circlepath",
        tint: summary.fallbackRate == 0 ? .signalASIAccent : .orange,
        badge: percent(summary.fallbackRate)
      )
      SignalASISecurityStatusRow(
        title: t("voice_performance_resource_mode", "Resource mode"),
        subtitle: resourceSubtitle,
        systemImage: "thermometer.medium",
        tint: resourceTint,
        badge: resourceLabel
      )
      SignalASISecurityStatusRow(
        title: t("voice_performance_circuits", "Open circuit breakers"),
        subtitle: t("voice_performance_circuits_subtitle", "Failed features and model profiles are isolated"),
        systemImage: "shield",
        tint: openCircuitCount == 0 ? .signalASIAccent : .orange,
        badge: "\(openCircuitCount)"
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.advanced.voice_models", "Voice Models"),
        subtitle: t("signalasi.advanced.voice_models_subtitle", "Manage Whisper models, benchmarks, and local ASR runtime"),
        systemImage: "waveform.badge.mic",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        VoiceWhisperModelSettingsView()
      }
    }
  }

  private var latencySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_performance_latency_section", "P50 / P95 LATENCY"))
      if metrics.isEmpty {
        SignalASISecurityStatusRow(
          title: t("voice_performance_no_samples", "No latency samples yet"),
          subtitle: t("voice_performance_no_samples_subtitle", "Complete voice tasks to populate this dashboard"),
          systemImage: "timer",
          tint: .orange,
          badge: t("voice_performance_health_no_data", "No data")
        )
      } else {
        ForEach(metrics.indices, id: \.self) { index in
          let metric = metrics[index]
          SignalASISecurityStatusRow(
            title: metricTitle(metric.0),
            subtitle: String(format: t("voice_performance_metric_samples", "%d samples"), metric.1.count),
            systemImage: "timer",
            tint: .blue,
            badge: String(
              format: t("voice_performance_latency_value", "%d / %d ms"),
              metric.1.p50Ms,
              metric.1.p95Ms
            )
          )
        }
      }
    }
  }

  private var resourceLabel: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
      return t("voice_performance_resource_normal", "Normal")
    case .fair:
      return t("voice_performance_resource_conserve", "Conserve")
    case .serious:
      return t("voice_performance_resource_degraded", "Degraded")
    case .critical:
      return t("voice_performance_resource_blocked", "Blocked")
    @unknown default:
      return t("voice_performance_resource_normal", "Normal")
    }
  }

  private var resourceTint: Color {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
      return .signalASIAccent
    case .fair:
      return .orange
    case .serious, .critical:
      return .red
    @unknown default:
      return .orange
    }
  }

  private var resourceSubtitle: String {
    if resourceConstraintCount == 0 {
      return t("voice_performance_no_constraints", "No active constraint")
    }
    return String(format: t("voice_performance_active_constraints", "%d active constraints"), resourceConstraintCount)
  }

  private var resourceConstraintCount: Int {
    summary.oomCount +
      summary.nativeCrashCount +
      summary.thermalDegradeCount +
      summary.modelVerificationFailureCount
  }

  private var openCircuitCount: Int {
    [
      summary.oomCount,
      summary.nativeCrashCount,
      summary.thermalDegradeCount,
      summary.modelVerificationFailureCount
    ].filter { $0 > 0 }.count
  }

  private func metricTitle(_ key: String) -> String {
    switch key {
    case "asr_total_ms":
      return t("voice_performance_metric_asr", "Speech end to transcript")
    case "model_first_delta_ms":
      return t("voice_performance_metric_model", "Model first output")
    case "tts_first_audio_ms":
      return t("voice_performance_metric_tts", "TTS first audio")
    case "agent_accept_ms":
      return t("voice_performance_metric_agent_accept", "Agent accepted")
    case "agent_first_progress_ms":
      return t("voice_performance_metric_agent_progress", "Agent first progress")
    case "agent_first_output_ms":
      return t("voice_performance_metric_agent_output", "Agent first output")
    default:
      return key
        .replacingOccurrences(of: "_ms", with: "")
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
    }
  }

  private func percent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIAgentPermissionAuditView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  private var tools: [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors()
  }

  private var summary: SignalASIAdvancedPermissionSummary {
    SignalASIAdvancedPermissionSummary(tools: tools)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("advanced_agent_permission_audit", "Agent Permission Audit"),
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
            title: t("advanced_agent_permission_audit", "Agent Permission Audit"),
            subtitle: t("advanced_agent_permission_audit_subtitle", "Check phone and device permissions"),
            systemImage: "checkmark.shield",
            tint: .purple,
            badge: "\(summary.permissionCount)"
          )
          auditSection
          navigationSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_permissions_title", "Permissions & Audit"))
      SignalASISecurityStatusRow(
        title: t("signalasi.advanced.native_tool_permissions", "Native tool permissions"),
        subtitle: String(
          format: t("signalasi.advanced.permission_scope_summary", "%d permissions / %d consents"),
          summary.permissionCount,
          summary.consentCount
        ),
        systemImage: "hand.raised",
        tint: .orange,
        badge: "\(summary.totalTools)"
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.advanced.available_tools", "Available tools"),
        subtitle: String(format: t("signalasi.advanced.available_tools_summary", "%d of %d tools available"), summary.availableTools, summary.totalTools),
        systemImage: "checkmark.circle",
        tint: summary.availableTools == summary.totalTools ? .signalASIAccent : .orange,
        badge: "\(summary.availableTools)"
      )
      ForEach(AgentNativeToolRisk.allCases) { risk in
        let count = tools.filter { $0.risk == risk }.count
        SignalASISecurityStatusRow(
          title: riskTitle(risk),
          subtitle: t("signalasi.advanced.risk_bucket_subtitle", "Native tool descriptors in this risk bucket"),
          systemImage: riskSystemImage(risk),
          tint: riskTint(risk),
          badge: "\(count)"
        )
      }
    }
  }

  private var navigationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.advanced.audit_destinations", "Audit Destinations"))
      SignalASISecurityNavigationRow(
        title: t("signalasi.security_center.on_device_agent_permissions", "On-device Agent Permissions"),
        subtitle: t("signalasi.security_center.on_device_agent_permissions_subtitle", "Microphone, camera, notifications, and device execution require phone-side grants"),
        systemImage: "iphone",
        tint: .signalASIAccent,
        badge: t("common_view", "View")
      ) {
        OnDeviceAgentPermissionsView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.native_tool_catalog.title", "Native Tools"),
        subtitle: t(
          "signalasi.native_tool_catalog.hero_subtitle",
          "Review iOS tool availability, risk, runtime scope, permissions, and consent boundaries"
        ),
        systemImage: "hammer",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        SignalASINativeToolCatalogView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t("signalasi.settings.model_data_sharing.subtitle", "Review metadata-only disclosure events and destination blocks"),
        systemImage: "lock.doc",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        SignalASIPrivacyDashboardView()
      }
    }
  }

  private func riskTitle(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low:
      return t("signalasi.native_tool_catalog.risk_low", "Low")
    case .medium:
      return t("signalasi.native_tool_catalog.risk_medium", "Medium")
    case .high:
      return t("signalasi.native_tool_catalog.risk_high", "High")
    case .blocked:
      return t("signalasi.native_tool_catalog.risk_blocked", "Blocked")
    }
  }

  private func riskSystemImage(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low:
      return "checkmark.circle"
    case .medium:
      return "exclamationmark.circle"
    case .high:
      return "exclamationmark.triangle"
    case .blocked:
      return "nosign"
    }
  }

  private func riskTint(_ risk: AgentNativeToolRisk) -> Color {
    switch risk {
    case .low:
      return .signalASIAccent
    case .medium:
      return .orange
    case .high:
      return .red
    case .blocked:
      return .gray
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIAdvancedPermissionSummary {
  var totalTools: Int
  var availableTools: Int
  var permissionCount: Int
  var consentCount: Int

  init(tools: [AgentNativeToolDescriptor]) {
    totalTools = tools.count
    availableTools = tools.filter { $0.availability.status == .available }.count
    permissionCount = Set(tools.flatMap { tool in
      tool.requiredPermissions.map(\.id)
    }).count
    consentCount = Set(tools.flatMap { tool in
      tool.requiredConsents.map(\.id)
    }).count
  }
}
