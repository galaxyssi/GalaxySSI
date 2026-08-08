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
  case downloading
  case ready
  case failed
}

@MainActor
final class LocalModelArtifactDownloadCoordinator: ObservableObject {
  @Published private(set) var states: [String: LocalModelArtifactInstallState] = [:]
  @Published private(set) var errors: [String: String] = [:]

  private var tasks: [String: Task<Void, Never>] = [:]
  private let fileManager = FileManager.default
  private let storage = LocalModelRuntimeStorage()

  init() {
    loadPersistedStates()
  }

  func state(for artifact: LocalModelHubArtifact) -> LocalModelArtifactInstallState {
    let profile = LocalModelRuntimeCatalog.hubProfile(for: artifact)
    if storage.inspect(profile).installed {
      return .ready
    }
    return states[artifact.id] ?? .notInstalled
  }

  func start(_ artifact: LocalModelHubArtifact) {
    guard tasks[artifact.id] == nil else { return }
    let profile = LocalModelRuntimeCatalog.addHubArtifact(artifact)
    errors[artifact.id] = nil
    states[artifact.id] = .downloading
    persistStates()
    tasks[artifact.id] = Task { [weak self] in
      do {
        let (temporaryURL, response) = try await URLSession.shared.download(from: artifact.downloadURL)
        try Task.checkCancellation()
        guard let self else { return }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
          throw LocalModelArtifactDownloadError.httpStatus
        }
        let size = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
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
        await MainActor.run {
          self.states[artifact.id] = .ready
          self.errors[artifact.id] = nil
          self.persistStates()
        }
      } catch is CancellationError {
        await MainActor.run {
          self?.states[artifact.id] = .notInstalled
          self?.persistStates()
        }
      } catch {
        await MainActor.run {
          self?.states[artifact.id] = .failed
          self?.errors[artifact.id] = error.localizedDescription
          self?.persistStates()
        }
      }
      await MainActor.run {
        self?.tasks.removeValue(forKey: artifact.id)
      }
    }
  }

  func cancel(_ artifact: LocalModelHubArtifact) {
    tasks[artifact.id]?.cancel()
    tasks.removeValue(forKey: artifact.id)
    states[artifact.id] = .notInstalled
    persistStates()
  }

  func delete(_ artifact: LocalModelHubArtifact) {
    tasks[artifact.id]?.cancel()
    tasks.removeValue(forKey: artifact.id)
    let profile = LocalModelRuntimeCatalog.hubProfile(for: artifact)
    try? storage.delete(profile)
    LocalModelRuntimeCatalog.removeHubProfile(profile)
    states[artifact.id] = .notInstalled
    errors[artifact.id] = nil
    persistStates()
  }

  func destinationURL(for artifact: LocalModelHubArtifact) -> URL {
    storage.finalFileURL(for: LocalModelRuntimeCatalog.hubProfile(for: artifact))
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

}

enum LocalModelArtifactDownloadError: LocalizedError {
  case httpStatus
  case sizeMismatch
  case sha256Mismatch

  var errorDescription: String? {
    switch self {
    case .httpStatus: return "Model source returned an invalid HTTP response"
    case .sizeMismatch: return "Downloaded model size does not match its pinned metadata"
    case .sha256Mismatch: return "Downloaded model failed SHA-256 verification"
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
    return SignalASILocalModelLabActionRow(
      title: artifact.displayName,
      subtitle: "\(formatBytes(artifact.sizeBytes)) - \(artifact.quantization) - \(sourceLabel(artifact.source)) - SHA256 \(artifact.sha256.prefix(12))...",
      systemImage: "arrow.down.circle",
      tint: state == .ready ? .signalASIAccent : .blue,
      badge: stateLabel(state)
    ) {
      switch state {
      case .downloading:
        downloads.cancel(artifact)
        statusMessage = t("signalasi.local_model.download_cancelled", "Download cancelled")
      case .ready:
        artifactToDelete = artifact
        showingDeleteConfirmation = true
      case .notInstalled, .failed:
        downloads.start(artifact)
        statusMessage = t("signalasi.local_model.download_started", "Download started")
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

  private func stateLabel(_ state: LocalModelArtifactInstallState) -> String {
    switch state {
    case .notInstalled: return t("signalasi.local_model.download_action", "Download")
    case .downloading: return t("signalasi.local_model.download_cancel", "Cancel")
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
