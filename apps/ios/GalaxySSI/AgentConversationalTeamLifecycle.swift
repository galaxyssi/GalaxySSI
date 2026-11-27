import SwiftUI

@MainActor
struct AgentConversationalTeamLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIStore
  func body(content: Content) -> some View {
    content.onAppear { update() }
      .onChange(of: scene) { _ in update() }
      .onReceive(store.objectWillChange) { _ in
        Task { @MainActor in await Task.yield(); update() }
      }
      .onReceive(NotificationCenter.default.publisher(for: AgentConversationalTeamStore.changed)) { _ in
        AgentConversationalTeamRuntime.shared.wake()
      }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in
        AgentConversationalTeamRuntime.shared.interrupt()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
        AgentConversationalTeamRuntime.shared.interrupt()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in update() }
  }
  private func update() { AgentConversationalTeamRuntime.shared.setForeground(scene == .active, store: store) }
}
