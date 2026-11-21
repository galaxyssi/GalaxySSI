import CoreMotion
import SwiftUI
import UIKit

@MainActor
final class GalaxySSIHealthMotionController: ObservableObject {
  static let shared = GalaxySSIHealthMotionController()
  enum Status: String { case off, active, waiting, requesting, denied, restricted, unsupported, failed }
  enum Feature: String, CaseIterable { case steps, cycling }
  @Published private(set) var state: GalaxySSIHealthMotion.State?
  @Published private(set) var stepStatus = Status.off
  @Published private(set) var cyclingStatus = Status.off
  private var records: GalaxySSIHealthRecords?
  private var generation = UUID()
  private var pending: Feature?
  private let pedometer = CMPedometer()
  private let activities = CMMotionActivityManager()
  private var day: Date?

  func matches(_ value: GalaxySSIHealthRecords) -> Bool {
    records?.owner == value.owner && records?.isolatedFile == value.isolatedFile
  }
  func attach(_ value: GalaxySSIHealthRecords) {
    if !matches(value) {
      suspend()
      // Account changes revoke the old account's sensor opt-in, not just its visible data.
      if let previous = records {
        for feature in Feature.allCases { UserDefaults.standard.set(true, forKey: revocationKey(feature, previous)) }
        let stopped = try? previous.updateMotion {
          $0.enableSteps(false, now: Date(), calendar: .autoupdatingCurrent)
          $0.enableCycling(false, now: Date(), calendar: .autoupdatingCurrent)
        }
        if stopped != nil { for feature in Feature.allCases { UserDefaults.standard.removeObject(forKey: revocationKey(feature, previous)) } }
      }
      records = value; state = nil
      if value.isolatedFile == nil {
        let key = "galaxyssi.health.motion.last-owner"
        let owner = AgentModelLoopRecoveryIdentity.sha256(value.owner)
        if UserDefaults.standard.string(forKey: key) != owner {
          do {
            let saved = try value.loadMotion()
            if saved.stepsEnabled != nil || saved.cyclingEnabled != nil {
              try value.updateMotion {
                $0.enableSteps(false, now: Date(), calendar: .autoupdatingCurrent)
                $0.enableCycling(false, now: Date(), calendar: .autoupdatingCurrent)
              }
            }
            UserDefaults.standard.set(owner, forKey: key)
          } catch { stepStatus = .failed; cyclingStatus = .failed; return }
        }
      }
    }
    refresh()
  }
  func suspend() {
    generation = UUID(); pending = nil
    pedometer.stopUpdates(); activities.stopActivityUpdates()
    state = nil; stepStatus = .off; cyclingStatus = .off
  }
  func refreshDay() {
    if day != Calendar.autoupdatingCurrent.startOfDay(for: Date()) { refresh() }
  }
  func refresh() {
    guard pending == nil, let records, UIApplication.shared.isProtectedDataAvailable else { return }
    pedometer.stopUpdates(); activities.stopActivityUpdates(); generation = UUID()
    let token = generation, now = Date(), calendar = Calendar.autoupdatingCurrent
    do {
      var saved = try records.loadMotion()
      let revoked = Feature.allCases.filter { UserDefaults.standard.bool(forKey: revocationKey($0, records)) }
      if !revoked.isEmpty {
        saved = try records.updateMotion {
          if revoked.contains(.steps) { $0.enableSteps(false, now: now, calendar: calendar) }
          if revoked.contains(.cycling) { $0.enableCycling(false, now: now, calendar: calendar) }
        }
        for feature in revoked { UserDefaults.standard.removeObject(forKey: revocationKey(feature, records)) }
      }
      if saved.stepsEnabled != nil && CMPedometer.authorizationStatus() != .authorized ||
          saved.cyclingEnabled != nil && CMMotionActivityManager.authorizationStatus() != .authorized {
        let denied = Feature.allCases.filter {
          $0 == .steps ? saved.stepsEnabled != nil && CMPedometer.authorizationStatus() != .authorized :
            saved.cyclingEnabled != nil && CMMotionActivityManager.authorizationStatus() != .authorized
        }
        for feature in denied { UserDefaults.standard.set(true, forKey: revocationKey(feature, records)) }
        saved = try records.updateMotion {
          if CMPedometer.authorizationStatus() != .authorized { $0.enableSteps(false, now: now, calendar: calendar) }
          if CMMotionActivityManager.authorizationStatus() != .authorized { $0.enableCycling(false, now: now, calendar: calendar) }
        }
        for feature in denied { UserDefaults.standard.removeObject(forKey: revocationKey(feature, records)) }
      }
      if saved.stepsEnabled != nil || saved.cyclingEnabled != nil {
        saved = try records.updateMotion { $0.prepare(now: now, uptime: ProcessInfo.processInfo.systemUptime, calendar: calendar) }
      }
      state = saved; day = calendar.startOfDay(for: now)
      stepStatus = status(CMPedometer.authorizationStatus(), supported: CMPedometer.isStepCountingAvailable(), enabled: saved.stepsEnabled != nil)
      cyclingStatus = status(CMMotionActivityManager.authorizationStatus(), supported: CMMotionActivityManager.isActivityAvailable(), enabled: saved.cyclingEnabled != nil)
      if stepStatus == .active, let step = saved.steps, let start = step.start {
        startSteps(from: start, segment: step.segment, token: token)
      }
      if cyclingStatus == .active, let enabled = saved.cyclingEnabled {
        startCycling(saved.cycling, enabled: enabled, now: now, token: token)
      } else if saved.cycling.started != nil {
        state = try records.updateMotion { $0.cycling.started = nil }
      }
    } catch { state = nil; stepStatus = .failed; cyclingStatus = .failed }
  }
  func setGoal(_ goal: Int?, for value: GalaxySSIHealthRecords) throws {
    guard matches(value) else { throw GalaxySSIHealthRecords.Failure.stale }
    state = try value.updateMotion { $0.goal = goal }
  }
  func setEnabled(_ feature: Feature, enabled: Bool, for value: GalaxySSIHealthRecords) {
    guard matches(value), let records, pending == nil else { return }
    if !enabled {
      // Persist an opt-out marker even if protected health-file storage is unavailable.
      UserDefaults.standard.set(true, forKey: revocationKey(feature, records))
      generation = UUID(); pedometer.stopUpdates(); activities.stopActivityUpdates()
    }
    let supported = feature == .steps ? CMPedometer.isStepCountingAvailable() : CMMotionActivityManager.isActivityAvailable()
    let authorization = feature == .steps ? CMPedometer.authorizationStatus() : CMMotionActivityManager.authorizationStatus()
    if enabled, !supported { setStatus(.unsupported, feature: feature); return }
    if enabled, authorization == .denied || authorization == .restricted {
      setStatus(authorization == .denied ? .denied : .restricted, feature: feature); return
    }
    if enabled, authorization == .notDetermined {
      pending = feature; setStatus(.requesting, feature: feature)
      let token = generation, now = Date()
      if feature == .steps {
        pedometer.queryPedometerData(from: now.addingTimeInterval(-1), to: now) { [weak self] _, _ in
          Task { @MainActor in self?.finishPermission(feature, token: token, owner: value) }
        }
      } else {
        activities.queryActivityStarting(from: now.addingTimeInterval(-1), to: now, to: .main) { [weak self] _, _ in
          Task { @MainActor in self?.finishPermission(feature, token: token, owner: value) }
        }
      }
      return
    }
    do {
      let now = Date(), calendar = Calendar.autoupdatingCurrent
      state = try records.updateMotion {
        $0.prepare(now: now, uptime: ProcessInfo.processInfo.systemUptime, calendar: calendar)
        if feature == .steps { $0.enableSteps(enabled, now: now, calendar: calendar) }
        else { $0.enableCycling(enabled, now: now, calendar: calendar) }
      }
      UserDefaults.standard.removeObject(forKey: revocationKey(feature, records))
      refresh()
    } catch {
      if !enabled {
        if feature == .steps { state?.enableSteps(false, now: Date(), calendar: .autoupdatingCurrent) }
        else { state?.enableCycling(false, now: Date(), calendar: .autoupdatingCurrent) }
        stepStatus = .failed; cyclingStatus = .failed
      }
      setStatus(.failed, feature: feature)
    }
  }
  private func revocationKey(_ feature: Feature, _ records: GalaxySSIHealthRecords) -> String {
    "galaxyssi.health.motion.revoke." + AgentModelLoopRecoveryIdentity.sha256(records.owner + (records.isolatedFile?.absoluteString ?? "")) + "." + feature.rawValue
  }
  private func finishPermission(_ feature: Feature, token: UUID, owner: GalaxySSIHealthRecords) {
    guard generation == token, pending == feature, matches(owner) else { return }
    pending = nil
    let authorization = feature == .steps ? CMPedometer.authorizationStatus() : CMMotionActivityManager.authorizationStatus()
    if authorization == .authorized { setEnabled(feature, enabled: true, for: owner) }
    else { setStatus(authorization == .restricted ? .restricted : .denied, feature: feature) }
  }
  private func status(_ access: CMAuthorizationStatus, supported: Bool, enabled: Bool) -> Status {
    guard supported else { return .unsupported }
    if access == .denied { return .denied }
    if access == .restricted { return .restricted }
    return enabled && access == .authorized ? .active : .off
  }
  private func setStatus(_ status: Status, feature: Feature) {
    if feature == .steps { stepStatus = status } else { cyclingStatus = status }
  }
  private func startSteps(from: Date, segment: UUID, token: UUID) {
    let receive: CMPedometerHandler = { [weak self] data, error in
      Task { @MainActor in
        guard let self, self.generation == token, let records = self.records else { return }
        guard CMPedometer.authorizationStatus() == .authorized else {
          self.setEnabled(.steps, enabled: false, for: records)
          self.stepStatus = CMPedometer.authorizationStatus() == .restricted ? .restricted : .denied
          return
        }
        guard error == nil, let data, data.endDate >= from, data.startDate <= data.endDate else {
          self.stepStatus = Self.emptyHistory(error) ? .waiting : .failed; return
        }
        do {
          self.state = try records.updateMotion {
            guard $0.stepsEnabled != nil, $0.steps?.segment == segment else { return }
            $0.steps?.observe(data.numberOfSteps.intValue, from: from, through: data.endDate, now: Date(), calendar: .autoupdatingCurrent)
          }
          self.stepStatus = self.state?.stepsEnabled == nil ? .off : .active
        } catch { self.stepStatus = .failed }
      }
    }
    pedometer.queryPedometerData(from: from, to: Date(), withHandler: receive)
    pedometer.startUpdates(from: from, withHandler: receive)
  }
  private func startCycling(_ ledger: GalaxySSIHealthMotion.Cycling, enabled: Date, now: Date, token: UUID) {
    let floor = now.addingTimeInterval(-7 * 86_400)
    let from = max(enabled, max(ledger.cursor ?? enabled, floor)), epoch = ledger.epoch
    activities.queryActivityStarting(from: from, to: now, to: .main) { [weak self] data, error in
      Task { @MainActor in
        guard let self, self.generation == token, let records = self.records else { return }
        guard CMMotionActivityManager.authorizationStatus() == .authorized else {
          self.setEnabled(.cycling, enabled: false, for: records)
          self.cyclingStatus = CMMotionActivityManager.authorizationStatus() == .restricted ? .restricted : .denied
          return
        }
        do {
          self.state = try records.updateMotion {
            guard $0.cyclingEnabled != nil, $0.cycling.epoch == epoch else { return }
            if (ledger.cursor ?? enabled) < floor || error != nil || data?.isEmpty != false || (data?.count ?? 0) > 10_000 {
              $0.cycling.started = nil
            }
            if error == nil, let data, data.count <= 10_000 {
              for activity in data.sorted(by: { $0.startDate < $1.startDate }) {
                let event = GalaxySSIHealthMotion.Cycling.Event(at: max(activity.startDate, from), kind: Self.kind(activity))
                $0.cycling.observe(event, now: now, calendar: .autoupdatingCurrent)
              }
              $0.cycling.cursor = now
            }
          }
          if (data?.count ?? 0) > 10_000 { self.cyclingStatus = .failed }
          else if Self.emptyHistory(error) || error == nil && data?.isEmpty != false { self.cyclingStatus = .waiting }
          else { self.cyclingStatus = error == nil ? .active : .failed }
          self.activities.startActivityUpdates(to: .main) { [weak self] activity in
            Task { @MainActor in
              guard let self, self.generation == token, let records = self.records else { return }
              guard CMMotionActivityManager.authorizationStatus() == .authorized else {
                self.setEnabled(.cycling, enabled: false, for: records)
                self.cyclingStatus = CMMotionActivityManager.authorizationStatus() == .restricted ? .restricted : .denied
                return
              }
              guard let activity else {
                self.state = try? records.updateMotion { $0.cycling.started = nil }
                self.cyclingStatus = .failed; return
              }
              do {
                self.state = try records.updateMotion {
                  guard $0.cyclingEnabled != nil, $0.cycling.epoch == epoch else { return }
                  $0.cycling.observe(.init(at: max(activity.startDate, now), kind: Self.kind(activity)), now: Date(), calendar: .autoupdatingCurrent)
                }
                self.cyclingStatus = self.state?.cyclingEnabled == nil ? .off : (Self.kind(activity) == .uncertain ? .waiting : .active)
              } catch { self.cyclingStatus = .failed }
            }
          }
        } catch { self.cyclingStatus = .failed }
      }
    }
  }
  private static func kind(_ activity: CMMotionActivity) -> GalaxySSIHealthMotion.Cycling.Kind {
    guard activity.confidence == .medium || activity.confidence == .high else { return .uncertain }
    if activity.cycling && !activity.automotive && !activity.walking && !activity.running && !activity.unknown { return .cycling }
    if !activity.unknown && (activity.stationary || activity.walking || activity.running || activity.automotive) { return .inactive }
    return .uncertain
  }
  private static func emptyHistory(_ error: Error?) -> Bool {
    guard let error = error as NSError? else { return false }
    return error.domain == CMErrorDomain && error.code == Int(CMErrorUnknown.rawValue)
  }
}

@MainActor
struct GalaxySSIHealthMotionLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @ObservedObject var store: GalaxySSIStore
  private let motion = GalaxySSIHealthMotionController.shared
  func body(content: Content) -> some View {
    content
      .onAppear { if scene == .active { attach() } }
      .onChange(of: scene) { if $0 == .active { attach() } else if $0 == .background { motion.suspend() } }
      .onChange(of: store.profile.identityFingerprint) { _ in if scene == .active { attach() } else { motion.suspend() } }
      .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in if scene == .active { motion.refreshDay() } }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in if scene == .active { attach() } }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in motion.suspend() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in if scene == .active { attach() } }
  }
  private func attach() { motion.attach(.init(owner: store.profile.identityFingerprint, secrets: store.secrets)) }
}
