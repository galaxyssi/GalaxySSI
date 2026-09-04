import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIOnDeviceRuntimeView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  private let runtimeProvider = AgentIOSDefaultOnDeviceRuntimeProvider()
  private let inAppRuntimeBroker = AgentIOSInAppQemuRuntimeBroker(
    runtimeRootURL: AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL()
  )
  @State private var runtimeReceipts: [AgentNativeToolAuditRecord] = []
  @State private var selectedRuntimeReceipt: AgentNativeToolAuditRecord?
  @State private var brokerHealth = AgentIOSRuntimeBrokerHealth.unchecked

  private var packs: [AgentRuntimePackStatus] {
    Self.packStatuses()
  }

  private var runtimeAvailability: AgentNativeToolAvailability {
    runtimeProvider.availability(operation: .execute)
  }

  private var brokerAvailability: AgentNativeToolAvailability {
    inAppRuntimeBroker.availability()
  }

  private var runtimeReady: Bool {
    runtimeAvailability.status == .available && brokerHealth.isReady
  }

  private var runtimeStatusMessage: String {
    runtimeAvailability.reason.ifBlank(brokerStatusMessage.ifBlank(t(
      "cc_runtime_overview_subtitle",
      "Run the embedded Debian runtime privately inside this iOS app"
    )))
  }

  private var brokerStatusMessage: String {
    if case .checking = brokerHealth {
      return t("cc_runtime_broker_checking", "Checking the paired local Linux runtime service")
    }
    return brokerHealth.message
  }

  private var brokerBadge: String {
    switch brokerHealth {
    case .ready:
      return t("cc_status_ready", "Ready")
    case .checking:
      return t("galaxyssi.status.loading", "Checking")
    case .unchecked, .notConfigured:
      return t("cc_status_not_configured", "Not configured")
    case .unavailable:
      return t("cc_status_unavailable", "Unavailable")
    }
  }

  private var runtimeBadge: String {
    if runtimeReady {
      return t("cc_status_ready", "Ready")
    }
    if case .checking = brokerHealth {
      return t("galaxyssi.status.loading", "Checking")
    }
    return t("status_needs_setup", "Needs Setup")
  }

  private var brokerTint: Color {
    switch brokerHealth {
    case .ready:
      return .galaxySSIAccent
    case .checking:
      return .blue
    case .unchecked, .notConfigured, .unavailable:
      return .orange
    }
  }

  private var readyPackCount: Int {
    packs.filter { $0.state == .ready }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button(action: refreshBrokerHealth) {
            Image(systemName: isBrokerChecking ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .disabled(isBrokerChecking)
          .accessibilityLabel(Text(t("cc_runtime_refresh_status", "Refresh runtime status")))
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t(runtimeReady ? "cc_runtime_ready_title" : "cc_runtime_setup_title",
                     runtimeReady ? "Embedded Debian runtime is ready" : "On-device runtime needs setup"),
            subtitle: runtimeStatusMessage,
            systemImage: "terminal",
            tint: runtimeReady ? .galaxySSIAccent : .orange,
            badge: runtimeBadge
          )
          GalaxySSIRuntimeMetricStrip(metrics: runtimeMetrics)
          managementSection
          offlineBootstrapSection
          receiptSection
          securitySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(item: $selectedRuntimeReceipt) { receipt in
      GalaxySSIRuntimeReceiptDetailSheet(receipt: receipt)
    }
    .onAppear {
      refreshRuntimeReceipts()
      refreshBrokerHealth()
    }
  }

  private var runtimeMetrics: [GalaxySSIRuntimeMetric] {
    [
      GalaxySSIRuntimeMetric(
        value: runtimeReady ? "1" : "0",
        label: t("cc_runtime_metric_ready", "Ready broker"),
        tint: runtimeReady ? .galaxySSIAccent : .orange
      ),
      GalaxySSIRuntimeMetric(
        value: "\(runtimeReceipts.count)",
        label: t("cc_runtime_metric_total", "Recent runs"),
        tint: .blue
      ),
      GalaxySSIRuntimeMetric(
        value: "\(readyPackCount)",
        label: t("cc_runtime_metric_languages", "Optional packs"),
        tint: readyPackCount > 0 ? .galaxySSIAccent : .gray
      )
    ]
  }

  private var isBrokerChecking: Bool {
    if case .checking = brokerHealth { return true }
    return false
  }

  private var managementSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_section_management", "Runtime Management"))
      GalaxySSISecurityStatusRow(
        title: t("cc_runtime_lifecycle_title", "Guest lifecycle"),
        subtitle: runtimeStatusMessage,
        systemImage: "link",
        tint: runtimeReady ? .galaxySSIAccent : .orange,
        badge: runtimeBadge
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_runtime_broker_title", "In-app Linux Runtime"),
        subtitle: brokerStatusMessage.ifBlank(brokerAvailability.reason.ifBlank(t(
          "cc_runtime_broker_connected",
          "The embedded Debian service is ready"
        ))),
        systemImage: "link",
        tint: brokerTint,
        badge: brokerBadge
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_runtime_linux_requirement_title", "Linux runtime requirement"),
        subtitle: t(
          "cc_runtime_linux_requirement_subtitle",
          "The embedded Debian runtime verifies Linux 1.3.9 or later before it accepts execution"
        ),
        systemImage: "checkmark.shield",
        tint: brokerTint,
        badge: "1.3.9+"
      )
      GalaxySSISecurityNavigationRow(
        title: t("cc_runtime_software_center_title", "Software Center"),
        subtitle: t(
          "cc_runtime_software_center_subtitle",
          "Find and install verified language, browser, and media tools"
        ),
        systemImage: "shippingbox",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        GalaxySSIRuntimeSoftwareCenterView()
      }
    }
  }

  private var receiptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_section_receipts", "Recent Execution Receipts"))
      if runtimeReceipts.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_runtime_receipt_empty_title", "No runtime executions yet"),
          subtitle: t("cc_runtime_receipt_empty_subtitle", "Verified execution receipts appear here after local runtime tasks run"),
          systemImage: "clock.arrow.circlepath",
          tint: .gray,
          badge: ""
        )
      } else {
        ForEach(runtimeReceipts) { receipt in
          GalaxySSISecurityActionRow(
            title: receiptTimestamp(receipt),
            subtitle: receiptSummary(receipt),
            systemImage: receiptSystemImage(receipt),
            tint: receiptTint(receipt),
            badge: receipt.status.rawValue
          ) {
            selectedRuntimeReceipt = receipt
          }
        }
      }
    }
  }

  private var offlineBootstrapSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_section_offline", "Offline Runtime Bundle"))
      if offlineRuntimeIncluded {
        GalaxySSISecurityStatusRow(
          title: t("cc_runtime_offline_export_title", "Embedded Linux 1.3.9 runtime"),
          subtitle: t(
            "cc_runtime_offline_export_subtitle",
            "Includes the Debian baseline and no-JIT QEMU runtime for the iOS app sandbox"
          ),
          systemImage: "cpu",
          tint: .galaxySSIAccent,
          badge: t("cc_runtime_offline_included", "Included")
        )
      } else {
        GalaxySSISecurityStatusRow(
          title: t("cc_runtime_offline_missing_title", "Offline Linux bundle unavailable"),
          subtitle: t(
            "cc_runtime_offline_missing_subtitle",
            "Install a full offline IPA to include the Linux 1.3.9 deployment payload"
          ),
          systemImage: "shippingbox",
          tint: .orange,
          badge: t("cc_status_unavailable", "Unavailable")
        )
      }
    }
  }

  private var offlineRuntimeIncluded: Bool {
    Bundle.main.url(
      forResource: "linux-base-1.3.9-aarch64",
      withExtension: "Image",
      subdirectory: "runtime-bootstrap"
    ) != nil
  }

  private var securitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_section_security", "Isolation & Policy"))
      GalaxySSISecurityStatusRow(
        title: t("cc_runtime_isolation_title", "Task Workspace Isolation"),
        subtitle: t("cc_runtime_isolation_subtitle", "Each task gets CPU, memory, storage, time, output, and artifact limits"),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("cc_status_ready", "Ready")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_runtime_network_title", "Guest Network Policy"),
        subtitle: t(
          "cc_runtime_network_broker_subtitle",
          "The embedded Debian guest uses host-mediated networking when a task explicitly enables it"
        ),
        systemImage: "network",
        tint: .blue,
        badge: t("cc_runtime_network_host_mediated", "Host mediated")
      )
    }
  }

  private func refreshRuntimeReceipts() {
    let paths = AgentNativeToolDefaultStorePaths(
      rootURL: AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
    )
    let store = FileAgentNativeToolAuditStore(fileURL: paths.auditFileURL)
    runtimeReceipts = store.list(
      limit: 12,
      toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      status: nil
    )
  }

  private func refreshBrokerHealth() {
    guard brokerAvailability.status == .available else {
      brokerHealth = .notConfigured(brokerAvailability.reason)
      return
    }
    brokerHealth = .checking
    let deadline = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      + AgentIOSInAppQemuRuntimeBroker.coldBootHealthTimeoutMillis
    DispatchQueue.global(qos: .userInitiated).async {
      let health = AgentIOSRuntimeBrokerHealthChecker.check(
        broker: inAppRuntimeBroker,
        deadlineEpochMillis: deadline,
        context: AgentNativeToolInvocationContext(
          invocationId: "runtime-dashboard-\(UUID().uuidString)"
        )
      )
      DispatchQueue.main.async {
        brokerHealth = health
      }
    }
  }

  private func receiptTimestamp(_ receipt: AgentNativeToolAuditRecord) -> String {
    GalaxySSISecurityFormatter.time(
      Date(timeIntervalSince1970: Double(receipt.finishedAtEpochMillis) / 1_000),
      unknown: t("galaxyssi.status.unknown", "Unknown"),
      language: interfaceLanguage
    )
  }

  private func receiptSummary(_ receipt: AgentNativeToolAuditRecord) -> String {
    let identifier = String(receipt.invocationId.prefix(16))
    return "\(receipt.durationMillis) ms / \(identifier)"
  }

  private func receiptSystemImage(_ receipt: AgentNativeToolAuditRecord) -> String {
    switch receipt.status {
    case .succeeded:
      return "checkmark.seal"
    case .failed, .verificationFailed, .timedOut:
      return "exclamationmark.triangle"
    case .rejected, .unavailable:
      return "exclamationmark.circle"
    case .cancelled:
      return "xmark.circle"
    }
  }

  private func receiptTint(_ receipt: AgentNativeToolAuditRecord) -> Color {
    switch receipt.status {
    case .succeeded:
      return .galaxySSIAccent
    case .failed, .verificationFailed, .timedOut:
      return .red
    case .rejected, .unavailable:
      return .orange
    case .cancelled:
      return .gray
    }
  }

  static func packStatuses(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    fileManager: FileManager = .default
  ) -> [AgentRuntimePackStatus] {
    AgentRuntimePackCatalogPolicy.requiredPacks.map { packId in
      packStatus(packId, runtimeRootURL: runtimeRootURL, fileManager: fileManager)
    }
  }

  static func packStatus(
    _ packId: String,
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    fileManager: FileManager = .default
  ) -> AgentRuntimePackStatus {
    let installed = AgentIOSRuntimePackInstaller(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager
    )
      .status(packId: packId)
    if packId == "node-js",
       installed.state == .ready,
       let version = installed.manifest?.version,
       AgentIOSQemuRuntimeController.shared.usesInstalledNodePack(version: version) {
      return installed
    }
    if let embedded = AgentIOSQemuRuntimeController.shared.embeddedPackStatus(packID: packId) {
      return embedded
    }
    return installed
  }

  static func packTitle(_ id: String, language: String) -> String {
    switch id {
    case "linux-base":
      return GalaxySSILocalization.string("cc_runtime_pack_linux", fallback: "Linux base", language: language)
    case "python-uv":
      return GalaxySSILocalization.string("cc_runtime_pack_python", fallback: "Python and uv", language: language)
    case "node-js":
      return GalaxySSILocalization.string("cc_runtime_pack_node", fallback: "Node.js and JavaScript", language: language)
    case "browser-automation":
      return GalaxySSILocalization.string("cc_runtime_pack_browser", fallback: "Browser automation", language: language)
    case "cpp":
      return "C / C++"
    case "ffmpeg":
      return "FFmpeg"
    default:
      return id.uppercased()
    }
  }

  static func packSubtitle(_ pack: AgentRuntimePackStatus, language: String) -> String {
    if let manifest = pack.manifest {
      return "\(manifest.version) / \(formatBytes(manifest.installedSizeBytes)) / \(manifest.license.ifBlank("unknown"))"
    }
    if pack.state == .ready {
      switch pack.id {
      case "linux-base":
        return GalaxySSILocalization.string(
          "cc_runtime_pack_linux_embedded",
          fallback: "Embedded GalaxySSI Linux 1.3.9",
          language: language
        )
      case "node-js":
        return GalaxySSILocalization.string(
          "cc_runtime_pack_node_embedded",
          fallback: "Embedded Node.js 24.18.0",
          language: language
        )
      default:
        break
      }
    }
    return GalaxySSILocalization.string(
      "cc_runtime_pack_subtitle",
      fallback: pack.reason.ifBlank("Signed modular runtime pack"),
      language: language
    )
  }

  static func packBadge(_ pack: AgentRuntimePackStatus, language: String) -> String {
    switch pack.state {
    case .ready:
      return GalaxySSILocalization.string("cc_status_ready", fallback: "Ready", language: language)
    case .notInstalled:
      return GalaxySSILocalization.string("cc_runtime_catalog_install", fallback: "Install", language: language)
    case .invalid, .incompatible:
      return GalaxySSILocalization.string("cc_runtime_catalog_repair", fallback: "Repair", language: language)
    }
  }

  static func packTint(_ pack: AgentRuntimePackStatus) -> Color {
    switch pack.state {
    case .ready:
      return .galaxySSIAccent
    case .notInstalled:
      return .blue
    case .invalid, .incompatible:
      return .orange
    }
  }

  static func formatBytes(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 B" }
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var index = 0
    while value >= 1024 && index < units.count - 1 {
      value /= 1024
      index += 1
    }
    return index == 0 ? "\(Int(value)) \(units[index])" : String(format: "%.1f %@", value, units[index])
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIRuntimeReceiptDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var receipt: AgentNativeToolAuditRecord

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_runtime_receipt_detail_title", "Runtime receipt"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Color.clear.frame(width: 44, height: 44)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_runtime_receipt_execution_title", "Local runtime execution"),
            subtitle: t(
              "cc_runtime_receipt_execution_subtitle",
              "A locally persisted native-tool receipt without source or workspace content"
            ),
            systemImage: systemImage,
            tint: tint,
            badge: receipt.status.rawValue
          )
          GalaxySSISecuritySectionTitle(title: t("cc_runtime_receipt_section_execution", "Execution"))
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_receipt_request_id", "Request ID"),
            subtitle: receipt.invocationId,
            systemImage: "number",
            tint: .blue,
            badge: "",
            monospacedSubtitle: true
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_receipt_timing", "Timing"),
            subtitle: timingSummary,
            systemImage: "clock",
            tint: tint,
            badge: ""
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_receipt_result", "Result"),
            subtitle: receipt.errorCode.ifBlank(t("cc_runtime_receipt_result_success", "Completed without a runtime error")),
            systemImage: systemImage,
            tint: tint,
            badge: receipt.status.rawValue
          )
          GalaxySSISecuritySectionTitle(title: t("cc_runtime_receipt_section_integrity", "Integrity"))
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_receipt_input_hash", "Input hash"),
            subtitle: receipt.inputSha256.ifBlank(t("galaxyssi.status.unknown", "Unknown")),
            systemImage: "lock.doc",
            tint: .galaxySSIAccent,
            badge: "",
            monospacedSubtitle: true
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_receipt_output_hash", "Output hash"),
            subtitle: receipt.outputSha256.ifBlank(t("galaxyssi.status.unknown", "Unknown")),
            systemImage: "checkmark.shield",
            tint: .galaxySSIAccent,
            badge: "",
            monospacedSubtitle: true
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private var timingSummary: String {
    let completed = GalaxySSISecurityFormatter.time(
      Date(timeIntervalSince1970: Double(receipt.finishedAtEpochMillis) / 1_000),
      unknown: t("galaxyssi.status.unknown", "Unknown"),
      language: interfaceLanguage
    )
    return "\(completed) / \(receipt.durationMillis) ms"
  }

  private var systemImage: String {
    switch receipt.status {
    case .succeeded:
      return "checkmark.seal"
    case .failed, .verificationFailed, .timedOut:
      return "exclamationmark.triangle"
    case .rejected, .unavailable:
      return "exclamationmark.circle"
    case .cancelled:
      return "xmark.circle"
    }
  }

  private var tint: Color {
    switch receipt.status {
    case .succeeded:
      return .galaxySSIAccent
    case .failed, .verificationFailed, .timedOut:
      return .red
    case .rejected, .unavailable:
      return .orange
    case .cancelled:
      return .gray
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIRuntimeSoftwareCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var searchText = ""
  @State private var packs = GalaxySSIOnDeviceRuntimeView.packStatuses()
    .filter { !["linux-base", "python-uv"].contains($0.id) }
  @State private var catalogEntries: [AgentRuntimePackCatalogEntry] = []
  @State private var fileImporterPresented = false
  @State private var isInstalling = false
  @State private var isUninstalling = false
  @State private var isRefreshingCatalog = false
  @State private var installingPackID: String?
  @State private var uninstallCandidatePackID: String?
  @State private var selectedCatalogEntry: AgentRuntimePackCatalogEntry?
  @State private var installMessage = ""
  @State private var catalogMessage = ""

  private var filteredPacks: [AgentRuntimePackStatus] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return packs }
    return packs.filter { pack in
      pack.id.lowercased().contains(query) ||
        GalaxySSIOnDeviceRuntimeView.packTitle(pack.id, language: interfaceLanguage)
          .lowercased()
          .contains(query)
    }
  }

  private var installedCount: Int {
    packs.filter { $0.state == .ready }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_runtime_software_center_title", "Software Center"),
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
            title: t("cc_runtime_software_overview_title", "Trusted software catalog"),
            subtitle: t(
              "cc_runtime_software_overview_subtitle",
              "Software runs inside an isolated iOS-local runtime; verified sources and signatures gate installation"
            ),
            systemImage: "shippingbox",
            tint: .blue,
            badge: t("cc_runtime_software_verified_badge", "Signed and verified")
          )
          GalaxySSIRuntimeMetricStrip(metrics: [
            GalaxySSIRuntimeMetric(
              value: "\(installedCount)",
              label: t("cc_runtime_software_metric_installed", "Installed"),
              tint: installedCount == packs.count ? .galaxySSIAccent : .orange
            ),
            GalaxySSIRuntimeMetric(
              value: "\(packs.count)",
              label: t("cc_runtime_software_metric_available", "Available"),
              tint: .blue
            ),
            GalaxySSIRuntimeMetric(
              value: "iOS",
              label: t("cc_runtime_software_metric_catalog", "Catalog"),
              tint: .galaxySSIInsightText
            )
          ])
          searchSection
          catalogSection
          advancedSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: [Self.runtimePackType],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
    .confirmationDialog(
      uninstallTitle,
      isPresented: Binding(
        get: { uninstallCandidatePackID != nil },
        set: { if !$0 { uninstallCandidatePackID = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(t("cc_runtime_software_uninstall_action", "Uninstall"), role: .destructive) {
        guard let packId = uninstallCandidatePackID else { return }
        uninstallCandidatePackID = nil
        uninstall(packId: packId)
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        uninstallCandidatePackID = nil
      }
    } message: {
      Text(uninstallMessage)
    }
    .sheet(item: $selectedCatalogEntry) { entry in
      GalaxySSIRuntimePackDetailSheet(
        entry: entry,
        installed: GalaxySSIOnDeviceRuntimeView.packStatus(entry.packId),
        onInstall: {
          install(entry)
        },
        onUninstall: {
          uninstallCandidatePackID = entry.packId
        }
      )
    }
    .task {
      loadCachedCatalog()
    }
  }

  private var searchSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_software_section_find", "Find Software"))
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.galaxySSITextSecondary)
        TextField(t("cc_runtime_software_search_hint", "Software name"), text: $searchText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !searchText.isEmpty {
          Button {
            searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.galaxySSITextSecondary)
          }
          .buttonStyle(.plain)
        }
      }
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .frame(height: 40)
      .background(Color.galaxySSISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var catalogSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        GalaxySSISecuritySectionTitle(title: t("cc_runtime_software_section_catalog", "Compatible Software"))
        Spacer()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_runtime_catalog_refresh_action", "Refresh signed catalog"),
        subtitle: catalogMessage.ifBlank(t(
          "cc_runtime_catalog_refresh_action_subtitle",
          "Load compatible packs from the verified GalaxySSI release catalog"
        )),
        systemImage: isRefreshingCatalog ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
        tint: isRefreshingCatalog ? .blue : .galaxySSIAccent,
        badge: isRefreshingCatalog
          ? t("cc_runtime_catalog_refreshing", "Refreshing")
          : t("cc_runtime_catalog_refresh_badge", "Refresh")
      ) {
        guard !isRefreshingCatalog && !isInstalling && !isUninstalling else { return }
        refreshCatalog()
      }
      if catalogEntries.isEmpty && filteredPacks.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_runtime_software_no_results_title", "No compatible software found"),
          subtitle: t("cc_runtime_catalog_empty_subtitle", "Refresh the signed catalog to see installable runtime packs"),
          systemImage: "magnifyingglass",
          tint: .orange,
          badge: ""
        )
      } else if !catalogEntries.isEmpty && filteredCatalogEntries.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_runtime_software_no_results_title", "No compatible software found"),
          subtitle: String(format: t(
            "cc_runtime_software_no_results_subtitle",
            "No verified software pack matches \"%@\""
          ), searchText),
          systemImage: "magnifyingglass",
          tint: .orange,
          badge: ""
        )
      } else {
        if catalogEntries.isEmpty {
          ForEach(filteredPacks) { pack in
            GalaxySSISecurityActionRow(
              title: GalaxySSIOnDeviceRuntimeView.packTitle(pack.id, language: interfaceLanguage),
              subtitle: GalaxySSIOnDeviceRuntimeView.packSubtitle(pack, language: interfaceLanguage),
              systemImage: pack.id == "ffmpeg" ? "film" : "shippingbox",
              tint: GalaxySSIOnDeviceRuntimeView.packTint(pack),
              badge: GalaxySSIOnDeviceRuntimeView.packBadge(pack, language: interfaceLanguage)
            ) {
              guard pack.state == .ready && !isInstalling && !isUninstalling && !isRefreshingCatalog else { return }
              uninstallCandidatePackID = pack.id
            }
          }
        } else {
          ForEach(filteredCatalogEntries) { entry in
            catalogEntryRow(entry)
          }
        }
      }
    }
  }

  private var advancedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_runtime_software_section_advanced", "Advanced Installation"))
      GalaxySSISecurityActionRow(
        title: t("cc_runtime_import_title", "Install runtime pack"),
        subtitle: installMessage.ifBlank(t("cc_runtime_import_subtitle", "Import a GalaxySSI-signed .sarpack package")),
        systemImage: isInstalling ? "arrow.triangle.2.circlepath" : "tray.and.arrow.down",
        tint: isInstalling ? .blue : .orange,
        badge: isInstalling
          ? t("cc_runtime_import_installing", "Installing")
          : t("cc_runtime_import_action", "Choose file")
      ) {
        guard !isInstalling && !isUninstalling else { return }
        fileImporterPresented = true
      }
    }
  }

  private var filteredCatalogEntries: [AgentRuntimePackCatalogEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return catalogEntries }
    return catalogEntries.filter { entry in
      entry.packId.lowercased().contains(query) ||
        GalaxySSIOnDeviceRuntimeView.packTitle(entry.packId, language: interfaceLanguage)
          .lowercased()
          .contains(query)
    }
  }

  private var uninstallTitle: String {
    let packId = uninstallCandidatePackID ?? ""
    let title = GalaxySSIOnDeviceRuntimeView.packTitle(packId, language: interfaceLanguage)
    return String(format: t("cc_runtime_software_uninstall_title", "Uninstall %@?"), title)
  }

  private var uninstallMessage: String {
    let packId = uninstallCandidatePackID ?? ""
    let title = GalaxySSIOnDeviceRuntimeView.packTitle(packId, language: interfaceLanguage)
    return String(format: t(
      "cc_runtime_software_uninstall_message",
      "Remove %@ from this device? Dependent runtime packs must be removed first."
    ), title)
  }

  @ViewBuilder
  private func catalogEntryRow(_ entry: AgentRuntimePackCatalogEntry) -> some View {
    let installed = GalaxySSIOnDeviceRuntimeView.packStatus(entry.packId)
    let ready = installed.state == .ready && installed.manifest?.version == entry.version
    let installing = installingPackID == entry.packId
    GalaxySSISecurityActionRow(
      title: GalaxySSIOnDeviceRuntimeView.packTitle(entry.packId, language: interfaceLanguage),
      subtitle: catalogEntrySubtitle(entry),
      systemImage: entry.packId == "ffmpeg" ? "film" : "shippingbox",
      tint: ready ? .galaxySSIAccent : (installing ? .blue : .orange),
      badge: ready
        ? t("cc_status_ready", "Ready")
        : (installing ? t("cc_runtime_catalog_installing", "Installing") : t("cc_runtime_catalog_install", "Install"))
    ) {
      guard !installing && !isInstalling && !isUninstalling && !isRefreshingCatalog else { return }
      selectedCatalogEntry = entry
    }
  }

  private func catalogEntrySubtitle(_ entry: AgentRuntimePackCatalogEntry) -> String {
    let base = "\(entry.version) / \(GalaxySSIOnDeviceRuntimeView.formatBytes(entry.installedSizeBytes)) / \(entry.license)"
    return entry.releaseNotes.isEmpty ? base : "\(base) / \(entry.releaseNotes)"
  }

  private func loadCachedCatalog() {
    let manager = AgentIOSRuntimePackCatalogManager(languageTag: interfaceLanguage)
    catalogEntries = manager.cachedCompatible()
  }

  private func refreshCatalog() {
    isRefreshingCatalog = true
    catalogMessage = t("cc_runtime_catalog_refreshing_message", "Refreshing signed catalog...")
    DispatchQueue.global(qos: .userInitiated).async {
      let manager = AgentIOSRuntimePackCatalogManager(languageTag: interfaceLanguage)
      let outcome: Result<[AgentRuntimePackCatalogEntry], Error>
      do {
        _ = try manager.refresh()
        outcome = .success(manager.cachedCompatible())
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        isRefreshingCatalog = false
        switch outcome {
        case .success(let entries):
          catalogEntries = entries
          catalogMessage = String(
            format: t("cc_runtime_catalog_refresh_success", "Loaded %d compatible packs"),
            entries.count
          )
        case .failure(let error):
          catalogMessage = error.localizedDescription.ifBlank(
            t("cc_runtime_catalog_refresh_failed", "Signed catalog refresh failed")
          )
        }
      }
    }
  }

  private func install(_ entry: AgentRuntimePackCatalogEntry) {
    isInstalling = true
    installingPackID = entry.packId
    installMessage = String(
      format: t("cc_runtime_catalog_installing_message", "Downloading %@..."),
      entry.packId
    )
    DispatchQueue.global(qos: .userInitiated).async {
      let manager = AgentIOSRuntimePackCatalogManager(languageTag: interfaceLanguage)
      let outcome: Result<[AgentRuntimePackInstallResult], Error>
      do {
        outcome = .success(try manager.downloadAndInstall(
          entry: entry,
          onDownloadProgress: { progress in
            guard progress.totalBytes > 0 else { return }
            let percent = min(100, max(0, Int(progress.downloadedBytes * 100 / progress.totalBytes)))
            DispatchQueue.main.async {
              installMessage = String(
                format: t("cc_runtime_catalog_downloading_progress", "Downloading %@ (%d%%)"),
                entry.packId,
                percent
              )
            }
          },
          onInstallProgress: { progress in
            DispatchQueue.main.async {
              installMessage = String(
                format: t("cc_runtime_catalog_installing_progress", "Installing %@: %@"),
                entry.packId,
                progress.stage.rawValue.lowercased()
              )
            }
          }
        ))
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        isInstalling = false
        installingPackID = nil
        switch outcome {
        case .success(let results):
          packs = GalaxySSIOnDeviceRuntimeView.packStatuses()
            .filter { !["linux-base", "python-uv"].contains($0.id) }
          installMessage = String(
            format: t("cc_runtime_catalog_install_success", "Installed %@ (%d pack(s))"),
            entry.packId,
            results.count
          )
        case .failure(let error):
          installMessage = error.localizedDescription.ifBlank(
            t("cc_runtime_catalog_install_failed", "Runtime pack installation failed")
          )
        }
      }
    }
  }

  private func uninstall(packId: String) {
    guard !isInstalling && !isUninstalling else { return }
    isUninstalling = true
    installMessage = String(
      format: t("cc_runtime_software_uninstalling", "Removing %@..."),
      GalaxySSIOnDeviceRuntimeView.packTitle(packId, language: interfaceLanguage)
    )
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome: Result<Bool, Error>
      do {
        outcome = .success(try AgentIOSRuntimePackInstaller().uninstall(packId: packId))
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        isUninstalling = false
        switch outcome {
        case .success(let removed):
          packs = GalaxySSIOnDeviceRuntimeView.packStatuses()
            .filter { !["linux-base", "python-uv"].contains($0.id) }
          let title = GalaxySSIOnDeviceRuntimeView.packTitle(packId, language: interfaceLanguage)
          installMessage = removed
            ? String(format: t("cc_runtime_software_uninstalled", "Removed %@"), title)
            : String(format: t("cc_runtime_software_not_installed", "%@ is not installed"), title)
        case .failure(let error):
          installMessage = error.localizedDescription.ifBlank(
            t("cc_runtime_software_uninstall_failed", "Runtime pack removal failed")
          )
        }
      }
    }
  }

  private static var runtimePackType: UTType {
    UTType(filenameExtension: "sarpack") ?? .data
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    guard case .success(let urls) = result, let source = urls.first else { return }
    guard source.startAccessingSecurityScopedResource() else {
      installMessage = t("cc_runtime_import_access_failed", "The selected runtime pack could not be opened")
      return
    }
    isInstalling = true
    installMessage = t("cc_runtime_import_preparing", "Verifying runtime pack...")
    DispatchQueue.global(qos: .userInitiated).async {
      let installer = AgentIOSRuntimePackInstaller()
      let outcome: Result<AgentRuntimePackInstallResult, Error>
      do {
        outcome = .success(try installer.install(source: source))
      } catch {
        outcome = .failure(error)
      }
      source.stopAccessingSecurityScopedResource()
      DispatchQueue.main.async {
        isInstalling = false
        switch outcome {
        case .success(let result):
          installMessage = String(
            format: t("cc_runtime_import_success", "Installed %@ %@"),
            result.packId,
            result.version
          )
          packs = GalaxySSIOnDeviceRuntimeView.packStatuses()
            .filter { !["linux-base", "python-uv"].contains($0.id) }
        case .failure(let error):
          installMessage = error.localizedDescription.ifBlank(
            t("cc_runtime_import_failed", "Runtime pack installation failed")
          )
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIRuntimePackDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var entry: AgentRuntimePackCatalogEntry
  var installed: AgentRuntimePackStatus
  var onInstall: () -> Void
  var onUninstall: () -> Void

  private var isReady: Bool {
    installed.state == .ready && installed.manifest?.version == entry.version
  }

  private var dependencies: String {
    let values = entry.dependencies.map {
      GalaxySSIOnDeviceRuntimeView.packTitle($0, language: interfaceLanguage)
    }
    return values.isEmpty ? t("cc_runtime_catalog_no_dependencies", "No dependencies") : values.joined(separator: ", ")
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_runtime_catalog_details_title", "Runtime pack details"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Color.clear.frame(width: 44, height: 44)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: GalaxySSIOnDeviceRuntimeView.packTitle(entry.packId, language: interfaceLanguage),
            subtitle: entry.releaseNotes.ifBlank(t("cc_runtime_catalog_no_release_notes", "No release notes")),
            systemImage: entry.packId == "ffmpeg" ? "film" : "shippingbox",
            tint: isReady ? .galaxySSIAccent : .blue,
            badge: isReady ? t("cc_status_ready", "Ready") : t("cc_runtime_catalog_install", "Install")
          )
          GalaxySSISecuritySectionTitle(title: t("cc_runtime_catalog_details_section", "Package details"))
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_id", "Package ID"),
            subtitle: entry.packId,
            systemImage: "number",
            tint: .blue,
            badge: "",
            monospacedSubtitle: true
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_version", "Version"),
            subtitle: entry.version,
            systemImage: "tag",
            tint: .blue,
            badge: ""
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_architecture", "Architecture"),
            subtitle: entry.architecture,
            systemImage: "cpu",
            tint: .blue,
            badge: ""
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_size", "Storage"),
            subtitle: "\(GalaxySSIOnDeviceRuntimeView.formatBytes(entry.archiveSizeBytes)) / \(GalaxySSIOnDeviceRuntimeView.formatBytes(entry.installedSizeBytes))",
            systemImage: "internaldrive",
            tint: .blue,
            badge: ""
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_license", "License"),
            subtitle: entry.license,
            systemImage: "doc.text",
            tint: .blue,
            badge: ""
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_runtime_catalog_detail_dependencies", "Dependencies"),
            subtitle: dependencies,
            systemImage: "arrow.triangle.branch",
            tint: .blue,
            badge: ""
          )
          GalaxySSISecurityPrimaryButton(
            title: isReady
              ? t("cc_runtime_catalog_reinstall", "Reinstall")
              : t("cc_runtime_catalog_install", "Install"),
            systemImage: isReady ? "arrow.clockwise" : "arrow.down.circle",
            tint: .galaxySSIAccent
          ) {
            dismiss()
            DispatchQueue.main.async {
              onInstall()
            }
          }
          if installed.state == .ready {
            Button(role: .destructive) {
              dismiss()
              DispatchQueue.main.async {
                onUninstall()
              }
            } label: {
              Label(
                t("cc_runtime_software_uninstall_action", "Uninstall"),
                systemImage: "trash"
              )
              .font(.system(size: 16, weight: .semibold))
              .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIRuntimeMetric: Identifiable {
  var value: String
  var label: String
  var tint: Color

  var id: String { label }
}

private struct GalaxySSIRuntimeMetricStrip: View {
  var metrics: [GalaxySSIRuntimeMetric]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(metrics) { metric in
        VStack(alignment: .leading, spacing: 4) {
          Text(metric.value)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(metric.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          Text(metric.label)
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
  }
}
