import Foundation

enum GalaxySSIHealthOriginalExportSave {
  struct Receipt: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable { case pending, verified, unverified, interrupted }
    let id: UUID
    let at: Date
    var outcome: Outcome
  }

  struct Scope: Hashable, Sendable {
    let owner: String
    let directory: URL?
    let recordsFile: URL?
  }

  final class Request: Sendable {
    let scope: Scope
    let export: GalaxySSIHealthOriginalStore.ExportAttempt
    let token: UUID
    init(scope: Scope, export: GalaxySSIHealthOriginalStore.ExportAttempt, token: UUID) {
      self.scope = scope; self.export = export; self.token = token
    }
  }

  private final class WeakRequest {
    weak var value: Request?
    init(_ value: Request) { self.value = value }
  }

  @MainActor private static var active: [Scope: [UUID: WeakRequest]] = [:]

  @MainActor static func register(_ request: Request) {
    var entries = active[request.scope, default: [:]].filter { $0.value.value != nil }
    entries[request.token] = WeakRequest(request)
    active[request.scope] = entries
  }

  @MainActor static func isActive(_ token: UUID, scope: Scope) -> Bool {
    active[scope]?[token]?.value != nil
  }

  @MainActor static func release(_ request: Request) {
    active[request.scope]?[request.token] = nil
    if active[request.scope]?.isEmpty == true { active[request.scope] = nil }
  }

  static func sameExport(_ left: GalaxySSIHealthOriginalStore.ExportAttempt,
                         _ right: GalaxySSIHealthOriginalStore.ExportAttempt) -> Bool {
    left.id == right.id && left.at == right.at && left.originals == right.originals &&
      left.bytes == right.bytes && left.sha256 == right.sha256
  }
}
