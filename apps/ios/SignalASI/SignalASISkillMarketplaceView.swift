import SwiftUI
import UniformTypeIdentifiers

struct SignalASISkillMarketplaceView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var installations: [AgentSkillInstallation] = []
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var importPresented = false
  @State private var exportPresented = false
  @State private var exportDocument: SignalASISkillPackageDocument?
  @State private var exportFilename = "signalasi-skill"
  @State private var pendingUnsignedPackage: Data?
  @State private var pendingUnsignedInspection: AgentSkillPackageInspection?

  private let runtime: AgentSkillRuntime

  init() {
    runtime = AgentSkillRuntime(
      store: UserDefaultsAgentSkillStore(),
      availableNativeToolIds: AgentPhoneNativeToolCatalog.descriptors().map(\.id)
    )
  }

  private var nativeToolIds: Set<String> {
    Set(AgentPhoneNativeToolCatalog.descriptors().map(\.id))
  }

  private var mcpConnections: [AgentMcpConnection] {
    AgentMcpRegistry(FileAgentMcpStore(rootURL: FileAgentMcpStore.defaultRootURL())).list()
  }

  private var catalogEntries: [AgentSkillCatalogEntry] {
    AgentDefaultCapabilityCatalog.skillEntries.sorted {
      if $0.featured != $1.featured { return $0.featured && !$1.featured }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private var enabledCount: Int {
    installations.filter(\.enabled).count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.skill_marketplace.title", "Skill Marketplace"),
        leading: { SignalASIBackButton() },
        trailing: {
          Button {
            importPresented = true
          } label: {
            Image(systemName: "square.and.arrow.down")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.signalASIAccent)
          }
          .accessibilityLabel(t("signalasi.skill_marketplace.import", "Import Skill"))
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.skill_marketplace.title", "Skill Marketplace"),
            subtitle: t(
              "signalasi.skill_marketplace.subtitle",
              "Install reusable Agent Skills with local validation and explicit controls"
            ),
            systemImage: "sparkles.rectangle.stack",
            tint: .purple,
            badge: String(format: t("signalasi.skill_marketplace.count", "%d installed"), installations.count)
          )

          overview

          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: statusIsError
                ? t("signalasi.skill_marketplace.error", "Skill update failed")
                : t("signalasi.skill_marketplace.latest_change", "Latest change"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .signalASIAccent,
              badge: statusIsError
                ? t("signalasi.status.needs_setup", "Needs Setup")
                : t("signalasi.status.ready", "Ready")
            )
          }

          installedSection
          recommendedSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(
      isPresented: $importPresented,
      allowedContentTypes: [.zip, .data],
      allowsMultipleSelection: false
    ) { result in
      importPackage(result)
    }
    .fileExporter(
      isPresented: $exportPresented,
      document: exportDocument,
      contentType: .zip,
      defaultFilename: exportFilename
    ) { result in
      switch result {
      case .success:
        setStatus(t("signalasi.skill_marketplace.exported", "Skill package exported."))
      case .failure(let error):
        setStatus(error.localizedDescription, isError: true)
      }
    }
    .alert(
      t("signalasi.skill_marketplace.unsigned_title", "Approve local Skill package?"),
      isPresented: Binding(
        get: { pendingUnsignedPackage != nil },
        set: { presented in
          if !presented {
            pendingUnsignedPackage = nil
            pendingUnsignedInspection = nil
          }
        }
      )
    ) {
      Button(t("signalasi.skill_marketplace.install", "Install")) {
        guard let package = pendingUnsignedPackage else { return }
        installPackage(package, allowUnsigned: true)
        pendingUnsignedPackage = nil
        pendingUnsignedInspection = nil
      }
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        pendingUnsignedPackage = nil
        pendingUnsignedInspection = nil
      }
    } message: {
      Text(unsignedPackageMessage)
    }
    .onAppear(perform: refresh)
  }

  private var overview: some View {
    HStack(spacing: 8) {
      skillMetric(value: "\(installations.count)", label: t("signalasi.skill_marketplace.installed", "Installed"), tint: .purple)
      skillMetric(value: "\(enabledCount)", label: t("signalasi.status.enabled", "Enabled"), tint: .signalASIAccent)
      skillMetric(value: "\(catalogEntries.count)", label: t("signalasi.skill_marketplace.recommended", "Recommended"), tint: .orange)
    }
  }

  private func skillMetric(value: String, label: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(tint)
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 11)
    .padding(.vertical, 10)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var installedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.skill_marketplace.installed_section", "Installed Skills"))
      if installations.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.skill_marketplace.empty_title", "No Skills installed"),
          subtitle: t("signalasi.skill_marketplace.empty_subtitle", "Choose a recommended Skill or import a validated local package."),
          systemImage: "sparkles",
          tint: .purple,
          badge: t("signalasi.skill_marketplace.available", "Available")
        )
      } else {
        ForEach(installations) { installation in
          SignalASISecurityNavigationRow(
            title: installation.manifest.name,
            subtitle: "v\(installation.version) - \(installation.manifest.summary)",
            systemImage: "sparkles",
            tint: installation.enabled ? .signalASIAccent : .orange,
            badge: installation.enabled
              ? t("signalasi.status.enabled", "Enabled")
              : t("signalasi.common.off", "Off")
          ) {
            SignalASISkillDetailView(
              installation: installation,
              dependencyStatus: nil,
              runtime: runtime,
              interfaceLanguage: interfaceLanguage,
              onChange: refresh,
              onExport: export
            )
          }
        }
      }
    }
  }

  private var recommendedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.skill_marketplace.recommended_section", "Recommended Skills"))
      ForEach(catalogEntries) { entry in
        let installation = installations.first { $0.id == entry.id && $0.version == entry.manifest.version }
        let dependencyStatus = AgentCapabilityDependencyResolver.resolve(
          entry,
          installedMcp: mcpConnections,
          nativeToolIds: nativeToolIds
        )
        SignalASISecurityNavigationRow(
          title: entry.name,
          subtitle: entry.summary,
          systemImage: entry.featured ? "star" : "sparkles",
          tint: dependencyStatus.available ? .purple : .orange,
          badge: installation == nil
            ? (dependencyStatus.available
              ? t("signalasi.skill_marketplace.ready_to_install", "Ready")
              : t("agent_capability_requires_setup", "Setup"))
            : t("signalasi.skill_marketplace.added", "Added")
        ) {
          SignalASISkillCatalogDetailView(
            entry: entry,
            installation: installation,
            dependencyStatus: dependencyStatus,
            runtime: runtime,
            interfaceLanguage: interfaceLanguage,
            onChange: refresh,
            onExport: export
          )
        }
      }
    }
  }

  private var unsignedPackageMessage: String {
    guard let inspection = pendingUnsignedInspection else {
      return t("signalasi.skill_marketplace.unsigned_subtitle", "This local package has no verified integrity record. Install only if you trust its source.")
    }
    return String(
      format: t("signalasi.skill_marketplace.unsigned_detail", "%@ v%@ has no verified integrity record. Install only if you trust its source."),
      inspection.manifest.name,
      inspection.manifest.version
    )
  }

  private func refresh() {
    installations = runtime.list()
  }

  private func importPackage(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
      let data = try Data(contentsOf: url)
      let inspection = try AgentSkillPackageInstaller(runtime).inspect(data)
      if inspection.integrityVerified {
        installPackage(data, allowUnsigned: false)
      } else {
        pendingUnsignedPackage = data
        pendingUnsignedInspection = inspection
      }
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func installPackage(_ data: Data, allowUnsigned: Bool) {
    do {
      let installation = try AgentSkillPackageInstaller(runtime).install(
        data,
        allowUnsignedLocalPackage: allowUnsigned
      )
      refresh()
      setStatus(String(format: t("signalasi.skill_marketplace.imported", "%@ v%@ imported and disabled until enabled."), installation.manifest.name, installation.version))
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func export(_ installation: AgentSkillInstallation) {
    exportDocument = SignalASISkillPackageDocument(data: AgentSkillPackageExporter.export(installation.manifest))
    exportFilename = "signalasi-\(installation.id.replacingOccurrences(of: ".", with: "-"))-\(installation.version)"
    exportPresented = true
  }

  private func setStatus(_ message: String, isError: Bool = false) {
    statusMessage = message
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASISkillDetailView: View {
  let installation: AgentSkillInstallation
  let dependencyStatus: AgentCapabilityDependencyStatus?
  let runtime: AgentSkillRuntime
  let interfaceLanguage: String
  let onChange: () -> Void
  let onExport: (AgentSkillInstallation) -> Void
  @State private var current: AgentSkillInstallation
  @State private var deleteConfirmation = false
  @Environment(\.dismiss) private var dismiss

  init(
    installation: AgentSkillInstallation,
    dependencyStatus: AgentCapabilityDependencyStatus?,
    runtime: AgentSkillRuntime,
    interfaceLanguage: String,
    onChange: @escaping () -> Void,
    onExport: @escaping (AgentSkillInstallation) -> Void
  ) {
    self.installation = installation
    self.dependencyStatus = dependencyStatus
    self.runtime = runtime
    self.interfaceLanguage = interfaceLanguage
    self.onChange = onChange
    self.onExport = onExport
    _current = State(initialValue: installation)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: current.manifest.name,
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: current.manifest.name,
            subtitle: current.manifest.summary,
            systemImage: "sparkles",
            tint: .purple,
            badge: "v\(current.version)"
          )
          details
          controls
          SignalASISecurityActionRow(
            title: t("signalasi.skill_marketplace.export", "Export Skill"),
            subtitle: t("signalasi.skill_marketplace.export_subtitle", "Create a portable declarative ZIP package"),
            systemImage: "square.and.arrow.up",
            tint: .blue,
            badge: t("signalasi.common.export", "Export")
          ) {
            onExport(current)
          }
          SignalASISecurityActionRow(
            title: t("signalasi.skill_marketplace.delete", "Delete Skill"),
            subtitle: t("signalasi.skill_marketplace.delete_subtitle", "Remove this installation from the local Skill store"),
            systemImage: "trash",
            tint: .red,
            badge: t("signalasi.common.delete", "Delete")
          ) {
            deleteConfirmation = true
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("signalasi.skill_marketplace.delete", "Delete Skill"), isPresented: $deleteConfirmation) {
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        _ = runtime.delete(id: current.id, version: current.version)
        onChange()
        dismiss()
      }
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {}
    } message: {
      Text(t("signalasi.skill_marketplace.delete_confirm", "Delete this Skill installation?"))
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.skill_marketplace.details", "Skill Details"))
      detailRow(t("signalasi.skill_marketplace.author", "Author"), current.manifest.author)
      detailRow(t("signalasi.skill_marketplace.source", "Source"), current.manifest.source)
      detailRow(t("signalasi.skill_marketplace.uses", "Uses"), "\(current.useCount)")
      detailRow(t("signalasi.skill_marketplace.permissions", "Permissions"), current.manifest.permissions.sorted().joined(separator: ", ").ifBlank(t("signalasi.common.none", "None")))
      if let dependencyStatus {
        detailRow(
          t("signalasi.skill_marketplace.dependencies", "Dependencies"),
          dependencyStatus.available
            ? t("signalasi.skill_marketplace.dependencies_ready", "All dependencies available")
            : t("agent_capability_requires_setup", "Setup required")
        )
      }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.skill_marketplace.controls", "Controls"))
      Toggle(isOn: Binding(
        get: { current.enabled },
        set: { updateEnabled($0) }
      )) {
        VStack(alignment: .leading, spacing: 3) {
          Text(t("signalasi.skill_marketplace.enabled", "Skill enabled"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(t("signalasi.skill_marketplace.enabled_subtitle", "Allow the Agent runtime to use this Skill"))
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
        }
      }
      .tint(.signalASIAccent)
      .padding(12)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Toggle(isOn: Binding(
        get: { current.autoInvoke },
        set: { updateAutoInvoke($0) }
      )) {
        VStack(alignment: .leading, spacing: 3) {
          Text(t("signalasi.skill_marketplace.auto_invoke", "Automatic invocation"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(t("signalasi.skill_marketplace.auto_invoke_subtitle", "Let matching requests suggest this Skill automatically"))
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
        }
      }
      .tint(.purple)
      .padding(12)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func updateEnabled(_ enabled: Bool) {
    do {
      current = try enabled
        ? runtime.enable(id: current.id, version: current.version)
        : runtime.disable(id: current.id, version: current.version)
      onChange()
    } catch {}
  }

  private func updateAutoInvoke(_ enabled: Bool) {
    do {
      current = try runtime.setAutoInvoke(id: current.id, version: current.version, enabled: enabled)
      onChange()
    } catch {}
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASISkillCatalogDetailView: View {
  let entry: AgentSkillCatalogEntry
  let installation: AgentSkillInstallation?
  let dependencyStatus: AgentCapabilityDependencyStatus
  let runtime: AgentSkillRuntime
  let interfaceLanguage: String
  let onChange: () -> Void
  let onExport: (AgentSkillInstallation) -> Void
  @State private var installError = ""

  var body: some View {
    Group {
      if let installation {
        SignalASISkillDetailView(
          installation: installation,
          dependencyStatus: dependencyStatus,
          runtime: runtime,
          interfaceLanguage: interfaceLanguage,
          onChange: onChange,
          onExport: onExport
        )
      } else {
        catalogContent
      }
    }
  }

  private var catalogContent: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: entry.name,
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: entry.name,
            subtitle: entry.summary,
            systemImage: entry.featured ? "star" : "sparkles",
            tint: .purple,
            badge: t("signalasi.skill_marketplace.recommended", "Recommended")
          )
          SignalASISecurityStatusRow(
            title: dependencyStatus.available
              ? t("signalasi.skill_marketplace.dependencies_ready", "All dependencies available")
              : t("agent_capability_requires_setup", "Setup required"),
            subtitle: dependencySummary,
            systemImage: dependencyStatus.available ? "checkmark.circle" : "exclamationmark.triangle",
            tint: dependencyStatus.available ? .signalASIAccent : .orange,
            badge: dependencyStatus.available
              ? t("signalasi.skill_marketplace.ready_to_install", "Ready")
              : t("agent_capability_requires_setup", "Setup")
          )
          if !installError.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.skill_marketplace.error", "Skill update failed"),
              subtitle: installError,
              systemImage: "xmark.circle",
              tint: .red,
              badge: t("signalasi.status.needs_setup", "Needs Setup")
            )
          }
          SignalASISecurityActionRow(
            title: t("signalasi.skill_marketplace.install", "Install"),
            subtitle: t("signalasi.skill_marketplace.install_subtitle", "Add this validated Skill to the local runtime"),
            systemImage: "arrow.down.circle",
            tint: dependencyStatus.available ? .purple : .gray,
            badge: dependencyStatus.available
              ? t("signalasi.skill_marketplace.install", "Install")
              : t("agent_capability_requires_setup", "Setup")
          ) {
            install()
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var dependencySummary: String {
    var values: [String] = []
    if !dependencyStatus.missingNativeTools.isEmpty {
      values.append(String(format: t("signalasi.skill_marketplace.missing_native", "%d native tools unavailable"), dependencyStatus.missingNativeTools.count))
    }
    if !dependencyStatus.missingMcpCatalogIds.isEmpty {
      values.append(String(format: t("signalasi.skill_marketplace.missing_mcp", "%d MCP services need setup"), dependencyStatus.missingMcpCatalogIds.count))
    }
    return values.joined(separator: " - ").ifBlank(t("signalasi.skill_marketplace.dependencies_ready", "All dependencies available"))
  }

  private func install() {
    guard dependencyStatus.available else { return }
    do {
      _ = try runtime.install(entry.manifest, enabled: true)
      onChange()
    } catch {
      installError = error.localizedDescription
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASISkillPackageDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.zip, .data] }
  static var writableContentTypes: [UTType] { [.zip] }

  var data: Data

  init(data: Data = Data()) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
