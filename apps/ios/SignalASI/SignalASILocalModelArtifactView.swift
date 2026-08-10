import Foundation
import SwiftUI

struct LocalModelHubArtifact: Identifiable, Equatable, Hashable {
  var repositoryId: String
  var fileName: String
  var sizeBytes: Int64
  var sha256: String
  var quantization: String
  var parameterCountBillions: Double
  var downloadURL: URL
  var source: LocalModelHubSource = .huggingFace

  var id: String { "\(source.rawValue)/\(repositoryId)/\(fileName)" }
  var displayName: String { fileName.replacingOccurrences(of: ".gguf", with: "").replacingOccurrences(of: "_", with: " ") }
}

enum LocalModelArtifactInstallState: String, Equatable {
  case notInstalled
  case paused
  case downloading
  case ready
  case failed
}

struct LocalModelArtifactProgress: Equatable {
  var bytesDownloaded: Int64
  var totalBytes: Int64

  var percent: Int {
    guard totalBytes > 0 else { return 0 }
    return Int(max(0, min(100, bytesDownloaded * 100 / totalBytes)))
  }
}

@MainActor
final class LocalModelArtifactDownloadCoordinator: ObservableObject {
  @Published private(set) var states: [String: LocalModelArtifactInstallState] = [:]
  @Published private(set) var errors: [String: String] = [:]
  @Published private(set) var progress: [String: LocalModelArtifactProgress] = [:]

  private var tasks: [String: Task<Void, Never>] = [:]
  private let fileManager = FileManager.default
  private let storage = LocalModelRuntimeStorage()
  private let chunkSize = 1_048_576

  init() {
    loadPersistedStates()
  }

  func state(for artifact: LocalModelHubArtifact) -> LocalModelArtifactInstallState {
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    if storage.inspect(profile).installed {
      return .ready
    }
    let saved = states[artifact.id] ?? .notInstalled
    if saved == .downloading && tasks[artifact.id] == nil {
      return partialBytes(for: profile) > 0 ? .paused : .notInstalled
    }
    if saved == .notInstalled && partialBytes(for: profile) > 0 {
      return .paused
    }
    return saved
  }

  func progress(for artifact: LocalModelHubArtifact) -> LocalModelArtifactProgress {
    if let value = progress[artifact.id] { return value }
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    return LocalModelArtifactProgress(
      bytesDownloaded: partialBytes(for: profile),
      totalBytes: artifact.sizeBytes
    )
  }

  func error(for artifact: LocalModelHubArtifact) -> String? {
    errors[artifact.id]
  }

