import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SignalASIDataBackupView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var backupPassword = ""
  @State private var includeMessages = true
  @State private var backupDocument: SignalASIBackupDocument?
  @State private var exportPresented = false
  @State private var importPresented = false
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var cacheBytes: Int64 = 0
  @State private var availableBytes: Int64 = 0

  private var passwordReady: Bool {
    backupPassword.count >= SignalASIBackupManager.minimumPasswordLength
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
            subtitle: t("cc_data_private_subtitle", "Backups use a separate password and can be stored entirely offline"),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: t("cc_status_secure", "Secure")
          )
          backupControls
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
      isPresented: $exportPresented,
      document: backupDocument,
      contentType: .data,
      defaultFilename: SignalASIBackupManager.defaultFilename()
    ) { result in
      switch result {
      case .success:
        setStatus(t("signalasi.backup.exported", "Backup exported."), isError: false)
      case .failure(let error):
        setStatus(error.localizedDescription, isError: true)
      }
    }
    .fileImporter(
      isPresented: $importPresented,
      allowedContentTypes: [.data],
      allowsMultipleSelection: false
    ) { result in
      do {
        guard let url = try result.get().first else { return }
        importBackup(from: url)
      } catch {
        setStatus(error.localizedDescription, isError: true)
      }
    }
    .onAppear(perform: refreshStorage)
  }

  private var backupControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      SecureField(t("signalasi.settings.password", "Password"), text: $backupPassword)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.signalASISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Toggle(t("signalasi.settings.include_messages", "Include Messages"), isOn: $includeMessages)
        .font(.system(size: 15, weight: .semibold))
        .tint(.signalASIAccent)
      if !statusMessage.isEmpty {
        Text(statusMessage)
          .font(.system(size: 13))
          .foregroundColor(statusIsError ? .red : .signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var backupSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_backup", "Backup"))
      SignalASISecurityActionRow(
        title: t("cc_create_backup_title", "Create Encrypted Backup"),
        subtitle: t("cc_create_backup_subtitle", "Identity, contacts, Agent data, knowledge, and optional chats"),
        systemImage: "square.and.arrow.up",
        tint: passwordReady ? .blue : .gray,
        badge: t("signalasi.common.export", "Export")
      ) {
        exportBackup()
      }
      .disabled(!passwordReady)
      SignalASISecurityActionRow(
        title: t("cc_import_backup_title", "Import Backup"),
        subtitle: t("cc_import_backup_subtitle", "Verify the password and preview the restore scope"),
        systemImage: "square.and.arrow.down",
        tint: passwordReady ? .signalASIAccent : .gray,
        badge: t("signalasi.common.import", "Import")
      ) {
        importPresented = true
      }
      .disabled(!passwordReady)
    }
  }

  private var storageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_storage", "Storage"))
      SignalASISecurityStatusRow(
        title: t("cc_storage_title", "SignalASI Storage"),
        subtitle: storageSubtitle,
        systemImage: "internaldrive",
        tint: .signalASIInsightText,
        badge: availableBytes > 0 ? Self.formatBytes(availableBytes) : ""
      )
      SignalASISecurityActionRow(
        title: t("cc_clear_cache_title", "Clear Rebuildable Cache"),
        subtitle: t("cc_clear_cache_subtitle", "Remove temporary files without deleting identity or user data"),
        systemImage: "trash",
        tint: .orange,
        badge: Self.formatBytes(cacheBytes)
      ) {
        clearCache()
      }
    }
  }

  private var storageSubtitle: String {
    let base = t("cc_storage_subtitle", "Knowledge, models, media, temporary files, and databases")
    guard availableBytes > 0 else { return base }
    return "\(base) / \(t("signalasi.data_backup.available", "available"))"
  }

  private func exportBackup() {
    guard passwordReady else {
      setStatus(passwordRequirementMessage, isError: true)
      return
    }
    let password = backupPassword
    let payload = store.exportBackupPayload(includeContacts: true, includeMessages: includeMessages)
    setStatus(t("signalasi.backup.preparing", "Preparing backup..."), isError: false)
    Task {
      do {
        let data = try await Task.detached {
          try SignalASIBackupManager.encryptPayload(payload, password: password)
        }.value
        await MainActor.run {
          backupDocument = SignalASIBackupDocument(data: data)
          exportPresented = true
          setStatus(t("signalasi.backup.ready", "Backup ready."), isError: false)
        }
      } catch {
        await MainActor.run {
          setStatus(error.localizedDescription, isError: true)
        }
      }
    }
  }

  private func importBackup(from url: URL) {
    guard passwordReady else {
      setStatus(passwordRequirementMessage, isError: true)
      return
    }
    let password = backupPassword
    let shouldIncludeMessages = includeMessages
    setStatus(t("signalasi.backup.restoring", "Restoring backup..."), isError: false)
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
          try store.restoreBackupPayload(payload, includeMessages: shouldIncludeMessages)
          setStatus(t("signalasi.backup.restored", "Backup restored."), isError: false)
        }
      } catch {
        await MainActor.run {
          setStatus(error.localizedDescription, isError: true)
        }
      }
    }
  }

  private func clearCache() {
    let cacheURL = Self.cacheDirectoryURL()
    let removedBytes = cacheBytes
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: cacheURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      for url in contents {
        try FileManager.default.removeItem(at: url)
      }
      refreshStorage()
      setStatus(
        String(format: t("signalasi.data_backup.cache_cleared", "Cleared %@ of rebuildable cache."), Self.formatBytes(removedBytes)),
        isError: false
      )
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private var passwordRequirementMessage: String {
    String(
      format: t("signalasi.backup.password_requirement", "Use at least %d characters for the backup password."),
      SignalASIBackupManager.minimumPasswordLength
    )
  }

  private func setStatus(_ value: String, isError: Bool) {
    statusMessage = value
    statusIsError = isError
  }

  private func refreshStorage() {
    cacheBytes = Self.directorySize(Self.cacheDirectoryURL())
    availableBytes = Self.availableCapacity()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private static func cacheDirectoryURL() -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }

  private static func directorySize(_ url: URL, fileManager: FileManager = .default) -> Int64 {
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: nil
    ) else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
      guard values?.isRegularFile == true else { continue }
      total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
    return total
  }

  private static func availableCapacity() -> Int64 {
    let homeURL = FileManager.default.homeDirectoryForCurrentUser
    let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
    if let important = values?.volumeAvailableCapacityForImportantUsage {
      return important
    }
    return Int64(values?.volumeAvailableCapacity ?? 0)
  }

  private static func formatBytes(_ bytes: Int64) -> String {
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
}
