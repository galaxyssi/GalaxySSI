import CryptoKit
import Foundation

struct AgentRuntimeArtifactActionPayload: Codable, Equatable {
  var artifactReference: String
  var displayName: String
  var relativePath: String
  var mimeType: String
  var sha256: String
  var sizeBytes: Int64
  var kind: String

  enum CodingKeys: String, CodingKey {
    case artifactReference = "artifact_reference"
    case displayName = "display_name"
    case relativePath = "relative_path"
    case mimeType = "mime_type"
    case sha256
    case sizeBytes = "size_bytes"
    case kind
  }

  init(
    artifactReference: String,
    displayName: String,
    relativePath: String,
    mimeType: String,
    sha256: String,
    sizeBytes: Int64,
    kind: String
  ) {
    self.artifactReference = String(artifactReference.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_096))
    self.displayName = AgentRichFormatRegistry.safeFileName(displayName)
    self.relativePath = AgentWorkspaceFilePathPolicy.displayPath(relativePath)
    self.mimeType = String(mimeType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
      .ifBlank("application/octet-stream")
    self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.sizeBytes = max(sizeBytes, 0)
    self.kind = String(kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80)).ifBlank("file")
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      artifactReference: try container.decodeIfPresent(String.self, forKey: .artifactReference) ?? "",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
      relativePath: try container.decodeIfPresent(String.self, forKey: .relativePath) ?? "",
      mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream",
      sha256: try container.decodeIfPresent(String.self, forKey: .sha256) ?? "",
      sizeBytes: try container.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0,
      kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "file"
    )
  }

  func encode() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self) else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> AgentRuntimeArtifactActionPayload? {
    guard let data = raw.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentRuntimeArtifactActionPayload.self, from: data)
  }
}

enum AgentRuntimeArtifactUi {
  static func richOutput(
    output: AgentMcpJSONObject,
    responseText: String,
    preferredFileName: String,
    zh: Bool
  ) -> String {
    let artifacts = output["artifacts"]?.arrayValue ?? []
    let selected = artifacts.compactMap(\.objectValue).first { item in
      item["relative_path"]?.stringValue == preferredFileName ||
        item["artifact_kind"]?.stringValue == "project_archive"
    }
    guard let artifact = selected else {
      return ""
    }
    return richOutput(artifact: artifact, responseText: responseText, preferredFileName: preferredFileName, zh: zh)
  }

