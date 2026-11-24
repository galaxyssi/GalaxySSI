import Foundation
import SwiftUI
import UIKit

enum GalaxySSIHealthCareAgentScope {
  static let prefix = "health-care:"
  static func concernID(_ conversation: AgentConversation) -> UUID? {
    guard conversation.status == .active, conversation.privateMode, conversation.trackingPaused,
      conversation.collaborationRoster == nil, conversation.mergedIntoConversationId.isBlank,
      conversation.globalTopicKey.hasPrefix(prefix) else { return nil }
    let suffix = String(conversation.globalTopicKey.dropFirst(prefix.count))
    guard suffix.utf8.count == 36, let id = UUID(uuidString: suffix),
      id.uuidString.lowercased() == suffix.lowercased() else { return nil }
    return id
  }
  static func concern(_ conversation: AgentConversation, in archive: GalaxySSIHealthRecords.Archive) -> GalaxySSIHealthCare.Concern? {
    guard archive.localCareAllowed == true, let id = concernID(conversation),
      let thread = archive.localCareDiscussions?[id.uuidString], thread.concernID == id,
      thread.archivedAt == nil, thread.agentConversationID == conversation.id,
      let concern = archive.localCare?.current.values.first(where: { $0.id == id }) else { return nil }
    return concern
  }
  static func title(language: String) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: "health_care_agent_open", value: fallback, table: "HealthIndependentAgent")
    }
    let english = value("en", fallback: "Open Health Agent")
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
}

extension GalaxySSIStore {
  // Creating/reusing a binding is local only. The caller chooses when to navigate.
  func openHealthCareAgent(records: GalaxySSIHealthRecords, concern: UUID, metric: GalaxySSIHealthMetric,
                           language: String) throws -> String {
    guard UIApplication.shared.isProtectedDataAvailable, profile.identityFingerprint == records.owner else {
      throw GalaxySSIHealthRecords.Failure.permission
    }
    let thread = try records.openLocalCareDiscussion(id: concern, metric: metric)
    if let id = thread.agentConversationID, let session = agentConversationDatabase.read(id),
      GalaxySSIHealthCareAgentScope.concernID(session) == concern,
      GalaxySSIHealthCareAgentScope.concern(session, in: try records.load()) != nil { return id }
    let title = GalaxySSIHealthCareAgentScope.title(language: language) + " \u{00b7} " + metric.title(language: language)
    let session = createAgentConversation(title: title,
      globalTopicKey: GalaxySSIHealthCareAgentScope.prefix + concern.uuidString.lowercased(), privateMode: true)
    do {
      guard setAgentSessionTrackingPaused(id: session.id, paused: true),
        let persisted = agentConversationDatabase.read(session.id),
        GalaxySSIHealthCareAgentScope.concernID(persisted) == concern else { throw GalaxySSIHealthRecords.Failure.unavailable }
      try records.bindLocalCareAgentDiscussion(id: concern, metric: metric, threadID: thread.id,
        expectedConversationID: thread.agentConversationID, conversationID: session.id)
      return session.id
    } catch {
      _ = deleteAgentSession(id: session.id)
      throw error
    }
  }
}

@MainActor
struct GalaxySSIHealthCareAgentOpenButton: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  @State private var destination: String?
  @State private var failed = false
  var body: some View {
    Button {
      do {
        guard scene == .active else { return }
        let id = try store.openHealthCareAgent(records: records, concern: concern, metric: metric, language: language)
        guard store.switchAgentSession(id) else { throw GalaxySSIHealthRecords.Failure.unavailable }
        destination = id
      } catch { failed = true }
    } label: {
      Label(GalaxySSIHealthCareAgentScope.title(language: language), systemImage: "bubble.left.and.bubble.right")
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    .accessibilityIdentifier("health-care-discuss")
    .background(NavigationLink(isActive: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
      if destination == store.activeAgentConversationId, scene == .active,
        store.profile.identityFingerprint == records.owner { AnyView(AgentHomeView()) }
    } label: { EmptyView() }.hidden())
    .alert(GalaxySSIHealthCareText.string("unavailable", "Local health review could not be loaded.", language: language), isPresented: $failed) {
      Button(GalaxySSILocalization.string("galaxyssi.ok", fallback: "OK", language: language)) { failed = false }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in destination = nil }
  }
}
