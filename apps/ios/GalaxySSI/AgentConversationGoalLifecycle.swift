import SwiftUI

@MainActor
struct AgentConversationGoalLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  let store: GalaxySSIStore
  func body(content: Content) -> some View {
    content.onAppear { update() }
      .onChange(of: scene) { _ in update() }
      .onReceive(store.objectWillChange) { _ in
        Task { @MainActor in await Task.yield(); update() }
      }
      .onReceive(NotificationCenter.default.publisher(for: AgentConversationGoalStore.changed)) { _ in
        AgentConversationGoalRuntime.shared.wake()
      }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in
        AgentConversationGoalRuntime.shared.interrupt()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
        AgentConversationGoalRuntime.shared.interrupt()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in update() }
  }
  @MainActor private func update() { AgentConversationGoalRuntime.shared.setForeground(scene == .active, store: store) }
}
