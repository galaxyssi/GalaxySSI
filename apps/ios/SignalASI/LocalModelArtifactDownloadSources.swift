import Foundation

enum LocalModelArtifactDownloadSources {
  static func urls(for artifact: LocalModelHubArtifact) -> [URL] {
    var candidates = [artifact.downloadURL]
    guard let host = artifact.downloadURL.host?.lowercased(),
          host == "huggingface.co" || host == "hf-mirror.com",
          var components = URLComponents(
            url: artifact.downloadURL,
            resolvingAgainstBaseURL: false
          ) else {
      return candidates
    }

    components.host = host == "huggingface.co" ? "hf-mirror.com" : "huggingface.co"
    if let alternate = components.url, !candidates.contains(alternate) {
      candidates.append(alternate)
    }
    return candidates
  }
}
