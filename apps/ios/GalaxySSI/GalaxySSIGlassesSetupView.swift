import Network
import SwiftUI
import UIKit

@MainActor
struct GalaxySSIGlassesSetupView: View {
  typealias Wire = GalaxySSIGlassesSetupProtocol
  private enum Stage: Equatable { case idle, connecting, comparison(String), confirming, ready, sending, saved }
  private struct ModelChoice: Identifiable {
    let contact: GalaxySSIContact
    let model: CloudModelConfig
    var id: String { contact.id + ":" + model.id }
  }

  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var host = ""
  @State private var port = ""
  @State private var modelID = ""
  @State private var stage = Stage.idle
  @State private var failed = false
  @State private var connection: GalaxySSIGlassesSetupConnection?
  @State private var job: Task<Void, Never>?
  @State private var watchdog: Task<Void, Never>?
  @State private var generation = UUID()

  private var choices: [ModelChoice] {
    store.contacts.filter { !$0.deleted && $0.deliveryMode == .cloudAPI }.flatMap { contact in
      contact.cloudModels.filter(Wire.Profile.validEndpoint).filter {
        CloudModelCredentialPolicy.isStoredCredential(store.apiKey(for: $0))
      }.map { ModelChoice(contact: contact, model: $0) }
    }
  }
  private var selected: ModelChoice? { choices.first { $0.id == modelID } }
  private var active: Bool { scene == .active && UIApplication.shared.isProtectedDataAvailable }

  var body: some View {
    Form {
      switch stage {
      case .idle: connectSection
      case .connecting, .confirming, .sending: ProgressView()
      case .comparison(let code):
        Section(t("verification", "Verify pairing code")) {
          Text(code).font(.title.monospacedDigit().weight(.semibold))
          Text(t("compare", "Compare this code with the code on the glasses. Confirm on both devices only if they match."))
          Button(t("match", "The codes match"), action: confirm)
          Button(t("mismatch", "The codes differ"), role: .cancel) { reset() }
        }
      case .ready: modelSection
      case .saved:
        Label(t("saved", "The glasses saved the cloud model."), systemImage: "checkmark.circle")
        Button(t("another", "Configure another device")) { reset() }
      }
      if stage != .idle && stage != .saved { Button(t("cancel", "Cancel"), role: .cancel) { reset() } }
      if failed { Text(t("failed", "Setup could not be confirmed. Check Wi-Fi and start a new setup on the glasses.")) }
    }
    .navigationTitle(t("title", "Configure AR glasses"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarHidden(false)
    .onDisappear { reset() }
    .onChange(of: scene) { value in
      if value == .background || (value == .inactive && stage != .connecting) { reset() }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) {
      _ in reset()
    }
  }

  private var connectSection: some View {
    Section(t("manual", "Glasses on the same Wi-Fi")) {
      TextField(t("host", "IPv4 address shown on glasses"), text: $host)
        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
      TextField(t("port", "Port shown on glasses"), text: $port).keyboardType(.numberPad)
      Button(t("connect", "Connect")) {
        guard let endpoint = GalaxySSIGlassesSetupConnection.manualEndpoint(host: host, port: port) else { return }
        connect(endpoint)
      }.disabled(!active || GalaxySSIGlassesSetupConnection.manualEndpoint(host: host, port: port) == nil)
    }
  }

  private var modelSection: some View {
    Section(t("model", "Cloud Agent and model")) {
      if choices.isEmpty {
        Text(t("no_model", "No saved cloud model can be transferred.")).foregroundColor(.secondary)
      }
      Picker(t("model", "Cloud Agent and model"), selection: $modelID) {
        Text(t("select", "Select a saved model")).tag("")
        ForEach(choices) { option in Text(option.contact.name + " / " + option.model.modelId).tag(option.id) }
      }
      if let selected {
        Text(selected.model.endpoint).font(.footnote)
        Text(t("share", "Transfer this model's API key to the confirmed glasses. The phone configuration is unchanged."))
          .font(.footnote)
      }
      Button(t("transfer", "Transfer configuration"), action: transfer).disabled(selected == nil || !active)
    }
  }

  private func connect(_ endpoint: NWEndpoint) {
    guard active, stage == .idle, job == nil else { return }
    do {
      connection = try GalaxySSIGlassesSetupConnection(endpoint: endpoint)
      stage = .connecting
      perform(seconds: 20) { client in
        let code = try await client.connect()
        return .comparison(code)
      }
    } catch { reset(); failed = true }
  }

  private func confirm() {
    guard active, case .comparison = stage else { return }
    stage = .confirming
    perform(seconds: 55) { client in try await client.confirm(); return .ready }
  }

  private func transfer() {
    guard active, stage == .ready, let selected, let key = store.apiKey(for: selected.model) else { return }
    do {
      let profile = try Wire.Profile(agentName: selected.contact.name, model: selected.model, key: key)
      stage = .sending
      perform(seconds: 30) { client in try await client.transfer(profile); return .saved }
    } catch { reset(); failed = true }
  }

  private func perform(seconds: UInt64, operation: @escaping (GalaxySSIGlassesSetupConnection) async throws -> Stage) {
    guard let connection, job == nil else { return }
    let id = generation
    failed = false
    expire(seconds: seconds, id: id)
    job = Task {
      do {
        let next = try await operation(connection)
        guard generation == id, active, !Task.isCancelled else { return }
        watchdog?.cancel(); watchdog = nil; job = nil
        stage = next
        switch next {
        case .comparison: expire(seconds: 55, id: id)
        case .ready: expire(seconds: 240, id: id)
        case .saved: connection.close(); self.connection = nil; modelID = ""
        default: break
        }
      } catch {
        if generation == id { reset(); failed = true }
      }
    }
  }

  private func expire(seconds: UInt64, id: UUID) {
    watchdog?.cancel()
    watchdog = Task {
      do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
      if generation == id { reset(); failed = true }
    }
  }

  private func reset() {
    generation = UUID()
    job?.cancel(); job = nil; watchdog?.cancel(); watchdog = nil
    connection?.close(); connection = nil
    modelID = ""; stage = .idle; failed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.glasses_setup." + key, fallback: fallback, language: language)
  }
}
