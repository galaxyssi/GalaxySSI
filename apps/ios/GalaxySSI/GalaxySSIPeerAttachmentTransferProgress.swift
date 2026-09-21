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
  var peerChat: Bool
  var clientRouteId: String
  var desktopId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var executionGeneration: Int64

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
    peerChat = payload["peer_chat"] as? Bool ?? true
    clientRouteId = payload.string("client_route_id")
    desktopId = payload.string("desktop_id")
    conversationId = payload.string("conversation_id")
    taskId = payload.string("task_id")
    turnId = payload.string("turn_id")
    executionGeneration = payload.int64("execution_generation")
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
    if !update.peerChat, applyGalleryUpdate(update, blocks: &blocks) {
      return AgentRichContentCodec.encode(blocks)
    }
    let index = blocks.firstIndex { block in
      update.peerChat
        ? block.metadata["transfer_id"] == update.transferId
        : scopedMetadata(block.metadata, uri: block.metadata["artifact_source_uri"] ?? block.uri, matches: update)
    } ?? (update.peerChat ? update.ordinal.takeIf { blocks.indices.contains($0) } : nil)
    guard let index else {
      if update.peerChat { blocks.append(block(for: update)) }
      return AgentRichContentCodec.encode(blocks)
    }
    if blocks[index].metadata["transfer_state"] == complete {
      return richOutputJson
    }
    blocks[index].metadata["transfer_id"] = update.transferId
    blocks[index].metadata["transfer_progress"] = String(presentationProgress(update))
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

  private static func applyGalleryUpdate(
    _ update: GalaxySSIPeerAttachmentTransferUpdate,
    blocks: inout [AgentRichBlock]
  ) -> Bool {
    for blockIndex in blocks.indices where blocks[blockIndex].type == .gallery {
      for (key, encoded) in blocks[blockIndex].metadata where key.hasPrefix("blob_item_") {
        guard let data = encoded.data(using: .utf8),
              var metadata = try? JSONDecoder().decode([String: String].self, from: data),
              scopedMetadata(metadata, uri: metadata["artifact_source_uri"] ?? "", matches: update) else {
          continue
        }
        if metadata["transfer_state"] == complete { return true }
        metadata["transfer_progress"] = String(presentationProgress(update))
        metadata["transfer_state"] = update.state
        if !update.storage.isEmpty { metadata["storage"] = update.storage }
        guard let replacement = try? JSONEncoder().encode(metadata),
              let replacementText = String(data: replacement, encoding: .utf8) else {
          return false
        }
        blocks[blockIndex].metadata[key] = replacementText
        return true
      }
    }
    return false
  }

  private static func scopedMetadata(
    _ metadata: [String: String],
    uri: String,
    matches update: GalaxySSIPeerAttachmentTransferUpdate
  ) -> Bool {
    metadata["blob_client_route_id"] == update.clientRouteId &&
      metadata["blob_desktop_id"] == update.desktopId &&
      metadata["blob_conversation_id"] == update.conversationId &&
      metadata["blob_task_id"] == update.taskId &&
      metadata["blob_turn_id"] == update.turnId &&
      metadata["blob_execution_generation"] == String(update.executionGeneration) &&
      metadata["transfer_id"]?.lowercased() == update.transferId &&
      uri == update.uri &&
      metadata["sha256"]?.lowercased() == update.sha256 &&
      metadata["size_bytes"] == String(update.sizeBytes)
  }

  private static func presentationProgress(_ update: GalaxySSIPeerAttachmentTransferUpdate) -> Int {
    update.state == complete ? 100 : min(99, update.progress)
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
