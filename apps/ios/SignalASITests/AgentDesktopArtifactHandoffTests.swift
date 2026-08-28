import CryptoKit
import Foundation
import XCTest
@testable import SignalASI

final class AgentDesktopArtifactHandoffTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func tearDownWithError() throws {
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots.removeAll()
  }

  func testDesktopArtifactStoreReassemblesAndResolvesWithoutPrivatePathLeak() throws {
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let root = temporaryDirectory("desktop-artifacts")
    let store = AgentDesktopArtifactStore(rootURL: root, cipher: cipher)
    let bytes = Data((0..<300_000).map { UInt8($0 % 251) })
    let digest = sha256(bytes)
    let artifactURI = "signalasi-artifact://task/outputs/result.bin"
    let artifactId = sha256(Data("\(artifactURI)\u{0}\(digest)".utf8))
    let first = bytes.prefix(256 * 1_024)
    let second = bytes.suffix(bytes.count - first.count)

    let pending = try store.ingest(
      payload(
        artifactId: artifactId,
        artifactURI: artifactURI,
        fullDigest: digest,
        fullSize: bytes.count,
        index: 0,
        count: 2,
        chunk: Data(first),
        originalSize: 500_000
      )
    )
    XCTAssertFalse(pending.completed)

    let completed = try store.ingest(
      payload(
        artifactId: artifactId,
        artifactURI: artifactURI,
        fullDigest: digest,
        fullSize: bytes.count,
        index: 1,
        count: 2,
        chunk: Data(second),
        originalSize: 500_000
      )
    )
    XCTAssertTrue(completed.completed)

    let resolved = store.resolveBlock(
      AgentRichBlock(
        id: "artifact",
        type: .file,
        title: "result.bin",
        text: "outputs \u{00B7} 488.3 KB",
        uri: artifactURI,
        mimeType: "application/octet-stream",
        metadata: [
          "transport": "encrypted-fragmented",
          "category": "outputs",
          "size": "488.3 KB",
          "size_bytes": "500000"
        ]
      )
    )

    XCTAssertTrue(resolved.uri.hasPrefix("signalasi-local-artifact://"))
    XCTAssertFalse(AgentRichContentCodec.encode([resolved]).contains("host_path"))
    XCTAssertEqual(resolved.text, "outputs \u{00B7} 293.0 KB")
    XCTAssertEqual(resolved.metadata["size_bytes"], "300000")
    XCTAssertEqual(resolved.metadata["original_size_bytes"], "500000")
    XCTAssertEqual(resolved.metadata["storage"], "attachment_aes_256_gcm")
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.localFile(for: resolved))), bytes)
    let encrypted = root.appendingPathComponent("files/\(artifactId).saenc")
    XCTAssertTrue(cipher.isEncryptedFile(encrypted))
    XCTAssertNotEqual(try Data(contentsOf: encrypted), bytes)
  }

  func testRichContentCodecDeduplicatesArtifactsAndFailsClosed() {
    let digest = String(repeating: "a", count: 64)
    let encoded = """
    {
      "version": 1,
      "blocks": [
        {
          "id": "relative-only",
          "type": "file",
          "title": "marked.jpg",
          "uri": "outputs/marked.jpg",
          "metadata": {"sha256": "\(digest)"}
        },
        {
          "id": "previewable",
          "type": "image",
          "title": "marked.jpg",
          "uri": "signalasi-artifact://task/outputs/marked.jpg",
          "data_b64": "aW1hZ2U=",
          "mime_type": "image/jpeg",
          "metadata": {"sha256": "\(digest)"}
        }
      ]
    }
    """

    let block = AgentRichContentCodec.decode(encoded).singleValue()
    XCTAssertEqual(block.id, "previewable")
    XCTAssertEqual(block.type, .image)
    XCTAssertEqual(block.dataB64, "aW1hZ2U=")
    XCTAssertTrue(AgentRichContentCodec.decode("not-json").isEmpty)
    XCTAssertTrue(AgentRichContentCodec.decode(#"{"version":99,"blocks":[]}"#).isEmpty)
  }

  func testRichContentMaterializerEncryptsInlinePayload() throws {
    let root = temporaryDirectory("rich-content")
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let materializer = AgentRichContentMaterializer(directoryURL: root, cipher: cipher)
    let bytes = Data("inline private file".utf8)
    let raw = AgentRichContentCodec.encode([
      AgentRichBlock(
        id: "inline",
        type: .file,
        title: "private.txt",
        dataB64: bytes.base64EncodedString(),
        mimeType: "text/plain"
      )
    ])

    let block = AgentRichContentCodec.decode(materializer.materialize(raw)).singleValue()
    let encrypted = try XCTUnwrap(URL(string: block.uri))
    let purpose = try XCTUnwrap(block.metadata["encryption_purpose"])

    XCTAssertTrue(cipher.isEncryptedFile(encrypted))
    XCTAssertEqual(block.metadata["storage"], "attachment_aes_256_gcm")
    XCTAssertTrue(block.dataB64.isEmpty)
    XCTAssertEqual(try cipher.read(from: encrypted, purpose: purpose), bytes)
  }

  func testRuntimeArtifactCardUsesSafeReferenceAndActions() throws {
    let root = temporaryDirectory("runtime-artifact")
    let source = root.appendingPathComponent("sample.py", isDirectory: false)
    let sourceData = Data("print(42)\n".utf8)
    try sourceData.write(to: source)
    let digest = sha256(sourceData)
    let rich = AgentRuntimeArtifactUi.richOutput(
      output: [
        "artifacts": .array([
          .object([
            "relative_path": .string("sample.py"),
            "host_path": .string("C:/private/agent-native-workspaces/session/sample.py"),
            "size_bytes": .int(Int64(sourceData.count)),
            "sha256": .string(digest),
            "artifact_kind": .string("file")
          ])
        ])
      ],
      responseText: "Written and verified.\n\nRun output:\n\n```text\n42\n```",
      preferredFileName: "sample.py",
      zh: false
    )

    XCTAssertFalse(rich.contains("host_path"))
    let blocks = AgentRichContentCodec.decode(rich)
    let file = try XCTUnwrap(blocks.first { $0.type == .file })
    XCTAssertEqual(file.title, "sample.py")
    XCTAssertTrue(file.uri.hasPrefix("signalasi-runtime-artifact://"))
    XCTAssertEqual(file.actions.map(\.verb), ["preview_runtime_artifact", "save_runtime_artifact"])
    XCTAssertTrue(blocks.contains { $0.type == .code && $0.text == "42" })

    let payload = try XCTUnwrap(AgentRuntimeArtifactActionPayload.decode(file.actions[0].value))
    XCTAssertFalse(payload.encode().contains("host_path"))
    XCTAssertEqual(try AgentRuntimeArtifactUi.resolve(payload: payload, managedRoots: [root]), source)
    XCTAssertEqual(try AgentRuntimeArtifactUi.preview(file: source), "print(42)\n")
  }

  func testArtifactActionsPreviewArchiveAndRejectUnsafeBytes() throws {
    let root = temporaryDirectory("artifact-actions")
    let text = root.appendingPathComponent("notes.txt", isDirectory: false)
    try Data("hello".utf8).write(to: text)
    XCTAssertEqual(try AgentDesktopArtifactActions.readTextPreview(source: text), "hello")

    let binary = root.appendingPathComponent("binary.bin", isDirectory: false)
    try Data([0, 1, 2]).write(to: binary)
    XCTAssertThrowsError(try AgentDesktopArtifactActions.readTextPreview(source: binary))

    let archive = root.appendingPathComponent("docs.zip", isDirectory: false)
    let archiveData = AgentRuntimeProjectArchiveBuilder.buildStoredZip([
      AgentRuntimeProjectArchiveEntry(path: "README.md", data: Data("ok".utf8)),
      AgentRuntimeProjectArchiveEntry(path: "src/main.swift", data: Data("print(1)".utf8))
    ])
    try archiveData.write(to: archive)
    XCTAssertEqual(
      try AgentDesktopArtifactActions.archivePreview(source: archive),
      ["README.md  2 B", "src/main.swift  8 B"]
    )

    let extracted = root.appendingPathComponent("extracted", isDirectory: true)
    let created = try AgentDesktopArtifactActions.extractStoredZip(source: archive, to: extracted)
    XCTAssertEqual(created.count, 2)
    XCTAssertEqual(
      try String(contentsOf: extracted.appendingPathComponent("src/main.swift")),
      "print(1)"
    )
  }

  private func temporaryDirectory(_ name: String) -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("signalasi-ios-tests", isDirectory: true)
      .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    temporaryRoots.append(root)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func payload(
    artifactId: String,
    artifactURI: String,
    fullDigest: String,
    fullSize: Int,
    index: Int,
    count: Int,
    chunk: Data,
    originalSize: Int? = nil
  ) -> [String: Any] {
    [
      "type": "artifact_chunk",
      "artifact_id": artifactId,
      "artifact_uri": artifactURI,
      "task_id": "task",
      "name": "result.bin",
      "mime_type": "application/octet-stream",
      "size_bytes": fullSize,
      "sha256": fullDigest,
      "original_size_bytes": originalSize ?? fullSize,
      "original_sha256": fullDigest,
      "chunk_index": index,
      "chunk_count": count,
      "chunk_size_bytes": chunk.count,
      "chunk_sha256": sha256(chunk),
      "data_b64": chunk.base64EncodedString()
    ]
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
