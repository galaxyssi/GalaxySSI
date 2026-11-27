import Darwin
import Foundation
import SQLite3
import UIKit

// Cache handles/programs/ciphertext pages only. Authentication still runs on every read.
final class AgentKnowledgePrimaryReadConnections {
  static let shared = AgentKnowledgePrimaryReadConnections()
  private struct Key: Hashable { let root: String; let file: String }
  private struct Stamp: Equatable { let rootDevice: UInt64; let rootInode: UInt64; let device: UInt64; let inode: UInt64 }
  private final class Reader {
    let handle: OpaquePointer
    let stamp: Stamp
    init(_ handle: OpaquePointer, _ stamp: Stamp) { self.handle = handle; self.stamp = stamp }
  }
  private let pool: AgentKnowledgeReadConnectionPool<Key, Reader>
  private let cleanup: DispatchQueue
  private let center: NotificationCenter
  private let trimLock = NSLock()
  private var trimming = false
  private var observers: [NSObjectProtocol] = []

  init(capacity: Int = 8, center: NotificationCenter = .default,
       cleanup: DispatchQueue = DispatchQueue(label: "galaxyssi.knowledge.readers.trim", qos: .utility)) {
    precondition((1...8).contains(capacity))
    pool = AgentKnowledgeReadConnectionPool(capacity: capacity) { AgentKnowledgeSQLiteStatements.shared.close($0.handle) }
    self.cleanup = cleanup; self.center = center
    for name in [UIApplication.didReceiveMemoryWarningNotification, .galaxySSIRuntimePlaintextWillClear] {
      observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.requestTrim() })
    }
  }
  deinit { for observer in observers { center.removeObserver(observer) }; pool.close() }
  struct Stats { let opened: Int64; let reused: Int64; let active: Int; let idle: Int; let peak: Int }
  var stats: Stats {
    let value = pool.stats
    return Stats(opened: value.opened, reused: value.reused, active: value.active, idle: value.idle, peak: value.peak)
  }

  func read<T>(root: URL, file: URL, directoryDescriptor: Int32, checkActive: () throws -> Void,
               open: () throws -> OpaquePointer, action: (OpaquePointer) throws -> T) throws -> T {
    let key = Key(root: root.path, file: file.path)
    let lease = try pool.borrow(key, checkActive: checkActive, valid: {
      $0.stamp == (try Self.stamp(root: root, file: file, descriptor: directoryDescriptor))
    }, create: {
      let before = try Self.stamp(root: root, file: file, descriptor: directoryDescriptor)
      let handle = try open()
      do {
        guard before == (try Self.stamp(root: root, file: file, descriptor: directoryDescriptor)) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        return Reader(handle, before)
      } catch { AgentKnowledgeSQLiteStatements.shared.close(handle); throw error }
    })
    defer { lease.end() }
    return try lease.access { try action($0.handle) }
  }
  func retire(root: URL, file: URL) throws {
    try pool.invalidate(where: { $0.root == root.path && $0.file == file.path }, requireIdle: true)
  }
  func clear(root: URL, requireIdle: Bool = false) throws {
    try pool.invalidate(where: { $0.root == root.path }, requireIdle: requireIdle)
  }
  func requestTrim() {
    trimLock.lock()
    guard !trimming else { trimLock.unlock(); return }
    trimming = true; trimLock.unlock()
    cleanup.async { [weak self] in
      guard let self else { return }
      try? self.pool.invalidate(where: { _ in true })
      self.trimLock.lock(); self.trimming = false; self.trimLock.unlock()
    }
  }

  private static func stamp(root: URL, file: URL, descriptor: Int32) throws -> Stamp {
    guard file.deletingLastPathComponent().path == root.path, descriptor >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    var anchored = stat(), current = stat(), main = stat()
    guard Darwin.fstat(descriptor, &anchored) == 0, Darwin.lstat(root.path, &current) == 0,
          (current.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
          current.st_dev == anchored.st_dev, current.st_ino == anchored.st_ino else { throw AgentKnowledgeDatabaseError.corruptRecord }
    for suffix in ["", "-wal", "-shm", "-journal"] {
      var info = stat()
      if Darwin.fstatat(descriptor, file.lastPathComponent + suffix, &info, AT_SYMLINK_NOFOLLOW) != 0 {
        if !suffix.isEmpty && errno == ENOENT { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if suffix.isEmpty { main = info }
    }
    return Stamp(rootDevice: UInt64(truncatingIfNeeded: anchored.st_dev), rootInode: UInt64(anchored.st_ino),
      device: UInt64(truncatingIfNeeded: main.st_dev), inode: UInt64(main.st_ino))
  }
}
