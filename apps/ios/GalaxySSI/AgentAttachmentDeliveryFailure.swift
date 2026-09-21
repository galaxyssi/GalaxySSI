import Foundation

enum AgentAttachmentDeliveryFailureContract {
  static let terminalCodes: Set<String> = [
    "blob_expired",
    "blob_not_found",
    "blob_source_missing",
    "source_changed",
    "chunk_authentication_failed",
    "ciphertext_hash_mismatch",
    "plaintext_hash_mismatch",
    "manifest_hash_mismatch",
    "file_size_mismatch",
    "transfer_binding_mismatch",
    "local_chunk_missing_or_corrupt",
    "blob_outgoing_identity_mismatch"
  ]

  static func isTerminal(_ code: String) -> Bool {
    terminalCodes.contains(code.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  static func observation(_ code: String) -> String {
    guard isTerminal(code) else { return "" }
    return "Attachment transfer failed: \(code). No verified attachment was delivered. " +
      "Inspect the attachment source and request a fresh transfer when appropriate. " +
      "Do not assume the file or image is available, and do not report a provider outage from this error."
  }

  static func matches(
    receipt: [String: Any],
    attachment: AgentPreparedOutboundAttachment
  ) -> Bool {
    let code = receipt.string("error_code")
    guard receipt.string("status") == "failed",
          isTerminal(code),
          receipt.string("transfer_id").lowercased() == attachment.transferId,
          receipt.string("sha256").lowercased() == attachment.sha256,
          receipt.string("client_route_id") == attachment.scope.clientRouteId,
          receipt.string("conversation_id") == attachment.scope.conversationId,
          receipt.string("task_id") == attachment.scope.taskId,
          receipt.string("turn_id") == attachment.scope.turnId,
          receipt.string("contact_id") == attachment.scope.contactId else {
      return false
    }
    guard let clientMessageId = attachment.scope.clientMessageId else { return true }
    return receipt.string("source_message_id") == clientMessageId
  }
}

struct AgentAttachmentDeliveryFailureObservation: Codable, Equatable, Identifiable {
  var id: String { "\(transferId):\(errorCode)" }
  var transferId: String
  var sourceMessageId: String
  var contactId: String
  var desktopId: String
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var errorCode: String
  var observedAtMillis: Int64
}

final class AgentAttachmentDeliveryFailureStore {
  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSLock()
  private let maximumObservations = 256

  init(
    applicationSupportDirectory: URL? = nil,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    fileManager: FileManager = .default
  ) {
    let support = applicationSupportDirectory ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    self.fileURL = support
      .appendingPathComponent("attachment-delivery-failures-v1", isDirectory: true)
      .appendingPathComponent("observations.saenc", isDirectory: false)
    self.cipher = cipher
  }

  @discardableResult
  func record(
    receipt: [String: Any],
    attachment: AgentPreparedOutboundAttachment,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) throws -> AgentAttachmentDeliveryFailureObservation {
    guard AgentAttachmentDeliveryFailureContract.matches(
      receipt: receipt,
      attachment: attachment
    ) else {
      throw AgentAttachmentTransferError.invalidScope
    }
    let observation = AgentAttachmentDeliveryFailureObservation(
      transferId: attachment.transferId,
      sourceMessageId: attachment.scope.clientMessageId ?? "",
      contactId: attachment.scope.contactId,
      desktopId: attachment.scope.desktopId,
      clientRouteId: attachment.scope.clientRouteId,
      conversationId: attachment.scope.conversationId,
      taskId: attachment.scope.taskId,
      turnId: attachment.scope.turnId,
      errorCode: receipt.string("error_code"),
      observedAtMillis: max(nowMillis, 0)
    )
    lock.lock()
    defer { lock.unlock() }
    var values = loadLocked()
    values.removeAll { $0.id == observation.id }
    values.append(observation)
    values = Array(values.suffix(maximumObservations))
    try cipher.write(
      JSONEncoder().encode(values),
      to: fileURL,
      purpose: "attachment-delivery-failures-v1"
    )
    return observation
  }

  func observations() -> [AgentAttachmentDeliveryFailureObservation] {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked()
  }

  private func loadLocked() -> [AgentAttachmentDeliveryFailureObservation] {
    guard let data = try? cipher.read(
      from: fileURL,
      purpose: "attachment-delivery-failures-v1"
    ) else { return [] }
    return (try? JSONDecoder().decode(
      [AgentAttachmentDeliveryFailureObservation].self,
      from: data
    )) ?? []
  }
}