  func start(_ artifact: LocalModelHubArtifact) {
    guard tasks[artifact.id] == nil else { return }
    let profile = LocalModelRuntimeCatalog.addHubArtifact(artifact)
    let required = storage.requiredDownloadBytes(for: profile)
    let available = storage.availableBytes()
    if available > 0 && available < required {
      errors[artifact.id] = LocalModelArtifactDownloadError.insufficientStorage(
        required: required,
        available: available
      ).localizedDescription
      states[artifact.id] = .failed
      persistStates()
      return
    }
    errors[artifact.id] = nil
    states[artifact.id] = .downloading
    progress[artifact.id] = LocalModelArtifactProgress(
      bytesDownloaded: partialBytes(for: profile),
      totalBytes: artifact.sizeBytes
    )
    persistStates()
    tasks[artifact.id] = Task { [weak self] in
      do {
        guard let self else { return }
        let temporaryURL = try await self.downloadToStaging(artifact, profile: profile)
        try Task.checkCancellation()
        let size = try self.fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
        guard size?.int64Value == artifact.sizeBytes else {
          throw LocalModelArtifactDownloadError.sizeMismatch
        }
        let actualHash = try LocalModelRuntimeStorage.sha256(fileURL: temporaryURL)
        guard actualHash == artifact.sha256.lowercased() else {
          throw LocalModelArtifactDownloadError.sha256Mismatch
        }
        _ = try self.storage.installVerifiedFile(
          temporaryURL,
          profile: profile,
          downloadURL: artifact.downloadURL
        )
        LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: true)
        self.progress[artifact.id] = LocalModelArtifactProgress(
          bytesDownloaded: artifact.sizeBytes,
          totalBytes: artifact.sizeBytes
        )
        self.states[artifact.id] = .ready
        self.errors[artifact.id] = nil
        self.persistStates()
      } catch is CancellationError {
        let partial = self?.partialBytes(for: profile) ?? 0
        self?.states[artifact.id] = partial > 0 ? .paused : .notInstalled
        self?.progress[artifact.id] = LocalModelArtifactProgress(
          bytesDownloaded: partial,
          totalBytes: artifact.sizeBytes
        )
        self?.persistStates()
      } catch {
        let partial = self?.partialBytes(for: profile) ?? 0
        self?.states[artifact.id] = .failed
        self?.progress[artifact.id] = LocalModelArtifactProgress(
          bytesDownloaded: partial,
          totalBytes: artifact.sizeBytes
        )
        self?.errors[artifact.id] = error.localizedDescription
        self?.persistStates()
      }
      self?.tasks.removeValue(forKey: artifact.id)
    }
  }

  func cancel(_ artifact: LocalModelHubArtifact) {
    tasks[artifact.id]?.cancel()
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    let partial = partialBytes(for: profile)
    states[artifact.id] = partial > 0 ? .paused : .notInstalled
    progress[artifact.id] = LocalModelArtifactProgress(
      bytesDownloaded: partial,
      totalBytes: artifact.sizeBytes
    )
    persistStates()
  }

  func delete(_ artifact: LocalModelHubArtifact) {
    tasks[artifact.id]?.cancel()
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: false)
    LocalModelInferenceRuntime.shared.unloadIfSelected(profileId: profile.id)
    try? storage.delete(profile)
    LocalModelRuntimeCatalog.removeHubProfile(profile)
    states[artifact.id] = .notInstalled
    errors[artifact.id] = nil
    progress[artifact.id] = LocalModelArtifactProgress(bytesDownloaded: 0, totalBytes: artifact.sizeBytes)
    persistStates()
  }

  func destinationURL(for artifact: LocalModelHubArtifact) -> URL {
    storage.finalFileURL(for: LocalModelRuntimeCatalog.profile(for: artifact))
  }

  private func loadPersistedStates() {
    let values = UserDefaults.standard.dictionary(forKey: "signalasi.local_model.artifact_states") as? [String: String] ?? [:]
    states = values.reduce(into: [:]) { result, entry in
      if let state = LocalModelArtifactInstallState(rawValue: entry.value) {
        result[entry.key] = state
      }
    }
  }

  private func persistStates() {
    UserDefaults.standard.set(states.mapValues(\.rawValue), forKey: "signalasi.local_model.artifact_states")
  }

  private func partialBytes(for profile: LocalModelRuntimeProfile) -> Int64 {
    let url = storage.stagingFileURL(for: profile)
    let values = try? fileManager.attributesOfItem(atPath: url.path)
    return max(0, (values?[.size] as? NSNumber)?.int64Value ?? 0)
  }

  private func publishProgress(
    _ artifact: LocalModelHubArtifact,
    bytesDownloaded: Int64
  ) {
    progress[artifact.id] = LocalModelArtifactProgress(
      bytesDownloaded: bytesDownloaded,
      totalBytes: artifact.sizeBytes
    )
  }

  private func downloadToStaging(
    _ artifact: LocalModelHubArtifact,
    profile: LocalModelRuntimeProfile
  ) async throws -> URL {
    var lastError: Error?
    for sourceURL in LocalModelArtifactDownloadSources.urls(for: artifact) {
      do {
        return try await downloadToStaging(
          artifact,
          profile: profile,
          sourceURL: sourceURL
        )
      } catch let cancellation as CancellationError {
        throw cancellation
      } catch {
        if Task.isCancelled {
          throw CancellationError()
        }
        lastError = error
      }
    }
    if let lastError {
      throw lastError
    }
    throw LocalModelArtifactDownloadError.httpStatus
  }

  private func downloadToStaging(
    _ artifact: LocalModelHubArtifact,
    profile: LocalModelRuntimeProfile,
    sourceURL: URL
  ) async throws -> URL {
    let staging = storage.stagingFileURL(for: profile)
    try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
    var offset = partialBytes(for: profile)
    if offset < 0 || offset > artifact.sizeBytes {
      try? fileManager.removeItem(at: staging)
      offset = 0
    }
    var restartedWithoutRange = false

    while true {
      var request = URLRequest(url: sourceURL)
      request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
      request.setValue("SignalASI-iOS", forHTTPHeaderField: "User-Agent")
      if offset > 0 {
        request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
      }
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw LocalModelArtifactDownloadError.httpStatus
      }
      if http.statusCode == 416 && offset == artifact.sizeBytes {
        return staging
      }
      guard (200..<300).contains(http.statusCode) else {
        throw LocalModelArtifactDownloadError.httpStatus
      }
      let append = offset > 0 && http.statusCode == 206 &&
        contentRangeStart(http.value(forHTTPHeaderField: "Content-Range")) == offset
      if offset > 0 && !append {
        guard !restartedWithoutRange else {
          throw LocalModelArtifactDownloadError.invalidContentRange
        }
        try? fileManager.removeItem(at: staging)
        offset = 0
        restartedWithoutRange = true
        continue
      }

      let initialBytes = append ? offset : 0
      if !fileManager.fileExists(atPath: staging.path) {
        fileManager.createFile(atPath: staging.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: staging)
      defer { try? handle.close() }
      if append {
        try handle.seekToEnd()
      } else {
        try handle.truncate(atOffset: 0)
      }
      var downloaded = initialBytes
      var buffer = Data()
      buffer.reserveCapacity(chunkSize)
      var lastPublishedAt = Date.distantPast
      for try await byte in bytes {
        try Task.checkCancellation()
        buffer.append(byte)
        if buffer.count >= chunkSize {
          handle.write(buffer)
          downloaded += Int64(buffer.count)
          buffer.removeAll(keepingCapacity: true)
          if Date().timeIntervalSince(lastPublishedAt) >= 0.5 {
            publishProgress(artifact, bytesDownloaded: downloaded)
            lastPublishedAt = Date()
          }
          guard downloaded <= artifact.sizeBytes else {
            throw LocalModelArtifactDownloadError.sizeMismatch
          }
        }
      }
      if !buffer.isEmpty {
        handle.write(buffer)
        downloaded += Int64(buffer.count)
      }
      handle.synchronizeFile()
      publishProgress(artifact, bytesDownloaded: downloaded)
      return staging
    }
  }

  private func contentRangeStart(_ value: String?) -> Int64? {
    guard let value,
          let range = value.split(separator: " ").last,
          let start = range.split(separator: "-").first else { return nil }
    return Int64(start)
  }

}

