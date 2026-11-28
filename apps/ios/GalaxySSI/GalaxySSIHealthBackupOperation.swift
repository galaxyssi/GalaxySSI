import Foundation

enum GalaxySSIHealthBackupOperation {
  enum Kind: Hashable, Sendable { case generation, save }
  struct Scope: Hashable, Sendable {
    let owner: String
    let directory: URL?
  }
  final class Request: Sendable {
    let scope: Scope
    let kind: Kind
    let entry: GalaxySSIHealthBackupHistory.Entry
    let token: UUID
    init(scope: Scope, kind: Kind, entry: GalaxySSIHealthBackupHistory.Entry, token: UUID) {
      self.scope = scope; self.kind = kind; self.entry = entry; self.token = token
    }
  }
  private struct Key: Hashable { let kind: Kind; let token: UUID }
  private final class WeakRequest {
    weak var value: Request?
    init(_ value: Request) { self.value = value }
  }
  @MainActor private static var active: [Scope: [Key: WeakRequest]] = [:]

  @MainActor static func register(_ request: Request) {
    var entries = active[request.scope, default: [:]].filter { $0.value.value != nil }
    entries[Key(kind: request.kind, token: request.token)] = WeakRequest(request)
    active[request.scope] = entries
  }
  @MainActor static func owns(_ request: Request) -> Bool {
    active[request.scope]?[Key(kind: request.kind, token: request.token)]?.value === request
  }
  @MainActor static func isActive(_ token: UUID?, kind: Kind, entry: UUID, scope: Scope) -> Bool {
    guard let token, let request = active[scope]?[Key(kind: kind, token: token)]?.value else { return false }
    return request.entry.id == entry
  }
  @MainActor static func release(_ request: Request) {
    guard owns(request) else { return }
    active[request.scope]?[Key(kind: request.kind, token: request.token)] = nil
    if active[request.scope]?.isEmpty == true { active[request.scope] = nil }
  }

  static func sameBackup(_ left: GalaxySSIHealthBackupHistory.Entry, _ right: GalaxySSIHealthBackupHistory.Entry) -> Bool {
    left.id == right.id && left.at == right.at && left.generation == .ready && right.generation == .ready &&
      left.generationToken == right.generationToken && left.bytes == right.bytes && left.sha256 == right.sha256
  }
}
