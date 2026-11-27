import Foundation

extension MessageCoordinator {
  func fileReceiptKey(_ file: AgentPreparedOutboundAttachment) -> AgentTurnReceiptStore.Key? {
    store.fileReceiptKey(file)
  }

  func fileReceiptBinding(_ file: AgentPreparedOutboundAttachment) -> String? {
    guard let link = store.serverLinks.first(where: { $0.paired && $0.desktopId == file.scope.desktopId &&
      $0.routes.clientRouteId == file.scope.clientRouteId }) else { return nil }
    return GalaxySSITransportReceiptJournal.binding(peerId: link.desktopId, routes: link.routes)
  }

  func fileReceiptIsBound(_ file: AgentPreparedOutboundAttachment) -> Bool {
    guard let key = fileReceiptKey(file), let binding = fileReceiptBinding(file),
      let receipt = store.turnReceiptStore.read(key)?.files?[AgentTurnReceiptEvidence.hash(file.attachmentId)] else { return false }
    return receipt.transfer == file.transferId && receipt.peer == binding && receipt.wire != .closed && receipt.wire != .stored
  }

  @discardableResult
  func updateFileReceipt(_ file: AgentPreparedOutboundAttachment, state: AgentFileReceipt.Wire) -> Bool {
    guard let key = fileReceiptKey(file), let binding = fileReceiptBinding(file) else { return false }
    return store.turnReceiptStore.changeFile(key, item: file.attachmentId) {
      $0.fold(transfer: file.transferId, state: state, fingerprint: binding, generation: file.fileRetryGeneration)
    }
  }

  func queuedFileReceipts(_ files: [AgentPreparedOutboundAttachment]) {
    for file in files { updateFileReceipt(file, state: .uploading) }
  }
}

extension GalaxySSIStore {
  func fileReceiptKey(_ file: AgentPreparedOutboundAttachment) -> AgentTurnReceiptStore.Key? {
    guard let id = file.scope.clientMessageId.flatMap(UUID.init(uuidString:)),
      let original = persistedMessage(id: id, contactId: "hermes"),
      original.conversationId == file.scope.conversationId, original.turnId == file.scope.turnId,
      AgentFileReceipt.originals(original).count >= 2,
      AgentFileReceipt.originals(original).contains(where: { $0.id == file.attachmentId }) else { return nil }
    return turnReceiptKey(conversation: original.conversationId, turn: original.turnId)
  }
}