enum LocalModelArtifactDownloadError: LocalizedError {
  case httpStatus
  case sizeMismatch
  case sha256Mismatch
  case invalidContentRange
  case insufficientStorage(required: Int64, available: Int64)

  var errorDescription: String? {
    switch self {
    case .httpStatus: return "Model source returned an invalid HTTP response"
    case .sizeMismatch: return "Downloaded model size does not match its pinned metadata"
    case .sha256Mismatch: return "Downloaded model failed SHA-256 verification"
    case .invalidContentRange: return "Model source returned an invalid Content-Range"
    case .insufficientStorage(let required, let available):
      return "Local model needs \(required) bytes, but only \(available) bytes are available"
    }
  }
}

enum LocalModelHubArtifactClient {
  static func artifacts(for model: LocalModelHubSearchResult) async throws -> [LocalModelHubArtifact] {
    switch model.source {
    case .huggingFace:
      return try await huggingFaceArtifacts(for: model)
    case .modelScope:
      return try await modelScopeArtifacts(for: model)
    }
  }

  private static func huggingFaceArtifacts(for model: LocalModelHubSearchResult) async throws -> [LocalModelHubArtifact] {
    guard let encodedRepository = model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://huggingface.co/api/models/\(encodedRepository)?blobs=true") else {
      throw URLError(.badURL)
    }
    let data = try await requestData(url: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let siblings = root["siblings"] as? [[String: Any]] else {
      return []
    }
    return siblings.compactMap { sibling in
      guard let fileName = sibling["rfilename"] as? String,
            fileName.lowercased().hasSuffix(".gguf"),
            fileName.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) == nil else {
        return nil
      }
      let lfs = sibling["lfs"] as? [String: Any] ?? [:]
      let sha = (lfs["sha256"] as? String ?? "").lowercased()
      let size = (lfs["size"] as? NSNumber)?.int64Value ?? (sibling["size"] as? NSNumber)?.int64Value ?? 0
      guard size > 0, sha.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { return nil }
      guard let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let fileURL = URL(string: "https://huggingface.co/\(model.id)/resolve/main/\(encodedFileName)") else { return nil }
      return LocalModelHubArtifact(
        repositoryId: model.id,
        fileName: fileName,
        sizeBytes: size,
        sha256: sha,
        quantization: quantization(fileName),
        parameterCountBillions: parameterCount("\(model.id)/\(fileName)"),
        downloadURL: fileURL,
        source: .huggingFace
      )
    }
    .filter { !$0.quantization.isEmpty }
    .sorted { $0.sizeBytes < $1.sizeBytes }
  }

  private static func modelScopeArtifacts(for model: LocalModelHubSearchResult) async throws -> [LocalModelHubArtifact] {
    guard let encodedRepository = model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          var components = URLComponents(string: "https://modelscope.cn/api/v1/models/\(encodedRepository)/repo") else {
      throw URLError(.badURL)
    }
    components.queryItems = [
      URLQueryItem(name: "Revision", value: "master"),
      URLQueryItem(name: "Recursive", value: "True")
    ]
    guard let url = components.url else { throw URLError(.badURL) }
    let data = try await requestData(url: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataObject = (root["Data"] as? [String: Any]) ?? (root["data"] as? [String: Any]),
          let files = (dataObject["Files"] as? [[String: Any]]) ?? (dataObject["files"] as? [[String: Any]]) else {
      return []
    }
    return files.compactMap { file in
      let path = file["Path"] as? String
      let name = file["Name"] as? String
      guard let fileName = [path, name].compactMap({ value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }).first,
            fileName.lowercased().hasSuffix(".gguf"),
            fileName.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) == nil else {
        return nil
      }
      let sha = ((file["Sha256"] as? String) ?? "").lowercased()
      let size = int64(file["Size"])
      guard size > 0,
            sha.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
            !quantization(fileName).isEmpty else { return nil }
      var downloadComponents = URLComponents(string: "https://modelscope.cn/api/v1/models/\(encodedRepository)/repo")
      downloadComponents?.queryItems = [
        URLQueryItem(name: "Revision", value: "master"),
        URLQueryItem(name: "FilePath", value: fileName)
      ]
      guard let downloadURL = downloadComponents?.url else { return nil }
      return LocalModelHubArtifact(
        repositoryId: model.id,
        fileName: fileName,
        sizeBytes: size,
        sha256: sha,
        quantization: quantization(fileName),
        parameterCountBillions: parameterCount("\(model.id)/\(fileName)"),
        downloadURL: downloadURL,
        source: .modelScope
      )
    }
    .sorted { $0.sizeBytes < $1.sizeBytes }
  }

  private static func requestData(url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SignalASI-iOS", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  private static func int64(_ value: Any?) -> Int64 {
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) ?? 0 }
    return 0
  }

  private static func quantization(_ fileName: String) -> String {
    let pattern = #"(?:^|[-_.])(IQ\d(?:_[A-Z0-9]+)?|Q\d(?:_[A-Z0-9]+)+)(?:[-_.]|$)"#
    return fileName.range(of: pattern, options: [.regularExpression, .caseInsensitive])
      .map { String(fileName[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "-_.")).uppercased() } ?? ""
  }

  private static func parameterCount(_ value: String) -> Double {
    let pattern = #"(?:^|[-_/])(\d+(?:\.\d+)?)B(?:[-_/]|$)"#
    guard let match = value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return 0 }
    let matched = String(value[match])
    return Double(matched.filter { $0.isNumber || $0 == "." }) ?? 0
  }
}

