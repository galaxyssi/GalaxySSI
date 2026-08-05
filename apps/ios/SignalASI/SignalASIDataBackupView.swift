import SwiftUI
import UniformTypeIdentifiers

struct SignalASIDataBackupView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var backupPassword = ""
  @State private var backupIncludeMessages = true
  @State private var backupDocument: SignalASIBackupDocument?
  @State private var backupExportPresented = false
  @State private var backupImportPresented = false
  @State private var backupStatus = ""
  @State private var backupStatusIsError = false
  @State private var cacheBytes: Int64 = 0
  @State private var freeStorageBytes: Int64 = 0

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
        importBackup(from: url)
      } catch {
        setBackupStatus(error.localizedDescription, isError: true)
      }
    }
    .onAppear(perform: refreshStorageMetrics)
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
    return "\(subtitle) · \(formatBytes(freeStorageBytes))"
  }

  private var canUseBackupPassword: Bool {
    backupPassword.count >= SignalASIBackupManager.minimumPasswordLength
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

  private func importBackup(from url: URL) {
    let password = backupPassword
    let includeMessages = backupIncludeMessages
    setBackupStatus(t("signalasi.backup.restoring", "Restoring backup..."), isError: false)
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
        try await MainActor.run {
          try store.restoreBackupPayload(payload, includeMessages: includeMessages)
          setBackupStatus(t("signalasi.backup.restored", "Backup restored."), isError: false)
          refreshStorageMetrics()
        }
      } catch {
        await MainActor.run {
          setBackupStatus(error.localizedDescription, isError: true)
        }
      }
    }
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
