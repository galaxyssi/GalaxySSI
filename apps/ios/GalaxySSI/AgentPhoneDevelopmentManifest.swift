import Foundation

struct AgentPhoneDevelopmentManifestFile: Equatable {
  var path: String
  var content: String
}

struct AgentPhoneDevelopmentManifest: Equatable {
  static let schema = "galaxyssi.phone-development-manifest.v2"

  var decisionSummary: String
  var entryFile: String
  var files: [AgentPhoneDevelopmentManifestFile]
  var requiredPacks: [String]
  var artifactPaths: [String]

  func runtimeInput() -> AgentMcpJSONObject {
    let encodedFiles: [AgentMcpJSONValue] = files.map { file in
      .object([
        "path": .string(file.path),
        "content_b64": .string(Data(file.content.utf8).base64EncodedString())
      ])
    }
    let source = """
    import base64
    import json
    import os
    import pathlib
    import runpy

    _galaxyssi_files = json.loads(base64.b64decode(\"\(Data(AgentMcpJSONCodec.stringify(.array(encodedFiles)).utf8).base64EncodedString())\").decode(\"utf-8\"))
    for _galaxyssi_file in _galaxyssi_files:
        _galaxyssi_path = pathlib.Path(_galaxyssi_file[\"path\"])
        _galaxyssi_path.parent.mkdir(parents=True, exist_ok=True)
        _galaxyssi_path.write_text(base64.b64decode(_galaxyssi_file[\"content_b64\"]).decode(\"utf-8\"), encoding=\"utf-8\")
    os.chdir(os.getcwd())
    runpy.run_path(\"\(entryFile)\", run_name=\"__main__\")
    """
    let artifactPaths = Array(Set((files.map(\.path) + self.artifactPaths).filter { !$0.isEmpty })).sorted()
    return [
      "language": .string(AgentRuntimeLanguage.python.rawValue),
      "source": .string(source),
      "arguments": .array([]),
      "timeout_ms": .int(180_000),
      "network_enabled": .bool(false),
      "allowed_network_domains": .array([]),
      "artifact_paths": .array(artifactPaths.map(AgentMcpJSONValue.string))
    ]
  }
}

enum AgentPhoneDevelopmentManifestCodec {
  static let manifestKey = "phone_development_manifest"

  enum ParseError: LocalizedError, Equatable {
    case missing
    case unsupportedSchema
    case unsupportedLanguage
    case invalidSummary
    case invalidEntryFile
    case invalidFilePath(String)
    case duplicateFile(String)
    case invalidFileContent(String)
    case invalidArtifactPath(String)
    case invalidPack(String)
    case limitExceeded(String)

    var errorDescription: String? {
      switch self {
      case .missing: return "Phone development manifest is missing."
      case .unsupportedSchema: return "Phone development manifest schema is unsupported."
      case .unsupportedLanguage: return "Only Python phone development manifests are supported."
      case .invalidSummary: return "Phone development manifest summary is invalid."
      case .invalidEntryFile: return "Phone development manifest entry file is invalid."
      case .invalidFilePath(let path): return "Phone development manifest path is unsafe: \(path)"
      case .duplicateFile(let path): return "Phone development manifest contains a duplicate file: \(path)"
      case .invalidFileContent(let path): return "Phone development manifest file content is invalid: \(path)"
      case .invalidArtifactPath(let path): return "Phone development manifest artifact path is unsafe: \(path)"
      case .invalidPack(let pack): return "Phone development manifest pack is invalid: \(pack)"
      case .limitExceeded(let detail): return "Phone development manifest exceeds \(detail)."
      }
    }
  }