struct SignalASILocalModelHubArtifactView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @StateObject private var downloads = LocalModelArtifactDownloadCoordinator()
  @State private var artifacts: [LocalModelHubArtifact] = []
  @State private var loading = true
  @State private var statusMessage = ""
  @State private var artifactToDelete: LocalModelHubArtifact?
  @State private var showingDeleteConfirmation = false
  var model: LocalModelHubSearchResult

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(title: model.displayName, leading: { SignalASIBackButton() }, trailing: { Color.clear })
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASILocalModelLabHeroView(
            title: model.displayName,
            subtitle: t("signalasi.local_model.artifact_subtitle", "Choose a GGUF artifact with pinned size and SHA-256 metadata"),
            systemImage: "doc.badge.gearshape",
            tint: .signalASIAccent,
            badge: sourceLabel(model.source)
          )
          if loading {
            SignalASILocalModelLabStatusRow(title: t("signalasi.local_model.artifact_loading", "Loading artifacts"), subtitle: model.id, systemImage: "hourglass", tint: .blue, badge: "...")
          } else if artifacts.isEmpty {
            SignalASILocalModelLabStatusRow(title: t("signalasi.local_model.artifact_empty", "No verified GGUF artifacts"), subtitle: statusMessage, systemImage: "info.circle", tint: .orange, badge: t("signalasi.status.unknown", "Unknown"))
          } else {
            SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.artifact_section", "GGUF Artifacts"))
            ForEach(artifacts) { artifact in
              artifactRow(artifact)
            }
          }
          if !statusMessage.isEmpty && !loading {
            SignalASILocalModelLabStatusRow(title: t("signalasi.local_model.status", "Status"), subtitle: statusMessage, systemImage: "info.circle", tint: .blue, badge: t("signalasi.status.ready", "Ready"))
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .confirmationDialog(
      t("signalasi.local_model.delete_title", "Delete downloaded model?"),
      isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(t("signalasi.local_model.delete_action", "Delete"), role: .destructive) {
        guard let artifact = artifactToDelete else { return }
        downloads.delete(artifact)
        statusMessage = t("signalasi.local_model.download_deleted", "Downloaded model deleted")
        artifactToDelete = nil
      }
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        artifactToDelete = nil
      }
    }
    .task { await loadArtifacts() }
  }

  private func artifactRow(_ artifact: LocalModelHubArtifact) -> some View {
    let state = downloads.state(for: artifact)
    let artifactProgress = downloads.progress(for: artifact)
    let downloadError = downloads.error(for: artifact)
    return SignalASILocalModelLabActionRow(
      title: artifact.displayName,
      subtitle: artifactSubtitle(
        artifact,
        state: state,
        progress: artifactProgress,
        error: downloadError
      ),
      systemImage: "arrow.down.circle",
      tint: state == .ready ? .signalASIAccent : .blue,
      badge: stateLabel(state, progress: artifactProgress)
    ) {
      switch state {
      case .downloading:
        downloads.cancel(artifact)
        statusMessage = t("signalasi.local_model.download_cancelled", "Download cancelled")
      case .ready:
        artifactToDelete = artifact
        showingDeleteConfirmation = true
      case .notInstalled, .failed, .paused:
        downloads.start(artifact)
        statusMessage = downloads.state(for: artifact) == .failed
          ? downloads.error(for: artifact) ?? t("signalasi.local_model.download_failed", "Download failed")
          : state == .paused
          ? t("signalasi.local_model.download_resumed", "Download resumed")
          : t("signalasi.local_model.download_started", "Download started")
      }
    }
  }

  private func loadArtifacts() async {
    do {
      let loaded = try await LocalModelHubArtifactClient.artifacts(for: model)
      await MainActor.run {
        artifacts = loaded
        loading = false
      }
    } catch {
      await MainActor.run {
        statusMessage = error.localizedDescription
        loading = false
      }
    }
  }

  private func artifactSubtitle(
    _ artifact: LocalModelHubArtifact,
    state: LocalModelArtifactInstallState,
    progress: LocalModelArtifactProgress,
    error: String?
  ) -> String {
    let details = "\(formatBytes(artifact.sizeBytes)) - \(artifact.quantization) - \(sourceLabel(artifact.source)) - SHA256 \(artifact.sha256.prefix(12))..."
    let failure = error.map { " - \($0)" } ?? ""
    switch state {
    case .downloading, .paused:
      return "\(progress.percent)% - \(formatBytes(progress.bytesDownloaded)) / \(formatBytes(artifact.sizeBytes)) - \(details)"
    case .notInstalled, .ready, .failed:
      return details + failure
    }
  }

  private func stateLabel(_ state: LocalModelArtifactInstallState, progress: LocalModelArtifactProgress) -> String {
    switch state {
    case .notInstalled: return t("signalasi.local_model.download_action", "Download")
    case .paused: return t("signalasi.local_model.download_resume", "Resume")
    case .downloading: return "\(progress.percent)%"
    case .ready: return t("signalasi.local_model.download_delete", "Delete")
    case .failed: return t("signalasi.common.retry", "Retry")
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let value = Double(max(0, bytes))
    if value >= 1_073_741_824 { return String(format: "%.1f GiB", value / 1_073_741_824) }
    return String(format: "%.0f MiB", value / 1_048_576)
  }

  private func sourceLabel(_ source: LocalModelHubSource) -> String {
    switch source {
    case .huggingFace:
      return t("signalasi.local_model.source_huggingface", "Hugging Face")
    case .modelScope:
      return t("signalasi.local_model.source_modelscope", "ModelScope")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
