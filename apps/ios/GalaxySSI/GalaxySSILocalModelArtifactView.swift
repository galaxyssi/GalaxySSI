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
  var visionCapable: Bool = false

  var id: String { "\(source.rawValue)/\(repositoryId)/\(fileName)" }
  var displayName: String { fileName.replacingOccurrences(of: ".gguf", with: "").replacingOccurrences(of: "_", with: " ") }
}

enum LocalModelArtifactInstallState: String, Equatable {
  case notInstalled
  case paused
  case downloading
  case verifying
  case installing
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

private final class LocalModelArtifactDownloadDelegate: NSObject, URLSessionDownloadDelegate {
  weak var owner: LocalModelArtifactDownloadCoordinator?

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let artifactID = downloadTask.taskDescription else { return }
    Task { @MainActor [weak owner] in
      owner?.backgroundDownloadProgress(
        artifactID: artifactID,
        bytesDownloaded: totalBytesWritten,
        totalBytes: totalBytesExpectedToWrite
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let artifactID = downloadTask.taskDescription else { return }
    let stagingURL: URL?
    if let profile = LocalModelRuntimeCatalog.profiles().first(where: {
      LocalModelRuntimeCatalog.artifact(for: $0)?.id == artifactID
    }) {
      let destination = LocalModelRuntimeStorage().stagingFileURL(for: profile)
      do {
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: location, to: destination)
        stagingURL = destination
      } catch {
        stagingURL = nil
      }
    } else {
      stagingURL = nil
    }
    Task { @MainActor [weak owner] in
      owner?.backgroundDownloadFinished(artifactID: artifactID, stagingURL: stagingURL)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let artifactID = task.taskDescription, let error else { return }
    Task { @MainActor [weak owner] in
      owner?.backgroundDownloadFailed(artifactID: artifactID, error: error)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor [weak owner] in
      owner?.backgroundSessionDidFinishEvents()
    }
  }
}

@MainActor
final class LocalModelArtifactDownloadCoordinator: ObservableObject {
  static let shared = LocalModelArtifactDownloadCoordinator()
  static let backgroundSessionIdentifier = "com.galaxyssi.chat.ios.local-models"

  @Published private(set) var states: [String: LocalModelArtifactInstallState] = [:]
  @Published private(set) var errors: [String: String] = [:]
  @Published private(set) var progress: [String: LocalModelArtifactProgress] = [:]

  private var backgroundTasks: [String: URLSessionDownloadTask] = [:]
  private var backgroundSourceIndexes: [String: Int] = [:]
  private var backgroundCompletionHandler: (() -> Void)?
  private let backgroundDelegate: LocalModelArtifactDownloadDelegate
  private let backgroundSession: URLSession
  private let fileManager = FileManager.default
  private let storage = LocalModelRuntimeStorage()
  private let stateStorageKey = "galaxyssi.local_model.artifact_states"
  private let stateStorageSecrets: GalaxySSISecretStore

  init(secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    let delegate = LocalModelArtifactDownloadDelegate()
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.backgroundSessionIdentifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.allowsCellularAccess = true
    if #available(iOS 13.0, *) {
      configuration.allowsExpensiveNetworkAccess = true
      configuration.allowsConstrainedNetworkAccess = true
    }
    backgroundDelegate = delegate
    backgroundSession = URLSession(
      configuration: configuration,
      delegate: delegate,
      delegateQueue: nil
    )
    stateStorageSecrets = secrets
    delegate.owner = self
    loadPersistedStates()
    backgroundSession.getAllTasks { [weak self] tasks in
      let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
      Task { @MainActor in
        self?.restoreBackgroundTasks(downloadTasks)
      }
    }
  }

  nonisolated static func handleBackgroundEvents(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      guard identifier == Self.backgroundSessionIdentifier else {
        completionHandler()
        return
      }
      Self.shared.backgroundCompletionHandler = completionHandler
    }
  }

