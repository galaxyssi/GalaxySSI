import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SignalASIOnDeviceRuntimeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  private let runtimeProvider = AgentIOSDefaultOnDeviceRuntimeProvider()
  @State private var isRecoveringLinuxBase = false
  @State private var linuxBaseRecoveryMessage = ""

  private var packs: [AgentRuntimePackStatus] {
    Self.packStatuses()
  }

  private var runtimeAvailability: AgentNativeToolAvailability {
    runtimeProvider.availability(operation: .execute)
  }

  private var runtimeReady: Bool {
    runtimeAvailability.status == .available
  }

  private var readyPackCount: Int {
    packs.filter { $0.state == .ready }.count
  }

  private var readyLanguageCount: Int {
    guard runtimeReady else { return 0 }
    return AgentRuntimeLanguage.allCases.filter { language in
      let pack = packs.first { $0.id == language.requiredPack }
      return pack?.state == .ready && pack?.manifest?.capabilities.contains(language.requiredCapability) == true
    }.count
  }

  private var linuxBasePack: AgentRuntimePackStatus? {
    packs.first { $0.id == "linux-base" }
  }

  private var linuxBaseNeedsRecovery: Bool {
    guard let linuxBasePack,
          linuxBasePack.state == .ready,
          let version = linuxBasePack.manifest?.version else {
      return true
    }
    return !AgentRuntimePackCatalogPolicy.meetsLinuxBaseRecoveryBaseline(version)
  }

  private var linuxBaseRecoveryBadge: String {
    if isRecoveringLinuxBase {
      return t("cc_runtime_recovery_in_progress", "Recovering")
    }
    if linuxBaseNeedsRecovery {
      return t("cc_runtime_catalog_repair", "Repair")
    }
    return linuxBasePack?.manifest?.version ?? AgentRuntimePackCatalogPolicy.linuxBaseRecoveryVersion
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
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
            title: t(runtimeReady ? "cc_runtime_ready_title" : "cc_runtime_setup_title",
                     runtimeReady ? "iOS-local runtime is ready" : "On-device runtime needs setup"),
            subtitle: runtimeAvailability.reason.ifBlank(t(
              "cc_runtime_overview_subtitle",
              "Signed packs and an isolated guest provide language and media tools without inheriting app permissions"
            )),
            systemImage: "terminal",
            tint: runtimeReady ? .signalASIAccent : .orange,
            badge: runtimeReady ? t("cc_status_ready", "Ready") : t("cc_status_not_configured", "Not configured")
          )
          SignalASIRuntimeMetricStrip(metrics: runtimeMetrics)
          managementSection
          environmentSection
          receiptSection
          securitySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var runtimeMetrics: [SignalASIRuntimeMetric] {
    [
      SignalASIRuntimeMetric(
        value: "\(readyPackCount)",
        label: t("cc_runtime_metric_ready", "Ready packs"),
        tint: readyPackCount == packs.count ? .signalASIAccent : .orange
      ),
      SignalASIRuntimeMetric(
        value: "\(packs.count)",
        label: t("cc_runtime_metric_total", "Total packs"),
        tint: .blue
      ),
      SignalASIRuntimeMetric(
        value: "\(readyLanguageCount)",
        label: t("cc_runtime_metric_languages", "Languages"),
        tint: runtimeReady ? .signalASIAccent : .gray
      )
    ]
  }

  private var managementSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_section_management", "Runtime Management"))
      SignalASISecurityStatusRow(
        title: t("cc_runtime_lifecycle_title", "Guest lifecycle"),
        subtitle: runtimeAvailability.reason.ifBlank(t("cc_runtime_lifecycle_subtitle", "Start, health, restart backoff, and recovery state")),
        systemImage: "link",
        tint: runtimeReady ? .signalASIAccent : .orange,
        badge: runtimeReady ? t("cc_runtime_lifecycle_ready", "Ready") : t("cc_runtime_lifecycle_no_controller", "Not packaged")
      )
      SignalASISecurityActionRow(
        title: t("cc_runtime_recovery_title", "Recover Linux 1.3.9"),
        subtitle: linuxBaseRecoveryMessage.ifBlank(t(
          "cc_runtime_recovery_subtitle",
          "Verify and atomically replace the signed Linux base; conversation project workspaces are retained"
        )),
        systemImage: "arrow.clockwise",
        tint: linuxBaseNeedsRecovery ? .orange : .signalASIAccent,
        badge: linuxBaseRecoveryBadge
      ) {
        recoverLinuxBase()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_runtime_software_center_title", "Software Center"),
        subtitle: t("cc_runtime_software_center_subtitle", "Find and install verified language, browser, and media tools"),
        systemImage: "shippingbox",
        tint: softwareReadyCount == softwarePackCount ? .signalASIAccent : .blue,
        badge: String(format: t("cc_runtime_software_center_status", "Installed %d/%d"), softwareReadyCount, softwarePackCount)
      ) {
        SignalASIRuntimeSoftwareCenterView()
      }
      SignalASISecurityStatusRow(
        title: t("cc_runtime_catalog_refresh_title", "Runtime catalog"),
        subtitle: t("cc_runtime_catalog_refresh_subtitle", "Load compatible packs from the signed SignalASI release catalog"),
        systemImage: "checklist",
        tint: .blue,
        badge: "\(packs.count)"
      )
    }
  }

  private var environmentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_section_environment", "Base Runtime"))
      ForEach(environmentPacks) { pack in
        SignalASISecurityStatusRow(
          title: Self.packTitle(pack.id, language: interfaceLanguage),
          subtitle: Self.packSubtitle(pack, language: interfaceLanguage),
          systemImage: "terminal",
          tint: Self.packTint(pack),
          badge: Self.packBadge(pack, language: interfaceLanguage)
        )
      }
    }
  }

  private var receiptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_section_receipts", "Recent Execution Receipts"))
      SignalASISecurityStatusRow(
        title: t("cc_runtime_receipt_empty_title", "No runtime executions yet"),
        subtitle: t("cc_runtime_receipt_empty_subtitle", "Verified execution receipts appear here after local runtime tasks run"),
        systemImage: "clock.arrow.circlepath",
        tint: .gray,
        badge: ""
      )
    }
  }

  private var securitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_section_security", "Isolation & Policy"))
      SignalASISecurityStatusRow(
        title: t("cc_runtime_isolation_title", "Task Workspace Isolation"),
        subtitle: t("cc_runtime_isolation_subtitle", "Each task gets CPU, memory, storage, time, output, and artifact limits"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("cc_status_ready", "Ready")
      )
      SignalASISecurityStatusRow(
        title: t("cc_runtime_network_title", "Guest Network by Default"),
        subtitle: t("cc_runtime_network_subtitle", "Off by default unless the current task receives scoped network authorization"),
        systemImage: "network",
        tint: .gray,
        badge: t("signalasi.status.off", "Off")
      )
    }
  }

  private var environmentPacks: [AgentRuntimePackStatus] {
    packs.filter { ["linux-base", "python-uv"].contains($0.id) }
  }

  private func recoverLinuxBase() {
    guard !isRecoveringLinuxBase else { return }
    isRecoveringLinuxBase = true
    linuxBaseRecoveryMessage = t("cc_runtime_recovery_preparing", "Checking the signed Linux runtime catalog...")
    DispatchQueue.global(qos: .userInitiated).async {
      let manager = AgentIOSRuntimePackCatalogManager(languageTag: interfaceLanguage)
      let outcome: Result<[AgentRuntimePackInstallResult], Error>
      do {
        outcome = .success(try manager.recoverLinuxBase(
          onDownloadProgress: { progress in
            guard progress.totalBytes > 0 else { return }
            let percent = min(100, max(0, Int(progress.downloadedBytes * 100 / progress.totalBytes)))
            DispatchQueue.main.async {
              linuxBaseRecoveryMessage = String(
                format: t("cc_runtime_recovery_downloading", "Downloading Linux 1.3.9 (%d%%)..."),
                percent
              )
            }
          },
          onInstallProgress: { progress in
            DispatchQueue.main.async {
              linuxBaseRecoveryMessage = String(
                format: t("cc_runtime_recovery_installing", "Recovering Linux 1.3.9: %@"),
                progress.stage.rawValue.lowercased()
              )
            }
          }
        ))
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        isRecoveringLinuxBase = false
        switch outcome {
        case .success(let results):
          linuxBaseRecoveryMessage = String(
            format: t("cc_runtime_recovery_success", "Linux 1.3.9 is ready (%d package(s) verified)"),
            results.count
          )
        case .failure(let error):
          linuxBaseRecoveryMessage = error.localizedDescription.ifBlank(
            t("cc_runtime_recovery_failed", "Linux runtime recovery failed")
          )
        }
      }
    }
  }

  private var softwarePacks: [AgentRuntimePackStatus] {
    packs.filter { !["linux-base", "python-uv"].contains($0.id) }
  }

  private var softwarePackCount: Int {
    softwarePacks.count
  }

  private var softwareReadyCount: Int {
    softwarePacks.filter { $0.state == .ready }.count
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
    AgentIOSRuntimePackInstaller(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager
    )
      .status(packId: packId)
  }

  static func packTitle(_ id: String, language: String) -> String {
    switch id {
    case "linux-base":
      return SignalASILocalization.string("cc_runtime_pack_linux", fallback: "Linux base", language: language)
    case "python-uv":
      return SignalASILocalization.string("cc_runtime_pack_python", fallback: "Python and uv", language: language)
    case "node-js":
      return SignalASILocalization.string("cc_runtime_pack_node", fallback: "Node.js and JavaScript", language: language)
    case "browser-automation":
      return SignalASILocalization.string("cc_runtime_pack_browser", fallback: "Browser automation", language: language)
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
    return SignalASILocalization.string(
      "cc_runtime_pack_subtitle",
      fallback: pack.reason.ifBlank("Signed modular runtime pack"),
      language: language
    )
  }

  static func packBadge(_ pack: AgentRuntimePackStatus, language: String) -> String {
    switch pack.state {
    case .ready:
      return SignalASILocalization.string("cc_status_ready", fallback: "Ready", language: language)
    case .notInstalled:
      return SignalASILocalization.string("cc_runtime_catalog_install", fallback: "Install", language: language)
    case .invalid, .incompatible:
      return SignalASILocalization.string("cc_runtime_catalog_repair", fallback: "Repair", language: language)
    }
  }

  static func packTint(_ pack: AgentRuntimePackStatus) -> Color {
    switch pack.state {
    case .ready:
      return .signalASIAccent
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIRuntimeSoftwareCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var searchText = ""
  @State private var packs = SignalASIOnDeviceRuntimeView.packStatuses()
    .filter { !["linux-base", "python-uv"].contains($0.id) }
  @State private var catalogEntries: [AgentRuntimePackCatalogEntry] = []
  @State private var fileImporterPresented = false
  @State private var isInstalling = false
  @State private var isRefreshingCatalog = false
  @State private var installingPackID: String?
  @State private var installMessage = ""
  @State private var catalogMessage = ""

  private var filteredPacks: [AgentRuntimePackStatus] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return packs }
    return packs.filter { pack in
      pack.id.lowercased().contains(query) ||
        SignalASIOnDeviceRuntimeView.packTitle(pack.id, language: interfaceLanguage)
          .lowercased()
          .contains(query)
    }
  }

  private var installedCount: Int {
    packs.filter { $0.state == .ready }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_runtime_software_center_title", "Software Center"),
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
            title: t("cc_runtime_software_overview_title", "Trusted software catalog"),
            subtitle: t(
              "cc_runtime_software_overview_subtitle",
              "Software runs inside an isolated iOS-local runtime; verified sources and signatures gate installation"
            ),
            systemImage: "shippingbox",
            tint: .blue,
            badge: t("cc_runtime_software_verified_badge", "Signed and verified")
          )
          SignalASIRuntimeMetricStrip(metrics: [
            SignalASIRuntimeMetric(
              value: "\(installedCount)",
              label: t("cc_runtime_software_metric_installed", "Installed"),
              tint: installedCount == packs.count ? .signalASIAccent : .orange
            ),
            SignalASIRuntimeMetric(
              value: "\(packs.count)",
              label: t("cc_runtime_software_metric_available", "Available"),
              tint: .blue
            ),
            SignalASIRuntimeMetric(
              value: "iOS",
              label: t("cc_runtime_software_metric_catalog", "Catalog"),
              tint: .signalASIInsightText
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: [Self.runtimePackType],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
    .task {
      loadCachedCatalog()
    }
  }

  private var searchSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_software_section_find", "Find Software"))
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.signalASITextSecondary)
        TextField(t("cc_runtime_software_search_hint", "Software name"), text: $searchText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !searchText.isEmpty {
          Button {
            searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.signalASITextSecondary)
          }
          .buttonStyle(.plain)
        }
      }
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .frame(height: 40)
      .background(Color.signalASISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var catalogSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SignalASISecuritySectionTitle(title: t("cc_runtime_software_section_catalog", "Compatible Software"))
        Spacer()
      }
      SignalASISecurityActionRow(
        title: t("cc_runtime_catalog_refresh_action", "Refresh signed catalog"),
        subtitle: catalogMessage.ifBlank(t(
          "cc_runtime_catalog_refresh_action_subtitle",
          "Load compatible packs from the verified SignalASI release catalog"
        )),
        systemImage: isRefreshingCatalog ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
        tint: isRefreshingCatalog ? .blue : .signalASIAccent,
        badge: isRefreshingCatalog
          ? t("cc_runtime_catalog_refreshing", "Refreshing")
          : t("cc_runtime_catalog_refresh_badge", "Refresh")
      ) {
        guard !isRefreshingCatalog && !isInstalling else { return }
        refreshCatalog()
      }
      if catalogEntries.isEmpty && filteredPacks.isEmpty {
        SignalASISecurityStatusRow(
          title: t("cc_runtime_software_no_results_title", "No compatible software found"),
          subtitle: t("cc_runtime_catalog_empty_subtitle", "Refresh the signed catalog to see installable runtime packs"),
          systemImage: "magnifyingglass",
          tint: .orange,
          badge: ""
        )
      } else if !catalogEntries.isEmpty && filteredCatalogEntries.isEmpty {
        SignalASISecurityStatusRow(
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
            SignalASISecurityStatusRow(
              title: SignalASIOnDeviceRuntimeView.packTitle(pack.id, language: interfaceLanguage),
              subtitle: SignalASIOnDeviceRuntimeView.packSubtitle(pack, language: interfaceLanguage),
              systemImage: pack.id == "ffmpeg" ? "film" : "shippingbox",
              tint: SignalASIOnDeviceRuntimeView.packTint(pack),
              badge: SignalASIOnDeviceRuntimeView.packBadge(pack, language: interfaceLanguage)
            )
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
      SignalASISecuritySectionTitle(title: t("cc_runtime_software_section_advanced", "Advanced Installation"))
      SignalASISecurityActionRow(
        title: t("cc_runtime_import_title", "Install runtime pack"),
        subtitle: installMessage.ifBlank(t("cc_runtime_import_subtitle", "Import a SignalASI-signed .sarpack package")),
        systemImage: isInstalling ? "arrow.triangle.2.circlepath" : "tray.and.arrow.down",
        tint: isInstalling ? .blue : .orange,
        badge: isInstalling
          ? t("cc_runtime_import_installing", "Installing")
          : t("cc_runtime_import_action", "Choose file")
      ) {
        guard !isInstalling else { return }
        fileImporterPresented = true
      }
    }
  }

  private var filteredCatalogEntries: [AgentRuntimePackCatalogEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return catalogEntries }
    return catalogEntries.filter { entry in
      entry.packId.lowercased().contains(query) ||
        SignalASIOnDeviceRuntimeView.packTitle(entry.packId, language: interfaceLanguage)
          .lowercased()
          .contains(query)
    }
  }

  @ViewBuilder
  private func catalogEntryRow(_ entry: AgentRuntimePackCatalogEntry) -> some View {
    let installed = SignalASIOnDeviceRuntimeView.packStatus(entry.packId)
    let ready = installed.state == .ready && installed.manifest?.version == entry.version
    let installing = installingPackID == entry.packId
    SignalASISecurityActionRow(
      title: SignalASIOnDeviceRuntimeView.packTitle(entry.packId, language: interfaceLanguage),
      subtitle: catalogEntrySubtitle(entry),
      systemImage: entry.packId == "ffmpeg" ? "film" : "shippingbox",
      tint: ready ? .signalASIAccent : (installing ? .blue : .orange),
      badge: ready
        ? t("cc_status_ready", "Ready")
        : (installing ? t("cc_runtime_catalog_installing", "Installing") : t("cc_runtime_catalog_install", "Install"))
    ) {
      guard !ready && !installing && !isInstalling && !isRefreshingCatalog else { return }
      install(entry)
    }
  }

  private func catalogEntrySubtitle(_ entry: AgentRuntimePackCatalogEntry) -> String {
    let base = "\(entry.version) / \(SignalASIOnDeviceRuntimeView.formatBytes(entry.installedSizeBytes)) / \(entry.license)"
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
          packs = SignalASIOnDeviceRuntimeView.packStatuses()
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
          packs = SignalASIOnDeviceRuntimeView.packStatuses()
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIRuntimeMetric: Identifiable {
  var value: String
  var label: String
  var tint: Color

  var id: String { label }
}

private struct SignalASIRuntimeMetricStrip: View {
  var metrics: [SignalASIRuntimeMetric]

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
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }
}
