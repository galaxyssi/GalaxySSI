import CryptoKit
import Foundation
import UIKit
import UserNotifications

@MainActor
final class GalaxySSIHealthCareModelAttentionRuntime {
  typealias Attention = GalaxySSIHealthCareModelAttention
  static let shared = GalaxySSIHealthCareModelAttentionRuntime()
  private var running = false

  struct Context {
    let owner: String
    let contacts: [GalaxySSIContact]
    let links: [ServerLink]
    let language: String
    let secrets: GalaxySSISecretStore
    let blocked: Set<String>

    func permits(_ authorization: GalaxySSIHealthCareResearch.Authorization) -> Bool {
      let matches = contacts.filter { $0.id == authorization.contact && !$0.deleted }
      guard matches.count == 1, let contact = matches.first, !blocked.contains(contact.id) else { return false }
      if let route = authorization.pairedDesktop {
        return route.digest == authorization.destination && links.contains { route.accepts(contact: contact, link: $0) }
      }
      guard contact.deliveryMode == .cloudAPI, let model = contact.selectedCloudModel,
            model.modelId == authorization.model, let endpoint = authorization.endpoint,
            GalaxySSIHealthCareDiscussion.endpoint(for: model) == endpoint,
            let key = secrets.string(account: model.keychainAccount), CloudModelCredentialPolicy.isStoredCredential(key) else { return false }
      return GalaxySSIHealthCareDiscussion.destination(contactID: contact.id, model: model, endpoint: endpoint,
        credential: SHA256.hash(data: Data(key.utf8))) == authorization.destination
    }

    static func live(_ store: GalaxySSIStore, coordinator: MessageCoordinator, language: String) -> Self {
      .init(owner: store.profile.identityFingerprint, contacts: store.contacts, links: store.serverLinks, language: language,
        secrets: store.secrets, blocked: coordinator.healthDisclosureStore.blockedDestinationIds())
    }
    static func persisted() -> Self? {
      guard UIApplication.shared.isProtectedDataAvailable,
            let data = GalaxySSIEncryptedStateStore.load(defaults: .standard, secrets: KeychainSecretStore.shared),
            let config = try? JSONDecoder.galaxySSI.decode(Configuration.self, from: data) else { return nil }
      return .init(owner: config.profile.identityFingerprint, contacts: config.contacts,
        links: config.serverLinks.filter { $0.routes.isOpaqueV2Valid },
        language: LanguagePolicySettings.resolveInterface(config.languagePolicy?.interfaceLanguage ?? LanguagePolicySettings.auto),
        secrets: KeychainSecretStore.shared,
        blocked: FileAgentDataDisclosureStore(fileURL: AgentDataDisclosureStorePaths.ledgerURL()).blockedDestinationIds())
    }
    private struct Configuration: Decodable {
      let profile: GalaxySSIProfile
      let contacts: [GalaxySSIContact]
      let serverLinks: [ServerLink]
      let languagePolicy: LanguagePolicySettings?
    }
  }

  func reconcile(context: () -> Context?) async -> Date? {
    guard !running else { return Date().addingTimeInterval(1) }
    running = true
    defer { running = false }
    guard UIApplication.shared.isProtectedDataAvailable, let initial = context() else { return Date().addingTimeInterval(60) }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications().map(\.request)
    guard !Task.isCancelled, UIApplication.shared.isProtectedDataAvailable, context()?.owner == initial.owner else { return nil }
    let records = GalaxySSIHealthRecords(owner: initial.owner, secrets: initial.secrets)
    let ours = (pending + delivered).filter { $0.identifier.hasPrefix(Attention.prefix) }
    var visible: [String: UUID] = [:]
    for request in ours {
      if let raw = request.content.userInfo[Attention.turnKey] as? String, let turn = UUID(uuidString: raw) {
        visible[request.identifier] = turn
      } else { cancel(request.identifier, center: center) }
    }
    func current(_ value: Attention.Receipt) -> Bool {
      guard UIApplication.shared.isProtectedDataAvailable, let current = context(), current.owner == initial.owner,
            let review = try? records.load().localCareModelReviews?[value.turn] else { return false }
      return current.permits(review.authorization)
    }
    do {
      let next = try await GalaxySSIHealthCareModelAttentionDelivery.reconcile(records: records,
        systemAllowed: GalaxySSIHealthReviewDelivery.permitted(settings.authorizationStatus), visible: visible,
        now: Date(), calendar: .autoupdatingCurrent, clock: { Date() }, binding: current, foreground: {
          UIApplication.shared.applicationState == .active &&
            Attention.Visibility.shared.contains(owner: $0.owner, conversation: $0.conversation)
        }, post: { value in
          guard !Task.isCancelled, current(value), records.modelAttentionCurrent(value) else { return false }
          do {
            try await center.add(Self.request(value, language: initial.language))
            visible[value.identifier] = value.turn
            return true
          } catch { return false }
        }, cancel: { self.cancel($0, center: center); visible.removeValue(forKey: $0) })
      // Existing generic notices are withdrawn when quiet hours begin, without replaying at their end.
      let policy = try records.load().recordingReminders?.settings ?? .init()
      let now = Date()
      if policy.notifications, policy.allowsModelReviews, policy.quietStart != policy.quietEnd,
         policy.nextDelivery(now, calendar: .autoupdatingCurrent) == now,
         let notices = try records.load().localCareModelAttention,
         notices.values.contains(where: { visible[$0.identifier] == $0.turn && $0.state == .posted &&
           records.modelAttentionCurrent($0) && current($0) &&
           !Attention.Visibility.shared.contains(owner: $0.owner, conversation: $0.conversation) }),
         let quiet = Calendar.autoupdatingCurrent.nextDate(after: now,
           matching: DateComponents(hour: policy.quietStart, minute: 0), matchingPolicy: .nextTime) {
        return next.map { min($0, quiet) } ?? quiet
      }
      return next
    } catch {
      ours.forEach { cancel($0.identifier, center: center) }
      return Date().addingTimeInterval(60)
    }
  }

  func presentation(_ request: UNNotificationRequest) async -> UNNotificationPresentationOptions {
    guard let context = Context.persisted(),
          let raw = request.content.userInfo[Attention.turnKey] as? String, let turn = UUID(uuidString: raw) else { return [] }
    let records = GalaxySSIHealthRecords(owner: context.owner, secrets: context.secrets)
    guard let notice = try? records.modelAttentionTarget(identifier: request.identifier, turn: turn),
          !Attention.Visibility.shared.contains(owner: context.owner, conversation: notice.conversation),
          let review = try? records.load().localCareModelReviews?[notice.turn], context.permits(review.authorization),
          let settings = try? records.load().recordingReminders?.settings,
          settings.notifications, settings.allowsModelReviews, settings.nextDelivery(Date(), calendar: .autoupdatingCurrent) <= Date()
    else { return [] }
    return [.banner, .list]
  }

  static func request(_ value: Attention.Receipt, language: String) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = "GalaxySSI"
    content.body = GalaxySSILocalization.string("galaxyssi.health.model_attention.notice",
      fallback: "A Health review was updated. Open GalaxySSI to view it.", language: language)
    content.userInfo = [Attention.turnKey: value.turn.uuidString]
    return UNNotificationRequest(identifier: value.identifier, content: content, trigger: nil)
  }

  private func cancel(_ identifier: String, center: UNUserNotificationCenter) {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }
}