  func state(for artifact: LocalModelHubArtifact) -> LocalModelArtifactInstallState {
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    if storage.inspect(profile).installed {
      return .ready
    }
    let saved = states[artifact.id] ?? .notInstalled
    if [.downloading, .verifying, .installing].contains(saved),
       backgroundTasks[artifact.id] == nil {
      return partialBytes(for: profile) > 0 ? .paused : .notInstalled
    }
    if saved == .notInstalled && partialBytes(for: profile) > 0 {
      return .paused
    }
    if saved == .notInstalled,
       fileManager.fileExists(atPath: storage.resumeDataFileURL(for: profile).path) {
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

  func requiresMeteredNetworkConfirmation() -> Bool {
    let probe = AgentMediaNetworkDetector.shared.currentProbe
    return probe.metered || probe.cellular
  }

  func start(_ artifact: LocalModelHubArtifact) {
    guard backgroundTasks[artifact.id] == nil else { return }
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
    enqueueBackgroundDownload(artifact, sourceIndex: 0)
  }

  func cancel(_ artifact: LocalModelHubArtifact) {
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    let resumeURL = storage.resumeDataFileURL(for: profile)
    let hadBackgroundTask = backgroundTasks[artifact.id] != nil
    backgroundTasks[artifact.id]?.cancel { data in
      guard let data, !data.isEmpty else { return }
      try? data.write(to: resumeURL, options: .atomic)
    }
    backgroundTasks.removeValue(forKey: artifact.id)
    backgroundSourceIndexes.removeValue(forKey: artifact.id)
    let partial = partialBytes(for: profile)
    states[artifact.id] = hadBackgroundTask || partial > 0 ? .paused : .notInstalled
    progress[artifact.id] = LocalModelArtifactProgress(
      bytesDownloaded: partial,
      totalBytes: artifact.sizeBytes
    )
    persistStates()
  }

  func delete(_ artifact: LocalModelHubArtifact) {
    backgroundTasks[artifact.id]?.cancel()
    backgroundTasks.removeValue(forKey: artifact.id)
    backgroundSourceIndexes.removeValue(forKey: artifact.id)
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

  fileprivate func backgroundDownloadProgress(
    artifactID: String,
    bytesDownloaded: Int64,
    totalBytes: Int64
  ) {
    guard backgroundTasks[artifactID] != nil else { return }
    progress[artifactID] = LocalModelArtifactProgress(
      bytesDownloaded: max(0, bytesDownloaded),
      totalBytes: max(0, totalBytes)
    )
  }

  fileprivate func backgroundDownloadFinished(artifactID: String, stagingURL: URL?) {
    backgroundTasks.removeValue(forKey: artifactID)
    guard let stagingURL,
          let artifact = artifact(for: artifactID) else {
      finishBackgroundFailure(
        artifactID: artifactID,
        error: LocalModelArtifactDownloadError.httpStatus
      )
      return
    }
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    do {
      states[artifactID] = .verifying
      persistStates()
      let size = try fileManager.attributesOfItem(atPath: stagingURL.path)[.size] as? NSNumber
      guard size?.int64Value == artifact.sizeBytes else {
        throw LocalModelArtifactDownloadError.sizeMismatch
      }
      let actualHash = try LocalModelRuntimeStorage.sha256(fileURL: stagingURL)
      guard actualHash == artifact.sha256.lowercased() else {
        throw LocalModelArtifactDownloadError.sha256Mismatch
      }
      states[artifactID] = .installing
      persistStates()
      _ = try storage.installVerifiedFile(
        stagingURL,
        profile: profile,
        downloadURL: artifact.downloadURL
      )
      try? fileManager.removeItem(at: storage.resumeDataFileURL(for: profile))
      LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: true)
      progress[artifactID] = LocalModelArtifactProgress(
        bytesDownloaded: artifact.sizeBytes,
        totalBytes: artifact.sizeBytes
      )
      states[artifactID] = .ready
      errors[artifactID] = nil
      persistStates()
    } catch {
      finishBackgroundFailure(artifactID: artifactID, error: error)
    }
  }

  fileprivate func backgroundDownloadFailed(artifactID: String, error: Error) {
    guard states[artifactID] == .downloading else { return }
    backgroundTasks.removeValue(forKey: artifactID)
    guard let artifact = artifact(for: artifactID) else {
      finishBackgroundFailure(artifactID: artifactID, error: error)
      return
    }
    let nextIndex = (backgroundSourceIndexes[artifactID] ?? 0) + 1
    let sources = LocalModelArtifactDownloadSources.urls(for: artifact)
    guard nextIndex < sources.count else {
      finishBackgroundFailure(artifactID: artifactID, error: error)
      return
    }
    backgroundSourceIndexes[artifactID] = nextIndex
    enqueueBackgroundDownload(artifact, sourceIndex: nextIndex)
  }

  fileprivate func backgroundSessionDidFinishEvents() {
    let handler = backgroundCompletionHandler
    backgroundCompletionHandler = nil
    handler?()
  }

  private func enqueueBackgroundDownload(_ artifact: LocalModelHubArtifact, sourceIndex: Int) {
    let sources = LocalModelArtifactDownloadSources.urls(for: artifact)
    guard sourceIndex >= 0, sourceIndex < sources.count else {
      finishBackgroundFailure(
        artifactID: artifact.id,
        error: LocalModelArtifactDownloadError.httpStatus
      )
      return
    }
    let sourceURL = sources[sourceIndex]
    var request = URLRequest(url: sourceURL)
    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
    request.setValue("GalaxySSI-iOS", forHTTPHeaderField: "User-Agent")
    let profile = LocalModelRuntimeCatalog.profile(for: artifact)
    let task: URLSessionDownloadTask
    if sourceIndex == 0,
       let resumeData = try? Data(contentsOf: storage.resumeDataFileURL(for: profile)),
       !resumeData.isEmpty {
      task = backgroundSession.downloadTask(withResumeData: resumeData)
    } else {
      task = backgroundSession.downloadTask(with: request)
    }
    task.taskDescription = artifact.id
    backgroundSourceIndexes[artifact.id] = sourceIndex
    backgroundTasks[artifact.id] = task
    states[artifact.id] = .downloading
    persistStates()
    task.resume()
  }

  private func restoreBackgroundTasks(_ tasks: [URLSessionDownloadTask]) {
    for task in tasks {
      guard let artifactID = task.taskDescription,
            artifact(for: artifactID) != nil else {
        task.cancel()
        continue
      }
      backgroundTasks[artifactID] = task
      states[artifactID] = .downloading
    }
    persistStates()
  }

  private func finishBackgroundFailure(artifactID: String, error: Error) {
    let profile = artifact(for: artifactID).map { LocalModelRuntimeCatalog.profile(for: $0) }
    let partial = profile.map(partialBytes(for:)) ?? 0
    states[artifactID] = .failed
    progress[artifactID] = LocalModelArtifactProgress(
      bytesDownloaded: partial,
      totalBytes: profile?.expectedModelFileBytes ?? 0
    )
    errors[artifactID] = error.localizedDescription
    backgroundSourceIndexes.removeValue(forKey: artifactID)
    persistStates()
  }

  private func artifact(for artifactID: String) -> LocalModelHubArtifact? {
    LocalModelRuntimeCatalog.profiles()
      .compactMap { LocalModelRuntimeCatalog.artifact(for: $0) }
      .first { $0.id == artifactID }
  }

  func destinationURL(for artifact: LocalModelHubArtifact) -> URL {
    storage.finalFileURL(for: LocalModelRuntimeCatalog.profile(for: artifact))
  }

  private func loadPersistedStates() {
    let defaults = UserDefaults.standard
    let values: [String: String]
    if let encryptedData = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: stateStorageKey,
      secrets: stateStorageSecrets
    ),
    let encryptedValues = try? JSONDecoder().decode([String: String].self, from: encryptedData) {
      values = encryptedValues
    } else {
      // Migrate the pre-encryption dictionary on first launch after upgrade.
      values = defaults.dictionary(forKey: stateStorageKey) as? [String: String] ?? [:]
    }
    states = values.reduce(into: [:]) { result, entry in
      if let state = LocalModelArtifactInstallState(rawValue: entry.value) {
        result[entry.key] = state
      }
    }
    if defaults.object(forKey: stateStorageKey) != nil {
      persistStates()
    }
  }

  private func persistStates() {
    guard let data = try? JSONEncoder().encode(states.mapValues(\.rawValue)) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: UserDefaults.standard,
      key: stateStorageKey,
      secrets: stateStorageSecrets
    )
  }