  static func parse(_ object: AgentMcpJSONObject) throws -> AgentPhoneDevelopmentManifest {
    guard object["schema"]?.strictStringValue == AgentPhoneDevelopmentManifest.schema else {
      throw ParseError.unsupportedSchema
    }
    guard object["language"]?.strictStringValue?.lowercased() == AgentRuntimeLanguage.python.rawValue else {
      throw ParseError.unsupportedLanguage
    }
    let summary = object["decision_summary"]?.strictStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !summary.isEmpty, summary.count <= maximumSummaryCharacters else {
      throw summary.isEmpty ? ParseError.invalidSummary : ParseError.limitExceeded("summary length")
    }
    let entryFile = try safeRelativePath(object["entry_file"]?.strictStringValue ?? "", entry: true)
    guard let rawFiles = object["files"]?.arrayValue, !rawFiles.isEmpty else {
      throw ParseError.limitExceeded("at least one file")
    }
    guard rawFiles.count <= maximumFileCount else {
      throw ParseError.limitExceeded("file count")
    }
    var seenPaths = Set<String>()
    var totalBytes = 0
    let files = try rawFiles.map { raw -> AgentPhoneDevelopmentManifestFile in
      guard let file = raw.objectValue else {
        throw ParseError.invalidFileContent("unknown")
      }
      let path = try safeRelativePath(file["path"]?.strictStringValue ?? "", entry: false)
      guard seenPaths.insert(path).inserted else {
        throw ParseError.duplicateFile(path)
      }
      let content = file["content"]?.strictStringValue ?? ""
      guard !content.isEmpty, Data(content.utf8).count <= maximumFileBytes else {
        throw content.isEmpty ? ParseError.invalidFileContent(path) : ParseError.limitExceeded("file size")
      }
      totalBytes += Data(content.utf8).count
      guard totalBytes <= maximumTotalBytes else {
        throw ParseError.limitExceeded("total file size")
      }
      return AgentPhoneDevelopmentManifestFile(path: path, content: content)
    }
    guard seenPaths.contains(entryFile) else {
      throw ParseError.invalidEntryFile
    }
    let requiredPacks = try stringList(object["required_packs"]?.arrayValue ?? [], limit: maximumPackCount) { pack in
      guard pack.range(of: packPattern, options: .regularExpression) != nil,
            AgentIOSOnDeviceRuntimeNativeToolCatalog.requiredPacks.contains(pack) else {
        throw ParseError.invalidPack(pack)
      }
      return pack
    }
    let artifactPaths = try stringList(object["artifact_paths"]?.arrayValue ?? [], limit: maximumArtifactCount) { path in
      guard safePath(path) else {
        throw ParseError.invalidArtifactPath(path)
      }
      return path
    }
    return AgentPhoneDevelopmentManifest(
      decisionSummary: summary,
      entryFile: entryFile,
      files: files,
      requiredPacks: requiredPacks,
      artifactPaths: artifactPaths
    )
  }

  static func materializedInput(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    guard let manifestObject = input[manifestKey]?.objectValue else {
      return input
    }
    let manifest = try parse(manifestObject)
    return manifest.runtimeInput()
  }

  private static func safeRelativePath(_ raw: String, entry: Bool) throws -> String {
    let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard safePath(path) else {
      throw entry ? ParseError.invalidEntryFile : ParseError.invalidFilePath(path)
    }
    return path
  }

  private static func safePath(_ path: String) -> Bool {
    path.range(of: pathPattern, options: .regularExpression) != nil &&
      !path.split(separator: "/").contains { $0 == ".." }
  }

  private static func stringList<T>(
    _ values: [AgentMcpJSONValue],
    limit: Int,
    transform: (String) throws -> T
  ) throws -> [T] where T: Equatable {
    guard values.count <= limit else {
      throw ParseError.limitExceeded("list length")
    }
    var result: [T] = []
    for value in values {
      guard let raw = value.strictStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        throw ParseError.limitExceeded("list item")
      }
      let item = try transform(raw)
      guard !result.contains(item) else { continue }
      result.append(item)
    }
    return result
  }

  private static let pathPattern = #"^[A-Za-z0-9][A-Za-z0-9._/-]{0,159}$"#
  private static let packPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#
  private static let maximumSummaryCharacters = 600
  private static let maximumFileCount = 64
  private static let maximumFileBytes = 128 * 1024
  private static let maximumTotalBytes = 160 * 1024
  private static let maximumPackCount = 8
  private static let maximumArtifactCount = 16
}
