import SwiftUI

@MainActor
struct GalaxySSIPinnedDesktopTeamView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let launch: AgentConversationalTeamLaunch
  let valid: () -> Bool
  let applied: () -> Void
  @State private var review: AgentPinnedDesktopTeam.Review?
  @State private var failed = false
  @State private var submitting = false
  private var objective: String {
    if case .start(let value) = launch.command { return value }
    return ""
  }
  private var available: Bool {
    valid() && scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      launch.source == nil && launch.owner == store.profile.identityFingerprint &&
      launch.selection == AgentModelSelectionSettings.selection(for: launch.conversation, defaults: store.defaults) &&
      AgentConversationGoalRuntime.eligible(store.agentSession(id: launch.conversation)) &&
      store.agentSession(id: launch.conversation)?.parentConversationId.isBlank == true &&
      AgentTaskExecutionModePolicy.resolve(request: objective,
        configuredMode: store.agentSafetySettings.taskExecutionMode).mode == .autoComplete &&
      AgentPinnedDesktopTeam.eligibleObjective(objective, language: language)
  }
  private func route() -> AgentPinnedDesktopTeam.Route? {
    guard available else { return nil }
    return AgentPinnedDesktopTeam.inspect(store: store, conversation: launch.conversation,
      blocked: coordinator.healthDisclosureStore.blockedDestinationIds())
  }
  var body: some View {
    NavigationView {
      List {
        if let review {
          Section(t("destination", "Confirmed Desktop")) {
            Text(verbatim: review.route.name)
            Text(verbatim: review.route.model)
            Text(verbatim: review.route.effort.rawValue).foregroundColor(.secondary)
          }
          Section(t("objective", "Full objective")) { Text(verbatim: objective).textSelection(.enabled) }
          Section {
            Text(t("consent", "Create a separate research group with two roles on this Desktop and model. Only this objective and the group's results are shared. No previous chat history or phone screen context is included. Desktop tools may run under your existing permissions; model charges may apply."))
            Button(action: start) { Label(t("authorize", "Create research group"), systemImage: "play") }
              .disabled(submitting || !available)
          }
        } else {
          Text(t("unavailable", "The selected Desktop must be paired, online, and advertise pinned team support with this exact model and reasoning effort. Update Desktop or reselect the model; no other route will be used."))
        }
        if failed { Text(t("changed", "The input or Desktop binding changed, or the group could not be saved. Your original conversation was not sent. Reopen this panel.")) }
      }
      .navigationTitle(t("title", "Desktop research group"))
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } } }
    }.navigationViewStyle(.stack).privacySensitive()
    .onAppear { if let current = route() { review = .init(launch: launch.id, route: current) } }
    .onChange(of: scene) { if $0 != .active { review = nil; dismiss() } }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in review = nil; dismiss() }
    .onDisappear { review = nil }
  }
  private func start() {
    guard !submitting, available, let review, review.claim(launch: launch.id, current: route()),
      let hermes = store.contact(id: "hermes"),
      let group = store.createPinnedDesktopTeam(objective: objective, route: review.route,
        source: launch.conversation, owner: launch.owner) else { failed = true; return }
    submitting = true
    let turn = group.collaborationRoster?.pinnedDesktop?.turn
    applied()
    guard store.switchAgentSession(group.id), let turn else { failed = true; submitting = false; return }
    dismiss()
    Task { @MainActor in
      _ = await coordinator.send(objective, to: hermes, requiredAgentConversationID: group.id, pinnedDesktopTeamTurn: turn)
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.pinned_desktop_team." + key, fallback: fallback, language: language)
  }
}