  private func partialBytes(for profile: LocalModelRuntimeProfile) -> Int64 {
    let url = storage.stagingFileURL(for: profile)
    let values = try? fileManager.attributesOfItem(atPath: url.path)
    return max(0, (values?[.size] as? NSNumber)?.int64Value ?? 0)
  }

}

enum LocalModelArtifactDownloadError: LocalizedError {
  case httpStatus
  case sizeMismatch
  case sha256Mismatch
  case insufficientStorage(required: Int64, available: Int64)

  var errorDescription: String? {
    switch self {
    case .httpStatus: return "Model source returned an invalid HTTP response"
    case .sizeMismatch: return "Downloaded model size does not match its pinned metadata"
    case .sha256Mismatch: return "Downloaded model failed SHA-256 verification"
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
    let repositoryVisionCapable = model.visionCapable || containsVisionTag(root["tags"])
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
        source: .huggingFace,
        visionCapable: repositoryVisionCapable
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
      guard let fileName = [path, name].compactMap({ (value: String?) -> String? in
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
        source: .modelScope,
        visionCapable: model.visionCapable
      )
    }
    .sorted { $0.sizeBytes < $1.sizeBytes }
  }

  private static func requestData(url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("GalaxySSI-iOS", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  private static func containsVisionTag(_ value: Any?) -> Bool {
    let tags: [String]
    if let strings = value as? [String] {
      tags = strings
    } else if let values = value as? [Any] {
      tags = values.compactMap { $0 as? String }
    } else {
      return false
    }
    return tags.contains { tag in
      let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalized == "image-text-to-text" ||
        normalized == "task:image-text-to-text" ||
        normalized == "vision"
    }
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

struct GalaxySSILocalModelHubArtifactView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @StateObject private var downloads = LocalModelArtifactDownloadCoordinator.shared
  @State private var artifacts: [LocalModelHubArtifact] = []
  @State private var loading = true
  @State private var statusMessage = ""
  @State private var artifactToDelete: LocalModelHubArtifact?
  @State private var showingDeleteConfirmation = false
  @State private var artifactToStart: LocalModelHubArtifact?
  @State private var showingMeteredDownloadConfirmation = false
  var model: LocalModelHubSearchResult

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(title: model.displayName, leading: { GalaxySSIBackButton() }, trailing: { Color.clear })
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSILocalModelLabHeroView(
            title: model.displayName,
            subtitle: t("galaxyssi.local_model.artifact_subtitle", "Choose a GGUF artifact with pinned size and SHA-256 metadata"),
            systemImage: "doc.badge.gearshape",
            tint: .galaxySSIAccent,
            badge: sourceLabel(model.source)
          )
          if loading {
            GalaxySSILocalModelLabStatusRow(title: t("galaxyssi.local_model.artifact_loading", "Loading artifacts"), subtitle: model.id, systemImage: "hourglass", tint: .blue, badge: "...")
          } else if artifacts.isEmpty {
            GalaxySSILocalModelLabStatusRow(title: t("galaxyssi.local_model.artifact_empty", "No verified GGUF artifacts"), subtitle: statusMessage, systemImage: "info.circle", tint: .orange, badge: t("galaxyssi.status.unknown", "Unknown"))
          } else {
            GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.artifact_section", "GGUF Artifacts"))
            ForEach(artifacts) { artifact in
              artifactRow(artifact)
            }
          }
          if !statusMessage.isEmpty && !loading {
            GalaxySSILocalModelLabStatusRow(title: t("galaxyssi.local_model.status", "Status"), subtitle: statusMessage, systemImage: "info.circle", tint: .blue, badge: t("galaxyssi.status.ready", "Ready"))
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .confirmationDialog(
      t("galaxyssi.local_model.delete_title", "Delete downloaded model?"),
      isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(t("galaxyssi.local_model.delete_action", "Delete"), role: .destructive) {
        guard let artifact = artifactToDelete else { return }
        downloads.delete(artifact)
        statusMessage = t("galaxyssi.local_model.download_deleted", "Downloaded model deleted")
        artifactToDelete = nil
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        artifactToDelete = nil
      }
    }
    .alert(
      t("galaxyssi.local_model.metered_download_title", "Download over cellular data?"),
      isPresented: $showingMeteredDownloadConfirmation
    ) {
      Button(t("galaxyssi.local_model.metered_download_confirm", "Download")) {
        guard let artifact = artifactToStart else { return }
        startDownload(artifact)
        artifactToStart = nil
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        artifactToStart = nil
      }
    } message: {
      Text(String(format: t(
        "galaxyssi.local_model.metered_download_message",
        "This model is %@. Downloading it over cellular or a metered connection may use significant data."
      ), formatBytes(artifactToStart?.sizeBytes ?? 0)))
    }
    .task { await loadArtifacts() }
  }

  private func artifactRow(_ artifact: LocalModelHubArtifact) -> some View {
    let state = downloads.state(for: artifact)
    let artifactProgress = downloads.progress(for: artifact)
    let downloadError = downloads.error(for: artifact)
    return GalaxySSILocalModelLabActionRow(
      title: artifact.displayName,
      subtitle: artifactSubtitle(
        artifact,
        state: state,
        progress: artifactProgress,
        error: downloadError
      ),
      systemImage: "arrow.down.circle",
      tint: state == .ready ? .galaxySSIAccent : .blue,
      badge: stateLabel(state, progress: artifactProgress)
    ) {
      switch state {
      case .downloading, .verifying, .installing:
        downloads.cancel(artifact)
        statusMessage = t("galaxyssi.local_model.download_cancelled", "Download cancelled")
      case .ready:
        artifactToDelete = artifact
        showingDeleteConfirmation = true
      case .notInstalled, .failed, .paused:
        if downloads.requiresMeteredNetworkConfirmation() {
          artifactToStart = artifact
          showingMeteredDownloadConfirmation = true
        } else {
          startDownload(artifact)
        }
      }
    }
  }

  private func startDownload(_ artifact: LocalModelHubArtifact) {
    let previousState = downloads.state(for: artifact)
    downloads.start(artifact)
    statusMessage = downloads.state(for: artifact) == .failed
      ? downloads.error(for: artifact) ?? t("galaxyssi.local_model.download_failed", "Download failed")
      : previousState == .paused
      ? t("galaxyssi.local_model.download_resumed", "Download resumed")
      : t("galaxyssi.local_model.download_started", "Download started")
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
    case .verifying:
      return "\(t("galaxyssi.local_model.download_verifying", "Verifying")) - \(details)"
    case .installing:
      return "\(t("galaxyssi.local_model.download_installing", "Installing")) - \(details)"
    case .notInstalled, .ready, .failed:
      return details + failure
    }
  }

  private func stateLabel(_ state: LocalModelArtifactInstallState, progress: LocalModelArtifactProgress) -> String {
    switch state {
    case .notInstalled: return t("galaxyssi.local_model.download_action", "Download")
    case .paused: return t("galaxyssi.local_model.download_resume", "Resume")
    case .downloading: return "\(progress.percent)%"
    case .verifying: return t("galaxyssi.local_model.download_verifying", "Verifying")
    case .installing: return t("galaxyssi.local_model.download_installing", "Installing")
    case .ready: return t("galaxyssi.local_model.download_delete", "Delete")
    case .failed: return t("galaxyssi.common.retry", "Retry")
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
      return t("galaxyssi.local_model.source_huggingface", "Hugging Face")
    case .modelScope:
      return t("galaxyssi.local_model.source_modelscope", "ModelScope")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
