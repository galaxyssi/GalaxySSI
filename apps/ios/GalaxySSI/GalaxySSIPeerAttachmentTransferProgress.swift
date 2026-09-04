import Foundation
import SwiftUI

struct GalaxySSIPeerAttachmentTransferUpdate: Equatable {
  var transferId: String
  var sourceMessageId: String
  var ordinal: Int
  var name: String
  var mimeType: String
  var sizeBytes: Int64
  var sha256: String
  var progress: Int
  var state: String
  var uri: String
  var storage: String
  var encryptionPurpose: String

  init?(payload: [String: Any]) {
    let transferId = payload.string("transfer_id").lowercased()
    guard !transferId.isEmpty else { return nil }
    self.transferId = transferId
    sourceMessageId = payload.string("source_message_id")
    ordinal = max(0, payload.int("attachment_ordinal"))
    name = payload.string("name").ifBlank("attachment")
    mimeType = payload.string("mime_type").ifBlank("application/octet-stream")
    sizeBytes = max(0, payload.int64("size_bytes"))
    sha256 = payload.string("sha256").lowercased()
    progress = min(100, max(0, payload.int("progress")))
    state = payload.string("state")
    uri = payload.string("uri")
    storage = payload.string("storage")
    encryptionPurpose = payload.string("encryption_purpose")
  }
}

enum GalaxySSIPeerAttachmentTransferProgress {
  static let payloadType = "peer_attachment_progress"
  static let uploading = "uploading"
  static let downloading = "downloading"
  static let complete = "complete"
  static let failed = "failed"

  static func shouldAutoReceive(_ mimeType: String) -> Bool {
    let normalized = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.hasPrefix("image/") || normalized.hasPrefix("audio/")
  }

  static func percent(receivedBytes: Int64, sizeBytes: Int64) -> Int {
    guard sizeBytes > 0 else { return 0 }
    guard receivedBytes < sizeBytes else { return 100 }
    return min(99, max(0, Int(max(0, receivedBytes) * 100 / sizeBytes)))
  }

  static func activeProgress(metadata: [String: String]) -> Int? {
    let state = metadata["transfer_state"] ?? ""
    guard state == uploading || state == downloading,
          let progress = Int(metadata["transfer_progress"] ?? ""),
          (0...99).contains(progress) else { return nil }
    return progress
  }

  static func applying(
    _ update: GalaxySSIPeerAttachmentTransferUpdate,
    to richOutputJson: String
  ) -> String {
    var blocks = AgentRichContentCodec.decode(richOutputJson)
    let index = blocks.firstIndex {
      $0.metadata["transfer_id"] == update.transferId
    } ?? update.ordinal.takeIf { blocks.indices.contains($0) }
    guard let index else {
      blocks.append(block(for: update))
      return AgentRichContentCodec.encode(blocks)
    }
    blocks[index].metadata["transfer_id"] = update.transferId
    blocks[index].metadata["transfer_progress"] = String(update.progress)
    blocks[index].metadata["transfer_state"] = update.state
    blocks[index].metadata["sha256"] = update.sha256
    if !update.uri.isEmpty {
      blocks[index].uri = update.uri
      blocks[index].metadata["artifact_source_uri"] = update.uri
    }
    if !update.storage.isEmpty {
      blocks[index].metadata["storage"] = update.storage
    }
    if !update.encryptionPurpose.isEmpty {
      blocks[index].metadata["encryption_purpose"] = update.encryptionPurpose
    }
    return AgentRichContentCodec.encode(blocks)
  }

  static func placeholder(_ update: GalaxySSIPeerAttachmentTransferUpdate) -> String {
    AgentRichContentCodec.encode([block(for: update)])
  }

  private static func block(for update: GalaxySSIPeerAttachmentTransferUpdate) -> AgentRichBlock {
    var metadata = [
      "source": "peer_message",
      "size_bytes": String(update.sizeBytes),
      "transfer_id": update.transferId,
      "transfer_progress": String(update.progress),
      "transfer_state": update.state,
      "sha256": update.sha256
    ]
    if !update.storage.isEmpty {
      metadata["storage"] = update.storage
    }
    if !update.encryptionPurpose.isEmpty {
      metadata["encryption_purpose"] = update.encryptionPurpose
    }
    return AgentRichBlock(
      id: update.transferId,
      type: update.mimeType.hasPrefix("image/") ? .image : .file,
      title: update.name,
      text: ByteCountFormatter.string(fromByteCount: update.sizeBytes, countStyle: .file),
      uri: update.uri,
      mimeType: update.mimeType,
      fallbackText: update.name,
      metadata: metadata
    )
  }
}

struct GalaxySSIPeerImageTransferProgressOverlay: View {
  var progress: Int

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
      ZStack {
        Circle()
          .stroke(Color.white.opacity(0.45), lineWidth: 3)
        Circle()
          .trim(from: 0, to: CGFloat(progress) / 100)
          .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text("\(progress)%")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(.white)
      }
      .frame(width: 58, height: 58)
    }
  }
}

private extension Int {
  func takeIf(_ predicate: (Int) -> Bool) -> Int? {
    predicate(self) ? self : nil
  }
}
