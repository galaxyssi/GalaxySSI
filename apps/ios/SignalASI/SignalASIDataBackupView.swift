import SwiftUI
import UniformTypeIdentifiers

enum SignalASIDataBackupInitialMode {
  case overview
  case export
  case importBackup
}

struct SignalASIDataBackupView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  private let initialMode: SignalASIDataBackupInitialMode
  @State private var backupPassword = ""
  @State private var backupIncludeMessages = true
  @State private var backupDocument: SignalASIBackupDocument?
  @State private var backupExportPresented = false
  @State private var backupImportPresented = false
  @State private var backupStatus = ""
  @State private var backupStatusIsError = false
  @State private var pendingImportPreview: SignalASIBackupImportPreview?
  @State private var cacheBytes: Int64 = 0
  @State private var freeStorageBytes: Int64 = 0
  @State private var didApplyInitialMode = false

  init(initialMode: SignalASIDataBackupInitialMode = .overview) {
    self.initialMode = initialMode
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_data_title", "Data & Backup"),
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
            title: t("cc_data_private_title", "Your data stays under your control"),
            subtitle: t(
              "cc_data_private_subtitle",
              "Backups use a separate password and can be stored entirely offline"
            ),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: t("signalasi.status.ready", "Ready")
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileExporter(
      isPresented: $backupExportPresented,
      document: backupDocument,
      contentType: .data,
      defaultFilename: SignalASIBackupManager.defaultFilename()
    ) { result in
      switch result {
      case .success:
        setBackupStatus(t("signalasi.backup.exported", "Backup exported."), isError: false)
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
      SignalASISecurityStatusRow(
        title: t("backup_export_title", "Back Up Chat History"),
        subtitle: t(
          "signalasi.data_backup.export_ready_hint",
          "Enter a backup password, choose whether to include chat history, then export."
        ),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("signalasi.common.export", "Export")
      )
    case .importBackup:
      SignalASISecurityStatusRow(
        title: t("backup_import_title", "Import Encrypted Backup"),
        subtitle: t(
          "signalasi.data_backup.import_ready_hint",
          "Enter the backup password, choose the chat-history restore option, then import a backup file."
        ),
        systemImage: "square.and.arrow.down",
        tint: .signalASIAccent,
        badge: t("signalasi.common.import", "Import")
      )
    }
  }

  private var backupSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_backup", "Backup"))
      SignalASIDataBackupCredentialCard(
        password: $backupPassword,
        includeMessages: $backupIncludeMessages,
        passwordTitle: t("backup_password_hint", "Set an encryption password"),
        includeMessagesTitle: t("backup_include_messages", "Back up chat history"),
        minimumPasswordHint: String(
          format: t("signalasi.data_backup.password_hint", "Use at least %d characters"),
          SignalASIBackupManager.minimumPasswordLength
        )
      )
      SignalASISecurityStatusRow(
        title: t("backup_include_agent_data", "Agent memory and knowledge"),
        subtitle: t(
          "backup_include_agent_data_subtitle",
          "Memory, knowledge, workflows, schedules and event triggers, task history, safety settings, and Home Assistant configuration"
        ),
        systemImage: "person.crop.circle.badge.gearshape",
        tint: .signalASIAccent,
        badge: t("backup_included", "Included")
      )
      SignalASISecurityActionRow(
        title: t("cc_create_backup_title", "Create Encrypted Backup"),
        subtitle: t(
          "cc_create_backup_subtitle",
          "Identity, contacts, Agent data, knowledge, and optional chats"
        ),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("signalasi.common.export", "Export")
      ) {
        exportBackup()
      }
      .disabled(!canUseBackupPassword)
      SignalASISecurityActionRow(
        title: t("cc_import_backup_title", "Import Backup"),
        subtitle: t("cc_import_backup_subtitle", "Verify the password and preview the restore scope"),
        systemImage: "square.and.arrow.down",
        tint: .signalASIAccent,
        badge: t("signalasi.common.import", "Import")
      ) {
        backupImportPresented = true
      }
      .disabled(!canUseBackupPassword)
      if let preview = pendingImportPreview {
        importPreviewSection(preview)
      }
      if !backupStatus.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.data_backup.backup_status", "Backup Status"),
          subtitle: backupStatus,
          systemImage: backupStatusIsError ? "xmark.circle" : "checkmark.circle",
          tint: backupStatusIsError ? .red : .signalASIAccent,
          badge: backupStatusIsError
            ? t("signalasi.status.needs_setup", "Needs Setup")
            : t("signalasi.status.ready", "Ready")
        )
      }
    }
  }

  private var storageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_storage", "Storage"))
      SignalASISecurityStatusRow(
        title: t("cc_storage_title", "SignalASI Storage"),
        subtitle: storageSubtitle,
        systemImage: "externaldrive",
        tint: .purple,
        badge: freeStorageBytes > 0 ? formatBytes(freeStorageBytes) : ""
      )
      SignalASISecurityActionRow(
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
    backupPassword.count >= SignalASIBackupManager.minimumPasswordLength
  }

  private func importPreviewSection(_ preview: SignalASIBackupImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.data_backup.import_preview_section", "Restore Preview"))
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_file", "Backup file"),
        subtitle: String(
          format: t("signalasi.data_backup.import_file_subtitle", "%@ / exported %@ / %@"),
          preview.fileName,
          preview.exportedAtText(language: interfaceLanguage),
          preview.platformLabel
        ),
        systemImage: "doc.text",
        tint: .blue,
        badge: t("signalasi.status.ready", "Ready")
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_identity", "Identity"),
        subtitle: preview.identitySubtitle(
          included: t("signalasi.data_backup.identity_included", "Signing identity is included"),
          profileOnly: t("signalasi.data_backup.identity_profile_only", "Profile restores without private signing key")
        ),
        systemImage: "person.crop.circle",
        tint: preview.includesIdentity ? .signalASIAccent : .gray,
        badge: preview.includesIdentity ? t("backup_included", "Included") : t("signalasi.common.preview", "Preview")
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_people", "Contacts & requests"),
        subtitle: String(
          format: t("signalasi.data_backup.import_people_subtitle", "%d contacts / %d friend requests"),
          preview.contactCount,
          preview.friendRequestCount
        ),
        systemImage: "person.2",
        tint: .purple,
        badge: preview.contactsBadge(localized: t)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_messages", "Chat history"),
        subtitle: String(
          format: t("signalasi.data_backup.import_messages_subtitle", "%d chats / %d messages"),
          preview.messageThreadCount,
          preview.messageCount
        ),
        systemImage: "bubble.left.and.bubble.right",
        tint: preview.willRestoreMessages ? .signalASIAccent : .gray,
        badge: preview.messagesBadge(localized: t)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_agent_data", "Agent data"),
        subtitle: String(
          format: t(
            "signalasi.data_backup.import_agent_data_subtitle",
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
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_language_voice", "Language & Voice"),
        subtitle: preview.languageVoiceSubtitle(localized: t),
        systemImage: "globe",
        tint: preview.includesAgentData ? .signalASIAccent : .gray,
        badge: preview.agentDataBadge(localized: t)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.data_backup.import_configuration", "Configuration"),
        subtitle: String(
          format: t(
            "signalasi.data_backup.import_configuration_subtitle",
            "%d server links / %d devices / %d cloud secrets"
          ),
          preview.serverLinkCount,
          preview.customDeviceCount,
          preview.cloudSecretCount
        ),
        systemImage: "slider.horizontal.3",
        tint: .teal,
        badge: t("signalasi.common.preview", "Preview")
      )
      SignalASISecurityActionRow(
        title: t("signalasi.data_backup.restore_preview_action", "Restore This Backup"),
        subtitle: t(
          "signalasi.data_backup.restore_preview_subtitle",
          "Apply the previewed identity, contacts, Agent data, settings, and selected chat history"
        ),
        systemImage: "arrow.clockwise",
        tint: .signalASIAccent,
        badge: t("signalasi.common.restore", "Restore")
      ) {
        restorePendingBackup()
      }
      SignalASISecurityActionRow(
        title: t("signalasi.common.cancel", "Cancel"),
        subtitle: t("signalasi.data_backup.cancel_preview_subtitle", "Discard this verified preview without changing local data"),
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
      setBackupStatus(t("signalasi.backup.preparing", "Preparing backup..."), isError: false)
      Task {
        do {
          let data = try await Task.detached {
            try SignalASIBackupManager.encryptPayload(payload, password: password)
          }.value
          await MainActor.run {
            backupDocument = SignalASIBackupDocument(data: data)
            backupExportPresented = true
            setBackupStatus(t("signalasi.backup.ready", "Backup ready."), isError: false)
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
    setBackupStatus(t("signalasi.backup.verifying", "Verifying backup..."), isError: false)
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
          try SignalASIBackupManager.importBackup(data: data, password: password)
        }.value
        await MainActor.run {
          pendingImportPreview = SignalASIBackupImportPreview(
            payload: payload,
            includeMessages: includeMessages,
            fileName: fileName
          )
          setBackupStatus(t("signalasi.backup.verified", "Backup verified. Review the restore preview."), isError: false)
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
      setBackupStatus(t("signalasi.backup.restoring", "Restoring backup..."), isError: false)
      try store.restoreBackupPayload(preview.payload, includeMessages: preview.includeMessages)
      pendingImportPreview = nil
      setBackupStatus(t("signalasi.backup.restored", "Backup restored."), isError: false)
      refreshStorageMetrics()
    } catch {
      setBackupStatus(error.localizedDescription, isError: true)
    }
  }

  private func cancelPendingBackupPreview() {
    pendingImportPreview = nil
    setBackupStatus(t("signalasi.backup.preview_cancelled", "Backup preview cancelled."), isError: false)
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
      String(format: t("signalasi.data_backup.cache_cleared", "Cleared %@ of rebuildable cache"), formatBytes(removedBytes)),
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
          "signalasi.data_backup.export_ready_hint",
          "Enter a backup password, choose whether to include chat history, then export."
        ),
        isError: false
      )
    case .importBackup:
      setBackupStatus(
        t(
          "signalasi.data_backup.import_ready_hint",
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIDataBackupCredentialCard: View {
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
        .background(Color.signalASIInputStroke.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Toggle(includeMessagesTitle, isOn: $includeMessages)
        .font(.system(size: 15, weight: .semibold))
        .tint(.signalASIAccent)
      Text(minimumPasswordHint)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIBackupImportPreview {
  var payload: SignalASIBackupPayload
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

  var customDeviceCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.customDeviceConnectors.count
  }

  var cloudSecretCount: Int {
    guard payload.includesAgentData else { return 0 }
    return payload.agentData.cloudAPISecrets.count
  }

  var platformLabel: String {
    payload.platform.isEmpty ? "SignalASI" : payload.platform.uppercased()
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
      : t("signalasi.data_backup.not_included", "Not included")
  }

  func messagesBadge(localized t: (String, String) -> String) -> String {
    guard payload.includesMessages else {
      return t("signalasi.data_backup.not_included", "Not included")
    }
    return willRestoreMessages
      ? t("backup_included", "Included")
      : t("signalasi.data_backup.skipped_by_choice", "Skipped")
  }

  func agentDataBadge(localized t: (String, String) -> String) -> String {
    payload.includesAgentData
      ? t("backup_included", "Included")
      : t("signalasi.data_backup.not_included", "Not included")
  }

  func languageVoiceSubtitle(localized t: (String, String) -> String) -> String {
    guard payload.includesAgentData else {
      return t("signalasi.data_backup.not_included", "Not included")
    }
    let policy = payload.agentData.languagePolicy
    let settings = payload.agentData.voiceSettings
    let voiceState = settings.wakeListeningEnabled
      ? t("common_on", "On")
      : t("common_off", "Off")
    let modelName = VoiceWhisperModelCatalog.model(settings.asrModelId).displayName
    return String(
      format: t(
        "signalasi.data_backup.import_language_voice_subtitle",
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
      ? t("signalasi.language_policy.auto_short", "Auto")
      : t("signalasi.language_policy.configured_short", "Configured")
  }
}
