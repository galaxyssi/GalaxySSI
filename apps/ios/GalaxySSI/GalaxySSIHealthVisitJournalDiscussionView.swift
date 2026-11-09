import CryptoKit
import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthVisitJournalDiscussionView: View {
  typealias Review = GalaxySSIHealthVisitJournalRead.Approval
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  let records: GalaxySSIHealthRecords
  let page: GalaxySSIHealthVisitJournal.Page

  @State private var question = ""
  @State private var selected = ""
  @State private var approval: Review?
  @State private var active: Review?
  @State private var response = ""
  @State private var task: Task<Void, Never>?
  @State private var failed = false
  @State private var online = false
  @State private var localProfiles: [LocalModelRuntimeProfile] = []

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  private var contacts: [GalaxySSIContact] {
    store.contacts.filter {
      !$0.deleted && $0.deliveryMode == .cloudAPI &&
        $0.selectedCloudModel.flatMap(GalaxySSIHealthCareDiscussion.endpoint(for:)) != nil &&
        !coordinator.healthDisclosureStore.blockedDestinationIds().contains($0.id)
    }
  }
  private var pairedRoutes: [GalaxySSIHealthDesktopResearch.Route] {
    store.contacts.flatMap { contact in
      guard coordinator.privateHealthDesktopRoute(contactID: contact.id) != nil else {
        return [GalaxySSIHealthDesktopResearch.Route]()
      }
      return contact.connectorInvocationProfile.models.compactMap {
        coordinator.privateHealthDesktopRoute(contactID: contact.id, modelID: $0.id)
      }
    }
  }

  var body: some View {
    NavigationView {
      Group {
        if canRead {
          Form {
            Toggle(t("online", "Allow approved online health questions"), isOn: Binding(
              get: { online }, set: { enabled in
                do { try records.setHealthOnlinePermission(enabled); refreshPermission() }
                catch { failed = true }
              }))
            Section {
              Picker(t("provider", "Provider and model"), selection: $selected) {
                Text(t("select_provider", "Select a model")).tag("")
                ForEach(localProfiles) { profile in
                  Text(t("on_device", "On this iPhone") + " / " + profile.displayName).tag("local:" + profile.id)
                }
                if online {
                  ForEach(contacts) { contact in
                    Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ?? "")).tag("cloud:" + contact.id)
                  }
                  ForEach(pairedRoutes, id: \.digest) { route in
                    Text(desktopName(route) + " / " + route.connector.modelId).tag("paired:" + route.digest)
                  }
                }
              }
              TextField(t("question", "Ask about this journal"), text: $question)
              Button(t("review", "Review sharing"), action: prepare).disabled(selected.isEmpty || question.isBlank)
            }.disabled(task != nil || approval != nil)
            if let approval { sharing(approval) }
            if task != nil { ProgressView() }
            if !response.isEmpty { Text(response).textSelection(.enabled) }
            if failed { Text(t("failed", "Discussion is unavailable. Check Health sharing permission, the selected model, or reopen the current journal.")) }
          }
        } else { Color.clear }
      }
      .navigationTitle(t("title", "Discuss post-visit journal"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(t("done", "Done")) { dismiss() } }
      }
    }
    .navigationViewStyle(.stack)
    .onAppear { refreshPermission(); refreshLocalProfiles() }
    .onChange(of: scene) { if $0 != .active { clear() } else { refreshPermission(); refreshLocalProfiles() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: store.contacts) { _ in
      if let review = active ?? approval {
        switch review.route {
        case .cloud: if cloudRoute(review) == nil { clear() }
        case .paired(let route): if !coordinator.isPrivateHealthDesktopRouteAvailable(route) { clear() }
        case .local: break
        }
      }
    }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { clear(); refreshPermission() }
    }
    .task(id: page.expires) {
      let remaining = max(0, min(GalaxySSIHealthVisitJournal.lifetime, page.expires.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
      if !Task.isCancelled { clear(); failed = true }
    }
  }

  private func sharing(_ review: Review) -> some View {
    Section(t("scope", "Shared this time")) {
      if let cloud = review.cloudApproval {
        Text(cloud.location)
        Text(cloud.modelID)
      } else if case .local(let profile, _) = review.route {
        Text(t("on_device", "On this iPhone"))
        Text(profile.displayName)
      } else if case .paired(let route) = review.route {
        Text(desktopName(route))
        Text(route.connector.modelId)
      }
      Text(review.summary.string("goal"))
      Text(review.summary.string("visit_purpose"))
      Text(review.question)
      if !review.previous.isEmpty {
        DisclosureGroup(t("previous", "Previous exchanges with this model")) {
          ForEach(review.previous) { exchange in
            Text(exchange.question).font(.headline)
            if let answer = exchange.answer { Text(answer) }
          }
        }
      }
      if review.route.requiresOnline {
        if case .paired = review.route {
          Text(t("paired_notice", "This paired Desktop and its selected model will receive the summary and any pages requested for this turn.")).font(.footnote)
        }
        Text(t("notice", "The selected model may read all entries in this journal for this request. It cannot read other Health records or change treatment, plans, or reminders.")).font(.footnote)
      } else {
        Text(t("local_notice", "The selected model can read this journal for this request. Journal data stays on this iPhone. No other Health records or changes are authorized.")).font(.footnote)
      }
      Button(t("send", "Approve and send")) { start(review) }.buttonStyle(.borderedProminent)
      Button(t("cancel", "Cancel")) { approval = nil }
    }
  }

  private func prepare() {
    guard canRead else { failed = true; return }
    do {
      if let profile = localProfiles.first(where: { "local:" + $0.id == selected }) {
        approval = try records.prepareVisitJournalDiscussion(page, question: question, localProfile: profile)
      } else if online, let route = pairedRoutes.first(where: { "paired:" + $0.digest == selected }) {
        approval = try records.prepareVisitJournalDiscussion(page, question: question, route: .paired(route), now: Date())
      } else if online, let contact = contacts.first(where: { "cloud:" + $0.id == selected }),
                let model = contact.selectedCloudModel, let key = store.apiKey(for: model) {
        approval = try records.prepareVisitJournalDiscussion(page, question: question, contact: contact, key: key)
      } else { failed = true; return }
      failed = false
    } catch { failed = true }
  }

  private func cloudRoute(_ review: Review) -> (GalaxySSIContact, String)? {
    guard canRead, online, let cloud = review.cloudApproval, let contact = contacts.first(where: { $0.id == cloud.destinationID }),
          let model = cloud.model, model == contact.selectedCloudModel,
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
          SHA256.hash(data: Data(key.utf8)) == cloud.credentialDigest else { return nil }
    return (contact, key)
  }

  private func start(_ review: Review) {
    guard canRead, task == nil, approval?.id == review.id else { failed = true; return }
    active = review; approval = nil; question = ""; response = ""; failed = false
    task = Task {
      defer { if active?.id == review.id { task = nil; active = nil } }
      do {
        let result: String
        switch review.route {
        case .cloud:
          result = try await GalaxySSIHealthVisitJournalDiscussionTransport.run(review, records: records,
            ledger: coordinator.healthDisclosureStore, currentRoute: {
              active?.id == review.id ? cloudRoute(review) : nil
            })
        case .paired:
          result = try await GalaxySSIHealthVisitJournalDiscussionTransport.runPaired(review, records: records,
            coordinator: coordinator, language: language, current: { canRead && online && active?.id == review.id })
        case .local:
          result = try await GalaxySSIHealthVisitJournalDiscussionTransport.runLocal(review, records: records,
            current: { profile, tokens in
              canRead && active?.id == review.id &&
                GalaxySSIHealthVisitJournalDiscussionTransport.localReady(profile, tokens: tokens)
            })
        }
        if active?.id == review.id, !Task.isCancelled { response = result }
      } catch {
        if active?.id == review.id, !Task.isCancelled { failed = true }
      }
    }
  }

  private func clear() {
    task?.cancel(); task = nil; active = nil; approval = nil; response = ""; question = ""; selected = ""; failed = false
  }
  private func refreshPermission() {
    online = canRead && ((try? records.load().healthOnlinePermission) != nil)
  }
  private func refreshLocalProfiles() {
    localProfiles = LocalModelRuntimeSettings.activeProfiles().filter {
      LocalModelInferenceRuntime.shared.ready(profile: $0)
    }
  }
  private func desktopName(_ route: GalaxySSIHealthDesktopResearch.Route) -> String {
    if let contact = store.contact(id: route.connector.contactId), !contact.desktopName.isBlank {
      return contact.desktopName
    }
    return route.connector.desktopId
  }
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.journal_discussion." + key, fallback: fallback, language: language)
  }
  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language: language) }
}
