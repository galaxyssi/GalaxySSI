import SwiftUI
import UIKit

@MainActor
struct GalaxySSIDoorAccessView: View {
  typealias Config = AgentDoorAccessConfiguration
  struct Launch: Identifiable {
    let id = UUID()
    let owner: String
    let conversation: String?
    let configuration: Config
    let command: Config.Command
    let automatic: Bool
  }
  struct Choice: Identifiable {
    let id = UUID()
    let target: Config.Target
    let door: AgentDoorAccessClient.Door
    let expires: TimeInterval
  }
  enum Status { case unavailable, noMatch, accepted, rejected, unconfirmed }

  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let launch: Launch

  @State private var account = ""
  @State private var password = ""
  @State private var hasSaved = false
  @State private var needsPhysicalCheck = false
  @State private var selection: Choice?
  @State private var confirming = false
  @State private var session: AgentDoorAccessClient.Session?
  @State private var doors: [AgentDoorAccessClient.Door] = []
  @State private var pendingTarget: String?
  @State private var status: Status?
  @State private var job: Task<Void, Never>?
  @State private var generation = UUID()
  private let client = AgentDoorAccessClient()

  private var current: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable &&
      store.profile.identityFingerprint == launch.owner &&
      (launch.conversation == nil || launch.conversation == store.activeAgentConversationId) &&
      Config.enabled(automatic: launch.automatic) == launch.configuration
  }
  private var credentialKey: String { "door-access-v1:" + launch.owner }
  private var uncertainKey: String { "door-access-uncertain-v1:" + launch.owner }

  var body: some View {
    NavigationView {
      Group {
        if current {
          Form {
            if session == nil {
              if hasSaved {
                Button(t("list", "Load doors")) { useSaved() }.disabled(job != nil)
                Button(t("forget", "Forget saved sign-in"), role: .destructive) {
                  store.secrets.delete(account: credentialKey); hasSaved = false
                }.disabled(job != nil)
              } else {
                TextField(t("account", "Door service account"), text: $account)
                  .textInputAutocapitalization(.never).disableAutocorrection(true).textContentType(.username)
                SecureField(t("password", "Password"), text: $password).textContentType(.password)
                Button(t("sign_in", "Sign in")) {
                  let credentials = AgentDoorAccessClient.Credentials(account: account, password: password)
                  account = ""; password = ""
                  load(credentials, save: true)
                }.disabled(job != nil || account.isBlank || password.isEmpty)
              }
            } else {
              ForEach(launch.configuration.targets) { target in
                if let door = AgentDoorAccessClient.uniqueDoor(target, in: doors) {
                  Button { review(target, door: door) } label: {
                    Label(target.display_name, systemImage: "lock")
                  }.disabled(job != nil || needsPhysicalCheck)
                }
              }
            }
            if job != nil { ProgressView() }
            if needsPhysicalCheck, job == nil {
              Text(statusText(.unconfirmed))
              Button(t("checked", "I checked the door")) {
                store.secrets.delete(account: uncertainKey)
                needsPhysicalCheck = store.secrets.string(account: uncertainKey) != nil
                if !needsPhysicalCheck { status = nil }
              }
            }
            if let status { Text(statusText(status)) }
          }
        } else { Color.clear }
      }
      .navigationTitle(t("title", "Door access"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("done", "Done")) { dismiss() } } }
      .confirmationDialog(t("confirm", "Send an unlock request?"), isPresented: $confirming,
        titleVisibility: .visible, presenting: selection) { choice in
        Button(t("unlock", "Send unlock request"), role: .destructive) { open(choice) }
        Button(t("cancel", "Cancel"), role: .cancel) { selection = nil }
      } message: { choice in Text(choice.target.display_name) }
    }
    .navigationViewStyle(.stack)
    .onAppear {
      if case .open(let id) = launch.command { pendingTarget = id }
      if current { needsPhysicalCheck = store.secrets.string(account: uncertainKey) != nil }
      hasSaved = saved() != nil
      if hasSaved { useSaved() }
    }
    .onChange(of: scene) { if $0 != .active { clear(); dismiss() } }
    .onChange(of: store.activeAgentConversationId) { _ in if launch.conversation != nil { clear(); dismiss() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear(); dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) {
      _ in clear(); dismiss()
    }
    .onDisappear { clear() }
  }

  private func saved() -> AgentDoorAccessClient.Credentials? {
    guard current, !launch.owner.isEmpty, let value = store.secrets.string(account: credentialKey) else { return nil }
    return try? JSONDecoder().decode(AgentDoorAccessClient.Credentials.self, from: Data(value.utf8))
  }

  private func useSaved() {
    guard let value = saved() else { hasSaved = false; return }
    load(value, save: false)
  }

  private func load(_ credentials: AgentDoorAccessClient.Credentials, save: Bool) {
    guard current, !launch.owner.isEmpty, job == nil else { return }
    let id = generation
    status = nil
    job = Task {
      defer { if id == generation { job = nil } }
      do {
        let authenticated = try await client.login(credentials)
        guard current, id == generation, !Task.isCancelled else { return }
        let listed = try await client.list(authenticated)
        guard current, id == generation, !Task.isCancelled else { return }
        if save {
          let value = String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
          try store.secrets.setString(value, account: credentialKey)
          hasSaved = true
        }
        session = authenticated
        doors = listed
        if let requested = pendingTarget {
          pendingTarget = nil
          guard let target = launch.configuration.targets.first(where: { $0.id == requested }),
                let door = AgentDoorAccessClient.uniqueDoor(target, in: listed) else { status = .noMatch; return }
          review(target, door: door)
        } else if !launch.configuration.targets.contains(where: { AgentDoorAccessClient.uniqueDoor($0, in: listed) != nil }) {
          status = .noMatch
        }
      } catch { if id == generation, !Task.isCancelled { status = .unavailable } }
    }
  }

  private func review(_ target: Config.Target, door: AgentDoorAccessClient.Door) {
    guard current, !needsPhysicalCheck, let session, !session.token.isEmpty else { return }
    selection = .init(target: target, door: door, expires: ProcessInfo.processInfo.systemUptime + 30)
    confirming = true
  }

  private func open(_ choice: Choice) {
    guard selection?.id == choice.id else { return }
    selection = nil
    guard current, job == nil, !needsPhysicalCheck, let session, ProcessInfo.processInfo.systemUptime < choice.expires,
          AgentDoorAccessClient.uniqueDoor(choice.target, in: doors) == choice.door else {
      status = .unavailable; return
    }
    guard store.secrets.string(account: uncertainKey) == nil else { needsPhysicalCheck = true; return }
    do { try store.secrets.setString("1", account: uncertainKey) }
    catch { status = .unavailable; return }
    needsPhysicalCheck = true
    let id = generation
    self.session = nil
    doors = []
    job = Task {
      defer { if id == generation { job = nil } }
      guard current, id == generation, !Task.isCancelled else { return }
      let result = await client.open(session, door: choice.door,
        millis: Int64(Date().timeIntervalSince1970 * 1_000))
      guard current, id == generation, !Task.isCancelled else { return }
      switch result {
      case .accepted, .rejected:
        store.secrets.delete(account: uncertainKey)
        needsPhysicalCheck = store.secrets.string(account: uncertainKey) != nil
        if case .accepted = result { status = .accepted } else { status = .rejected }
      case .unconfirmed: status = nil
      }
    }
  }

  private func clear() {
    generation = UUID()
    job?.cancel(); job = nil; session = nil; selection = nil; pendingTarget = nil
    confirming = false
    doors = []; account = ""; password = ""; hasSaved = false; needsPhysicalCheck = false; status = nil
  }
  private func statusText(_ status: Status) -> String {
    switch status {
    case .unavailable: return t("unavailable", "Door access is unavailable. Check the Skill, sign-in, or connection.")
    case .noMatch: return t("no_match", "No unique matching door was found.")
    case .accepted: return t("accepted", "The service accepted the request. The door position is not confirmed.")
    case .rejected: return t("rejected", "The service rejected the request.")
    case .unconfirmed: return t("unconfirmed", "The request may have been delivered. Check the door before sending another request.")
    }
  }
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.door_access." + key, fallback: fallback, language: language)
  }
  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language: language) }
}
