import Foundation

enum LocalModelArtifactDownloadSources {
  static func urls(
    for artifact: LocalModelHubArtifact,
    preferMirror: Bool = prefersMirror
  ) -> [URL] {
    guard let huggingFace = huggingFaceURL(for: artifact, host: "huggingface.co"),
          let mirror = huggingFaceURL(for: artifact, host: "hf-mirror.com"),
          let modelScope = modelScopeURL(for: artifact) else {
      return [artifact.downloadURL]
    }

    let ordered: [URL]
    switch artifact.source {
    case .modelScope:
      ordered = [modelScope, mirror, huggingFace]
    case .huggingFace:
      ordered = preferMirror
        ? [mirror, modelScope, huggingFace]
        : [huggingFace, modelScope, mirror]
    }
    return (ordered + [artifact.downloadURL]).reduce(into: []) { result, candidate in
      if !result.contains(candidate) {
        result.append(candidate)
      }
    }
  }

  private static func huggingFaceURL(
    for artifact: LocalModelHubArtifact,
    host: String
  ) -> URL? {
    guard let repository = artifact.repositoryId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let fileName = artifact.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
      return nil
    }
    return URL(string: "https://\(host)/\(repository)/resolve/main/\(fileName)")
  }

  private static func modelScopeURL(for artifact: LocalModelHubArtifact) -> URL? {
    guard let repository = artifact.repositoryId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          var components = URLComponents(
            string: "https://modelscope.cn/api/v1/models/\(repository)/repo"
          ) else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "Revision", value: "master"),
      URLQueryItem(name: "FilePath", value: artifact.fileName)
    ]
    return components.url
  }

  private static var prefersMirror: Bool {
    Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
  }
}
