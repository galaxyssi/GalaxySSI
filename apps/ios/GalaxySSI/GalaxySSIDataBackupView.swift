import SwiftUI
import UniformTypeIdentifiers

enum GalaxySSIDataBackupInitialMode {
  case overview
  case export
  case importBackup
}

struct GalaxySSIDataBackupView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  private let initialMode: GalaxySSIDataBackupInitialMode
  @State private var backupPassword = ""
  @State private var backupIncludeMessages = true
  @State private var backupDocument: GalaxySSIBackupDocument?
  @State private var backupExportPresented = false
  @State private var backupImportPresented = false
  @State private var backupStatus = ""
  @State private var backupStatusIsError = false
  @State private var pendingImportPreview: GalaxySSIBackupImportPreview?
  @State private var cacheBytes: Int64 = 0
  @State private var freeStorageBytes: Int64 = 0
  @State private var didApplyInitialMode = false

  init(initialMode: GalaxySSIDataBackupInitialMode = .overview) {
    self.initialMode = initialMode
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_data_title", "Data & Backup"),
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
            title: t("cc_data_private_title", "Your data stays under your control"),
            subtitle: t(
              "cc_data_private_subtitle",
              "Backups use a separate password and can be stored entirely offline"
            ),
            systemImage: "checkmark.shield",
            tint: .galaxySSIAccent,
            badge: t("galaxyssi.status.ready", "Ready")
          )
          initialModeCard
          backupSection
          storageSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileExporter(
      isPresented: $backupExportPresented,
      document: backupDocument,
      contentType: .data,
      defaultFilename: GalaxySSIBackupManager.defaultFilename()
    ) { result in
      switch result {
      case .success:
        setBackupStatus(t("galaxyssi.backup.exported", "Backup exported."), isError: false)
      case .failure(let error):
        setBackupStatus(error.localizedDescription, isError: true)
      }
    }
    .fileImporter(
      isPresented: $backupImportPresented,
      allowedContentTypes: [.data],
      allowsMultipleSelection: false
    ) { result in
      do {
        guard let url = try result.get().first else { return }
        previewBackupImport(from: url)
      } catch {
        setBackupStatus(error.localizedDescription, isError: true)
      }
    }
    .onAppear {
      refreshStorageMetrics()
      applyInitialModeIfNeeded()
    }
    .onChange(of: backupPassword) { _ in
      pendingImportPreview = nil
    }
    .onChange(of: backupIncludeMessages) { _ in
      pendingImportPreview = nil
    }
  }

  @ViewBuilder
  private var initialModeCard: some View {
    switch initialMode {
    case .overview:
      EmptyView()
    case .export:
      GalaxySSISecurityStatusRow(
        title: t("backup_export_title", "Back Up Chat History"),
        subtitle: t(
          "galaxyssi.data_backup.export_ready_hint",
          "Enter a backup password, choose whether to include chat history, then export."
        ),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("galaxyssi.common.export", "Export")
      )
    case .importBackup:
      GalaxySSISecurityStatusRow(
        title: t("backup_import_title", "Import Encrypted Backup"),
        subtitle: t(
          "galaxyssi.data_backup.import_ready_hint",
          "Enter the backup password, choose the chat-history restore option, then import a backup file."
        ),
        systemImage: "square.and.arrow.down",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.import", "Import")
      )
    }
  }

  private var backupSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_backup", "Backup"))
      GalaxySSIDataBackupCredentialCard(
        password: $backupPassword,
        includeMessages: $backupIncludeMessages,
        passwordTitle: t("backup_password_hint", "Set an encryption password"),
        includeMessagesTitle: t("backup_include_messages", "Back up chat history"),
        minimumPasswordHint: String(
          format: t("galaxyssi.data_backup.password_hint", "Use at least %d characters"),
          GalaxySSIBackupManager.minimumPasswordLength
        )
      )
      GalaxySSISecurityStatusRow(
        title: t("backup_include_agent_data", "Agent memory and knowledge"),
        subtitle: t(
          "backup_include_agent_data_subtitle",
          "Memory, knowledge, workflows, schedules and event triggers, task history, safety settings, and Home Assistant configuration"
        ),
        systemImage: "person.crop.circle.badge.gearshape",
        tint: .galaxySSIAccent,
        badge: t("backup_included", "Included")
      )
      GalaxySSISecurityActionRow(
        title: t("cc_create_backup_title", "Create Encrypted Backup"),
        subtitle: t(
          "cc_create_backup_subtitle",
          "Identity, contacts, Agent data, knowledge, and optional chats"
        ),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("galaxyssi.common.export", "Export")
      ) {
        exportBackup()
      }
      .disabled(!canUseBackupPassword)
      GalaxySSISecurityActionRow(
        title: t("cc_import_backup_title", "Import Backup"),
        subtitle: t("cc_import_backup_subtitle", "Verify the password and preview the restore scope"),
        systemImage: "square.and.arrow.down",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.import", "Import")
      ) {
        backupImportPresented = true
      }
      .disabled(!canUseBackupPassword)
      if let preview = pendingImportPreview {
        importPreviewSection(preview)
      }
      if !backupStatus.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.data_backup.backup_status", "Backup Status"),
          subtitle: backupStatus,
          systemImage: backupStatusIsError ? "xmark.circle" : "checkmark.circle",
          tint: backupStatusIsError ? .red : .galaxySSIAccent,
          badge: backupStatusIsError
            ? t("galaxyssi.status.needs_setup", "Needs Setup")
            : t("galaxyssi.status.ready", "Ready")
        )
      }
    }
  }

  private var storageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_storage", "Storage"))
      GalaxySSISecurityStatusRow(
        title: t("cc_storage_title", "GalaxySSI Storage"),
        subtitle: storageSubtitle,
        systemImage: "externaldrive",
        tint: .purple,
        badge: freeStorageBytes > 0 ? formatBytes(freeStorageBytes) : ""
      )
      GalaxySSISecurityActionRow(
        title: t("cc_clear_cache_title", "Clear Rebuildable Cache"),
        subtitle: t("cc_clear_cache_subtitle", "Remove temporary files without deleting identity or user data"),
        systemImage: "trash",
        tint: .orange,
        badge: formatBytes(cacheBytes)
      ) {
        clearRebuildableCache()
      }
    }
  }

  private var storageSubtitle: String {
    let subtitle = t("cc_storage_subtitle", "Knowledge, models, media, temporary files, and databases")
    guard freeStorageBytes > 0 else { return subtitle }
    return "\(subtitle) / \(formatBytes(freeStorageBytes))"
  }

  private var canUseBackupPassword: Bool {
    backupPassword.count >= GalaxySSIBackupManager.minimumPasswordLength
  }

  private func importPreviewSection(_ preview: GalaxySSIBackupImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.data_backup.import_preview_section", "Restore Preview"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_file", "Backup file"),
        subtitle: String(
          format: t("galaxyssi.data_backup.import_file_subtitle", "%@ / exported %@ / %@"),
          preview.fileName,
          preview.exportedAtText(language: interfaceLanguage),
          preview.platformLabel
        ),
        systemImage: "doc.text",
        tint: .blue,
        badge: t("galaxyssi.status.ready", "Ready")
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_identity", "Identity"),
        subtitle: preview.identitySubtitle(
          included: t("galaxyssi.data_backup.identity_included", "Signing identity is included"),
          profileOnly: t("galaxyssi.data_backup.identity_profile_only", "Profile restores without private signing key")
        ),
        systemImage: "person.crop.circle",
        tint: preview.includesIdentity ? .galaxySSIAccent : .gray,
        badge: preview.includesIdentity ? t("backup_included", "Included") : t("galaxyssi.common.preview", "Preview")
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_people", "Contacts & requests"),
        subtitle: String(
          format: t("galaxyssi.data_backup.import_people_subtitle", "%d contacts / %d friend requests"),
          preview.contactCount,
          preview.friendRequestCount
        ),
        systemImage: "person.2",
        tint: .purple,
        badge: preview.contactsBadge(localized: t)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_messages", "Chat history"),
        subtitle: String(
          format: t("galaxyssi.data_backup.import_messages_subtitle", "%d chats / %d messages"),
          preview.messageThreadCount,
          preview.messageCount
        ),
        systemImage: "bubble.left.and.bubble.right",
        tint: preview.willRestoreMessages ? .galaxySSIAccent : .gray,
        badge: preview.messagesBadge(localized: t)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_agent_data", "Agent data"),
        subtitle: String(
          format: t(
            "galaxyssi.data_backup.import_agent_data_subtitle",
            "%d memories / %d knowledge items / %d tasks / %d sessions"
          ),
          preview.memoryCount,
          preview.knowledgeCount,
          preview.taskCount,
          preview.agentSessionCount
        ),
        systemImage: "person.crop.circle.badge.gearshape",
        tint: preview.includesAgentData ? .orange : .gray,
        badge: preview.agentDataBadge(localized: t)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_global_agent", "Personal ASI state"),
        subtitle: preview.globalAgentStateSubtitle(localized: t),
        systemImage: "brain.head.profile",
        tint: preview.includesGlobalAgentState ? .purple : .gray,
        badge: preview.globalAgentStateBadge(localized: t)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_transcript", "Agent transcript"),
        subtitle: String(
          format: t("galaxyssi.data_backup.import_transcript_subtitle", "%d entries with deferred content integrity"),
          preview.transcriptCount
        ),
        systemImage: "text.bubble",
        tint: preview.transcriptCount > 0 ? .galaxySSIAccent : .gray,
        badge: preview.transcriptCount > 0
           ? t("backup_included", "Included")
           : t("galaxyssi.data_backup.not_included", "Not included")
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_language_voice", "Language & Voice"),
        subtitle: preview.languageVoiceSubtitle(localized: t),
        systemImage: "globe",
        tint: preview.includesAgentData ? .galaxySSIAccent : .gray,
        badge: preview.agentDataBadge(localized: t)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.data_backup.import_configuration", "Configuration"),
        subtitle: String(
          format: t(
            "galaxyssi.data_backup.import_configuration_subtitle",
            "%d server links / %d devices / %d cloud secrets"
          ),
          preview.serverLinkCount,
          preview.customDeviceCount,
          preview.cloudSecretCount
        ),
        systemImage: "slider.horizontal.3",
        tint: .teal,
        badge: t("galaxyssi.common.preview", "Preview")
      )
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.data_backup.restore_preview_action", "Restore This Backup"),
        subtitle: t(
          "galaxyssi.data_backup.restore_preview_subtitle",
          "Apply the previewed identity, contacts, Agent data, settings, and selected chat history"
        ),
        systemImage: "arrow.clockwise",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.restore", "Restore")
      ) {
        restorePendingBackup()
      }
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.common.cancel", "Cancel"),
        subtitle: t("galaxyssi.data_backup.cancel_preview_subtitle", "Discard this verified preview without changing local data"),
        systemImage: "xmark.circle",
        tint: .gray,
        badge: ""
      ) {
        cancelPendingBackupPreview()
      }
    }
  }

  private func exportBackup() {
    do {
      let password = backupPassword
      let payload = store.exportBackupPayload(includeContacts: true, includeMessages: backupIncludeMessages)
      setBackupStatus(t("galaxyssi.backup.preparing", "Preparing backup..."), isError: false)
      Task {
        do {
          let data = try await Task.detached {
            try GalaxySSIBackupManager.encryptPayload(payload, password: password)
          }.value
          await MainActor.run {
            backupDocument = GalaxySSIBackupDocument(data: data)
            backupExportPresented = true
            setBackupStatus(t("galaxyssi.backup.ready", "Backup ready."), isError: false)
          }
        } catch {
          await MainActor.run {
            setBackupStatus(error.localizedDescription, isError: true)
          }
        }
      }
    }
  }

  private func previewBackupImport(from url: URL) {
    let password = backupPassword
    let includeMessages = backupIncludeMessages
    let fileName = url.lastPathComponent
    pendingImportPreview = nil
    setBackupStatus(t("galaxyssi.backup.verifying", "Verifying backup..."), isError: false)
    Task {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      do {
        let data = try Data(contentsOf: url)
        let payload = try await Task.detached {
          try GalaxySSIBackupManager.importBackup(data: data, password: password)
        }.value
        await MainActor.run {
          pendingImportPreview = GalaxySSIBackupImportPreview(
            payload: payload,
            includeMessages: includeMessages,
            fileName: fileName
          )
          setBackupStatus(t("galaxyssi.backup.verified", "Backup verified. Review the restore preview."), isError: false)
          refreshStorageMetrics()
        }
      } catch {
        await MainActor.run {
          setBackupStatus(error.localizedDescription, isError: true)
        }
      }
    }
  }

  private func restorePendingBackup() {
    guard let preview = pendingImportPreview else { return }
    do {
      setBackupStatus(t("galaxyssi.backup.restoring", "Restoring backup..."), isError: false)
      try store.restoreBackupPayload(preview.payload, includeMessages: preview.includeMessages)
      pendingImportPreview = nil
      setBackupStatus(t("galaxyssi.backup.restored", "Backup restored."), isError: false)
      refreshStorageMetrics()
    } catch {
      setBackupStatus(error.localizedDescription, isError: true)
    }
  }

  private func cancelPendingBackupPreview() {
    pendingImportPreview = nil
    setBackupStatus(t("galaxyssi.backup.preview_cancelled", "Backup preview cancelled."), isError: false)
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
    refreshStorageMetrics()
    setBackupStatus(
      String(format: t("galaxyssi.data_backup.cache_cleared", "Cleared %@ of rebuildable cache"), formatBytes(removedBytes)),
      isError: false
    )
  }

  private func refreshStorageMetrics() {
    let fileManager = FileManager.default
    if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
      cacheBytes = directorySize(cachesURL, fileManager: fileManager)
    } else {
      cacheBytes = 0
    }
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
       let values = try? documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let bytes = values.volumeAvailableCapacityForImportantUsage {
      freeStorageBytes = bytes
    } else {
      freeStorageBytes = 0
    }
  }

  private func applyInitialModeIfNeeded() {
    guard !didApplyInitialMode else { return }
    didApplyInitialMode = true
    switch initialMode {
    case .overview:
      return
    case .export:
      setBackupStatus(
        t(
          "galaxyssi.data_backup.export_ready_hint",
          "Enter a backup password, choose whether to include chat history, then export."
        ),
        isError: false
      )
    case .importBackup:
      setBackupStatus(
        t(
          "galaxyssi.data_backup.import_ready_hint",
          "Enter the backup password, choose the chat-history restore option, then import a backup file."
        ),
        isError: false
      )
    }
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

  private func setBackupStatus(_ value: String, isError: Bool) {
    backupStatus = value
    backupStatusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIDataBackupCredentialCard: View {
  @Binding var password: String
  @Binding var includeMessages: Bool
  var passwordTitle: String
  var includeMessagesTitle: String
  var minimumPasswordHint: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SecureField(passwordTitle, text: $password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSIInputStroke.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Toggle(includeMessagesTitle, isOn: $includeMessages)
        .font(.system(size: 15, weight: .semibold))
        .tint(.galaxySSIAccent)
      Text(minimumPasswordHint)
        .font(.system(size: 12))
        .foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIBackupImportPreview {
  var payload: GalaxySSIBackupPayload
  var includeMessages: Bool
  var fileName: String

  var includesIdentity: Bool {
    payload.privacyManifest.includesIdentity && payload.identity != nil
  }

  var includesAgentData: Bool {
    payload.includesAgentData
  }

  var contactCount: Int {
    payload.includesContacts ? payload.contacts.count : 0
  }

  var friendRequestCount: Int {
    payload.includesContacts ? payload.friendRequests.count : 0
  }

  var messageThreadCount: Int {
    guard payload.includesMessages else { return 0 }
    return payload.messagesByContact.count
  }

  var messageCount: Int {
    guard payload.includesMessages else { return 0 }
    return payload.messagesByContact.values.reduce(0) { $0 + $1.count }
  }

  var willRestoreMessages: Bool {
    includeMessages && payload.includesMessages
  }

  var serverLinkCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.serverLinks.count
  }

  var memoryCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.memory?.count ?? 0
  }

  var knowledgeCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.knowledge?.count ?? 0
  }

  var taskCount: Int {
    guard payload.includesAgentData else { return 0 }
    let history = payload.agentData.taskHistory?.count ?? 0
    let proactive = payload.agentData.proactiveTasks?.count ?? 0
    let runs = payload.agentData.proactiveRuns?.count ?? 0
    return history + proactive + runs
  }

  var agentSessionCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.agentConversations?.count ?? 0
  }

  var includesGlobalAgentState: Bool {
    payload.includesAgentData &&
      payload.privacyManifest.includesGlobalAgentState &&
      payload.agentData.globalAgentState != nil
  }

  var globalAgentStateCount: Int {
    guard includesGlobalAgentState, let state = payload.agentData.globalAgentState else { return 0 }
    return state.cognitionTasks.count +
      state.autonomousRuns.count +
      state.longHorizonGoals.count +
      state.research.tasks.count +
      state.memoryEvolution.records.count +
      state.memoryEvolution.inbox.candidates.count
  }

  var transcriptCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.transcript?.count ?? 0
  }

  var customDeviceCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.customDeviceConnectors.count
  }

  var cloudSecretCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.cloudAPISecrets.count
  }

  var platformLabel: String {
    payload.platform.isEmpty ? "GalaxySSI" : payload.platform.uppercased()
  }

  func exportedAtText(language: String) -> String {
    let exportedAt = Date(timeIntervalSince1970: TimeInterval(payload.exportedAt) / 1_000)
    let resolved = LanguagePolicySettings.resolveInterface(language)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: resolved == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: exportedAt)
  }

  func identitySubtitle(included: String, profileOnly: String) -> String {
    includesIdentity ? included : profileOnly
  }

  func contactsBadge(localized t: (String, String) -> String) -> String {
    payload.includesContacts
      ? t("backup_included", "Included")
      : t("galaxyssi.data_backup.not_included", "Not included")
  }

  func messagesBadge(localized t: (String, String) -> String) -> String {
    guard payload.includesMessages else {
      return t("galaxyssi.data_backup.not_included", "Not included")
    }
    return willRestoreMessages
      ? t("backup_included", "Included")
      : t("galaxyssi.data_backup.skipped_by_choice", "Skipped")
  }

  func agentDataBadge(localized t: (String, String) -> String) -> String {
    payload.includesAgentData
      ? t("backup_included", "Included")
      : t("galaxyssi.data_backup.not_included", "Not included")
  }

  func globalAgentStateBadge(localized t: (String, String) -> String) -> String {
    includesGlobalAgentState
      ? t("backup_included", "Included")
      : t("galaxyssi.data_backup.not_included", "Not included")
  }

  func globalAgentStateSubtitle(localized t: (String, String) -> String) -> String {
    guard includesGlobalAgentState else {
      return t("galaxyssi.data_backup.global_agent_not_included", "Personal ASI runtime state is not included")
    }
    return String(
      format: t(
        "galaxyssi.data_backup.global_agent_subtitle",
        "%d runtime records / cognition, autonomy, research and memory evolution"
      ),
      globalAgentStateCount
    )
  }

  func languageVoiceSubtitle(localized t: (String, String) -> String) -> String {
    guard payload.includesAgentData else {
      return t("galaxyssi.data_backup.not_included", "Not included")
    }
    let policy = payload.agentData.languagePolicy
    let settings = payload.agentData.voiceSettings
    let voiceState = settings.wakeListeningEnabled
      ? t("common_on", "On")
      : t("common_off", "Off")
    let modelName = VoiceWhisperModelCatalog.model(settings.asrModelId).displayName
    return String(
      format: t(
        "galaxyssi.data_backup.import_language_voice_subtitle",
        "%@ / Voice %@ / %@ / ASR %@"
      ),
      languagePolicyStatusBadge(for: policy, localized: t),
      voiceState,
      modelName,
      settings.preferredLocaleIdentifier
    )
  }

  private func languagePolicyStatusBadge(
    for policy: LanguagePolicySettings,
    localized t: (String, String) -> String
  ) -> String {
    let allAuto = LanguagePolicySettings.normalizeInterface(policy.interfaceLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.responseLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.asrLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.ttsLanguage) == LanguagePolicySettings.auto
    return allAuto
      ? t("galaxyssi.language_policy.auto_short", "Auto")
      : t("galaxyssi.language_policy.configured_short", "Configured")
  }
}
