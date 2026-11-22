import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GalaxySSIHealthCareModelAttentionVisibility: ViewModifier {
  let owner: String
  let concern: UUID
  let conversation: UUID?
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @State private var token = UUID()

  func body(content: Content) -> some View {
    content.onAppear(perform: update).onDisappear(perform: clear)
      .onChange(of: scene) { _ in update() }
      .onChange(of: conversation) { _ in update() }
      .onChange(of: store.profile.identityFingerprint) { _ in update() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in update() }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
  }
  private func update() {
    let scope: GalaxySSIHealthCareModelAttention.VisibleScope?
    if scene == .active, UIApplication.shared.isProtectedDataAvailable,
       store.profile.identityFingerprint == owner, let conversation {
      scope = .init(owner: owner, concern: concern, conversation: conversation)
    } else { scope = nil }
    GalaxySSIHealthCareModelAttention.Visibility.shared.update(token, scope: scope)
  }
  private func clear() { GalaxySSIHealthCareModelAttention.Visibility.shared.update(token, scope: nil) }
}

@MainActor
struct GalaxySSIHealthCareModelAttentionLifecycle: ViewModifier {
  typealias Attention = GalaxySSIHealthCareModelAttention
  @ObservedObject var store: GalaxySSIStore
  let coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var generation = UUID()
  @State private var wakeAt: Date?
  @State private var destination: Destination?

  private struct Destination: Identifiable {
    let id: String
    let owner: String
    let concern: UUID
    let metric: GalaxySSIHealthMetric
  }

  func body(content: Content) -> some View {
    content
      .onAppear(perform: wake)
      .onChange(of: scene) { if $0 != .active { destination = nil }; wake() }
      .onChange(of: store.profile.identityFingerprint) { _ in destination = nil; wake() }
      .onChange(of: store.contacts) { _ in wake() }
      .onChange(of: store.serverLinks) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: Attention.openNotification)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: Attention.visibilityChanged)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: AgentDataDisclosureLedger.policyChanged)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecordingReminders.changed)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
        destination = nil; wakeAt = nil; generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in destination = nil }
      .task(id: generation) {
        let next = await GalaxySSIHealthCareModelAttentionRuntime.shared.reconcile(context: currentContext)
        guard !Task.isCancelled else { return }
        wakeAt = next
        GalaxySSIHealthCareModelAttentionBackground.schedule(next)
        openPending()
      }
      .task(id: wakeAt) {
        guard scene == .active, let wakeAt else { return }
        let delay = min(86_400, max(1, wakeAt.timeIntervalSinceNow))
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
        if !Task.isCancelled { wake() }
      }
      .sheet(item: $destination) { value in
        NavigationView {
          GalaxySSIHealthCareDiscussionView(records: .init(owner: value.owner, secrets: store.secrets),
            concernID: value.concern, metric: value.metric)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
              Button(GalaxySSILocalization.string("galaxyssi.common.close", fallback: "Close", language: language)) { destination = nil }
            } }
        }.navigationViewStyle(.stack).environmentObject(store).environmentObject(coordinator)
      }
  }
  private func wake() { generation = UUID() }
  private func currentContext() -> GalaxySSIHealthCareModelAttentionRuntime.Context? {
    guard UIApplication.shared.isProtectedDataAvailable else { return nil }
    if scene == .active { return .live(store, coordinator: coordinator, language: language) }
    return .persisted()
  }
  private func openPending() {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable,
          let context = currentContext(), let raw = UserDefaults.standard.string(forKey: Attention.pendingKey) else { return }
    UserDefaults.standard.removeObject(forKey: Attention.pendingKey)
    let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
    guard parts.count == 2, let turn = UUID(uuidString: String(parts[1])) else { return }
    let records = GalaxySSIHealthRecords(owner: context.owner, secrets: context.secrets)
    guard let value = try? records.modelAttentionTarget(identifier: String(parts[0]), turn: turn),
          let review = try? records.load().localCareModelReviews?[value.turn], context.permits(review.authorization),
          let settings = try? records.load().recordingReminders?.settings, settings.notifications, settings.allowsModelReviews else { return }
    destination = .init(id: value.identifier, owner: context.owner, concern: value.concern, metric: review.authorization.metric)
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [value.identifier])
  }
}