  static func richOutput(
    artifact: AgentMcpJSONObject,
    responseText: String,
    preferredFileName: String,
    zh: Bool
  ) -> String {
    let rawRelativePath = artifact["relative_path"]?.stringValue ?? ""
    guard case .success(let relativeSegments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(
      rawRelativePath,
      allowRoot: false
    ) else {
      return ""
    }
    let relativePath = relativeSegments.joined(separator: "/")
    let sha256 = artifact["sha256"]?.stringValue?.lowercased() ?? ""
    let sizeBytes = artifact["size_bytes"]?.intValue ?? 0
    guard sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      sizeBytes >= 0 else {
      return ""
    }
    let kind = (artifact["artifact_kind"]?.stringValue ?? "file").ifBlank("file")
    let displayName = URL(fileURLWithPath: relativePath).lastPathComponent.ifBlank(preferredFileName)
    let mimeType = mimeType(for: relativePath)
    let artifactReference = "galaxyssi-runtime-artifact://\(sha256)/\(AgentWorkspaceFilePathPolicy.displayPath(relativePath))"
    let payload = AgentRuntimeArtifactActionPayload(
      artifactReference: artifactReference,
      displayName: displayName,
      relativePath: relativePath,
      mimeType: mimeType,
      sha256: sha256,
      sizeBytes: sizeBytes,
      kind: kind
    )
    let fileCount = Int(artifact["file_count"]?.intValue ?? 0)
    let detail: String
    if kind == "project_archive" {
      detail = zh
        ? "\(max(fileCount, 1)) files - \(AgentDesktopArtifactStore.humanSize(sizeBytes))"
        : "\(max(fileCount, 1)) files - \(AgentDesktopArtifactStore.humanSize(sizeBytes))"
    } else {
      detail = "\(formatLabel(relativePath)) - \(AgentDesktopArtifactStore.humanSize(sizeBytes))"
    }
    let artifactBlock = AgentRichBlock(
      id: "runtime-artifact:\(sha256.prefix(24))",
      type: .file,
      title: payload.displayName,
      uri: artifactReference,
      mimeType: mimeType,
      language: language(for: relativePath),
      fallbackText: detail,
      actions: runtimeActions(payload: payload, relativePath: relativePath, zh: zh),
      metadata: [
        "runtime_artifact": "true",
        "artifact_kind": kind,
        "artifact_reference": artifactReference,
        "size": AgentDesktopArtifactStore.humanSize(sizeBytes),
        "size_bytes": String(sizeBytes),
        "sha256": sha256,
        "detail": detail,
        "file_count": String(fileCount)
      ]
    )
    var blocks = AgentRichContentCodec.fromText(responseText)
    blocks.insert(artifactBlock, at: min(1, blocks.count))
    return AgentRichContentCodec.encode(blocks)
  }

  static func resolve(payload: AgentRuntimeArtifactActionPayload, managedRoots: [URL]) throws -> URL {
    guard payload.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
      throw AgentDesktopArtifactActionError.invalid("Runtime artifact metadata is invalid")
    }
    let relative = AgentWorkspaceFilePathPolicy.displayPath(payload.relativePath)
    for root in managedRoots.map(\.standardizedFileURL) {
      let candidate = root.appendingPathComponent(relative, isDirectory: false).standardizedFileURL
      guard candidate.path.hasPrefix(root.path + "/") else {
        continue
      }
      guard FileManager.default.fileExists(atPath: candidate.path) else {
        continue
      }
      let fileSize = try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) } ?? -1
      guard fileSize == payload.sizeBytes else {
        continue
      }
      let digest = try AgentDesktopArtifactActions.sha256(source: candidate)
      if digest == payload.sha256 {
        return candidate
      }
    }
    throw AgentDesktopArtifactActionError.unavailable("Runtime artifact is unavailable")
  }

  static func preview(file: URL, maximumBytes: Int = AgentDesktopArtifactActions.maximumTextPreviewBytes) throws -> String {
    if file.pathExtension.lowercased() == "zip" {
      return try AgentDesktopArtifactActions.archivePreview(source: file).joined(separator: "\n")
    }
    return try AgentDesktopArtifactActions.readTextPreview(source: file, maximumBytes: maximumBytes)
  }

  static func isCodeFile(_ url: URL) -> Bool {
    codeExtensions.contains(url.pathExtension.lowercased())
  }

  private static func runtimeActions(
    payload: AgentRuntimeArtifactActionPayload,
    relativePath: String,
    zh: Bool
  ) -> [AgentRichAction] {
    var actions: [AgentRichAction] = []
    if isPreviewable(relativePath) {
      actions.append(
        AgentRichAction(
          id: "preview",
          label: GalaxySSILocalization.string(
            "agent_runtime_artifact_view",
            fallback: "View",
            language: zh ? LanguagePolicySettings.zhCN : LanguagePolicySettings.enUS
          ),
          verb: "preview_runtime_artifact",
          value: payload.encode()
        )
      )
    }
    actions.append(
      AgentRichAction(
        id: "save",
        label: GalaxySSILocalization.string(
          "agent_runtime_artifact_save",
          fallback: "Save",
          language: zh ? LanguagePolicySettings.zhCN : LanguagePolicySettings.enUS
        ),
        verb: "save_runtime_artifact",
        value: payload.encode(),
        style: "primary"
      )
    )
    return actions
  }

  private static func isPreviewable(_ path: String) -> Bool {
    previewExtensions.contains(language(for: path))
  }

  private static func mimeType(for path: String) -> String {
    switch language(for: path) {
    case "py":
      return "text/x-python"
    case "js":
      return "text/javascript"
    case "ts":
      return "text/typescript"
    case "json":
      return "application/json"
    case "md":
      return "text/markdown"
    case "html", "htm":
      return "text/html"
    case "css":
      return "text/css"
    case "zip":
      return "application/zip"
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    default:
      return "text/plain"
    }
  }

  private static func language(for path: String) -> String {
    path.split(separator: "?").first?.split(separator: ".").last.map { String($0).lowercased() } ?? ""
  }

  private static func formatLabel(_ path: String) -> String {
    switch language(for: path) {
    case "py":
      return "Python"
    case "js":
      return "JavaScript"
    case "ts":
      return "TypeScript"
    case "json":
      return "JSON"
    case "md":
      return "Markdown"
    default:
      return "Source"
    }
  }

  private static let codeExtensions = Set(["py", "js", "ts", "java", "kt", "kts", "c", "h", "cpp", "hpp", "rs", "go", "sh"])
  private static let previewExtensions = codeExtensions.union(["txt", "md", "json", "yaml", "yml", "xml", "html", "htm", "css", "toml", "ini", "zip"])
}
