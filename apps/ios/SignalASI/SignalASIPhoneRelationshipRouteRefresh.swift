import Foundation

enum SignalASIPhoneRelationshipRouteRefresh {
  static func apply(
    existing: SignalASIContact,
    remoteCard: [String: Any],
    routes: SignalASILinkRoutes,
    now: Date = Date()
  ) -> SignalASIContact? {
    let remoteId = remoteCard.string("signalasi_id")
    let remoteFingerprint = remoteCard.string("identity_fingerprint")
    let existingMatchesRemote = existing.id == remoteId || existing.signalASIId == remoteId
    guard !remoteId.isEmpty,
          existingMatchesRemote,
          !existing.deleted,
          existing.trustState == .verified,
          !existing.identityFingerprint.isEmpty,
          existing.identityFingerprint.caseInsensitiveCompare(remoteFingerprint) == .orderedSame,
          routes.isOpaqueV2Valid,
          routes.remoteFingerprint.caseInsensitiveCompare(remoteFingerprint) == .orderedSame,
          routes.localFingerprint.caseInsensitiveCompare(remoteFingerprint) != .orderedSame else {
      return nil
    }

    var refreshed = existing
    refreshed.linkClientRouteId = routes.clientRouteId
    refreshed.linkSecret = routes.linkSecret
    refreshed.linkLocalFingerprint = routes.localFingerprint
    refreshed.identityFingerprint = routes.remoteFingerprint
    refreshed.deleted = false
    refreshed.updatedAt = now
    return refreshed
  }
}
