import CryptoKit
import Darwin
import Foundation
import Network

/// Runs the UTM SE QEMU library inside the app process. The TCI build does not require JIT.
final class AgentIOSQemuRuntimeController {
  static let shared = AgentIOSQemuRuntimeController()

  private static let linuxPackID = "linux-base"
  private static let linuxPackVersion = "1.3.9"
  private static let nodePackID = "node-js"
  private static let nodePackVersion = "24.18.0"
  private static let nodePackCapabilities = ["javascript.execute", "typescript.execute"]

  private typealias QemuInit = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
  private typealias QemuMainLoop = @convention(c) () -> Void
  private typealias QemuCleanup = @convention(c) () -> Void

  private let fileManager: FileManager
  private let queue = DispatchQueue(label: "com.galaxyssi.ios.qemu-tci", qos: .userInitiated)
  private let stateLock = NSLock()
  private var phase = Phase.stopped
  private var detail = ""

  private enum Phase: String {
    case stopped
    case starting
    case running
    case failed
  }

  private init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func availability() -> AgentNativeToolAvailability {
    guard qemuFrameworkURL != nil else {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Install the full offline IPA to include the no-JIT iOS Linux runtime."
      )
    }
    guard bundledKernelURL != nil else {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "The embedded GalaxySSI Linux 1.3.9 kernel image is unavailable."
      )
    }
    guard bundledNodePackURL != nil, bundledNodePackConfigURL != nil else {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "The embedded Node.js 24.18.0 runtime pack is unavailable."
      )
    }
    stateLock.lock()
    defer { stateLock.unlock() }
    if phase == .failed {
      return AgentNativeToolAvailability(status: .unavailable, reason: detail.ifBlank("The iOS Linux runtime failed."))
    }
    return .available
  }

  func embeddedPackStatus(packID: String) -> AgentRuntimePackStatus? {
    switch packID {
    case Self.linuxPackID:
      guard bundledKernelURL != nil else { return nil }
      return AgentRuntimePackStatus(
        id: packID,
        state: .ready,
        reason: "Embedded GalaxySSI Linux \(Self.linuxPackVersion)"
      )
    case Self.nodePackID:
      guard bundledNodePackURL != nil, bundledNodePackConfigURL != nil else { return nil }
      return AgentRuntimePackStatus(
        id: packID,
        state: .ready,
        reason: "Embedded Node.js \(Self.nodePackVersion)"
      )
    default:
      return nil
    }
  }

  func usesInstalledNodePack(version: String) -> Bool {
    version.compare(Self.nodePackVersion, options: .numeric) != .orderedAscending
  }

  func socketPath(runtimeRootURL: URL) throws -> String {
    let directory = fileManager.temporaryDirectory.appendingPathComponent("sa-runtime", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("agent.sock", isDirectory: false).path
    guard path.utf8.count <= 100 else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux socket path is too long.")
    }
    return path
  }

  func startIfNeeded(runtimeRootURL: URL, sessionKey: Data) throws {
    guard sessionKey.count >= AgentIOSRuntimeBrokerPairingKey.byteCount else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux runtime session key is invalid.")
    }
    guard let frameworkURL = qemuFrameworkURL,
          let bundledKernelURL,
          let bundledNodePackURL,
          let bundledNodePackConfigURL else {
      throw AgentIOSRuntimeBrokerError.disabled
    }
    stateLock.lock()
    if phase == .running || phase == .starting {
      stateLock.unlock()
      return
    }
    if phase == .failed {
      let error = detail
      stateLock.unlock()
      throw AgentIOSRuntimeBrokerError.transport(error.ifBlank("The iOS Linux runtime cannot be restarted in this app session."))
    }
    phase = .starting
    detail = ""
    stateLock.unlock()

    do {
      let files = try provision(
        runtimeRootURL: runtimeRootURL,
        bundledKernelURL: bundledKernelURL,
        bundledNodePackURL: bundledNodePackURL,
        bundledNodePackConfigURL: bundledNodePackConfigURL,
        sessionKey: sessionKey
      )
      let arguments = launchArguments(files: files)
      queue.async { [weak self] in
        self?.runQemu(frameworkURL: frameworkURL, arguments: arguments)
      }
    } catch {
      stateLock.lock()
      phase = .failed
      detail = error.localizedDescription
      stateLock.unlock()
      throw error
    }
  }

  private var qemuFrameworkURL: URL? {
    guard let url = Bundle.main.privateFrameworksURL?
      .appendingPathComponent("qemu-aarch64-softmmu.framework", isDirectory: true),
      fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  private var bundledKernelURL: URL? {
    guard let url = Bundle.main.url(
      forResource: "linux-base-1.3.9-aarch64",
      withExtension: "Image",
      subdirectory: "runtime-bootstrap"
    ), fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  private var bundledNodePackURL: URL? {
    guard let url = Bundle.main.url(
      forResource: "node-js-\(Self.nodePackVersion)-arm64-v8a",
      withExtension: "img",
      subdirectory: "runtime-bootstrap"
    ), fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  private var bundledNodePackConfigURL: URL? {
    guard let url = Bundle.main.url(
      forResource: "node-js-\(Self.nodePackVersion)-arm64-v8a.img.config",
      withExtension: "json",
      subdirectory: "runtime-bootstrap"
    ), fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  private struct RuntimePackAttachment {
    var id: String
    var version: String
    var capabilities: [String]
    var image: URL
    var serial: String
  }

  private struct RuntimeFiles {
    var kernel: URL
    var disk: URL
    var packAttachments: [RuntimePackAttachment]
    var workspace: URL
    var socket: URL
    var session: URL
    var configuration: URL
  }

  private func provision(
    runtimeRootURL: URL,
    bundledKernelURL: URL,
    bundledNodePackURL: URL,
    bundledNodePackConfigURL: URL,
    sessionKey: Data
  ) throws -> RuntimeFiles {
    let runtime = runtimeRootURL.appendingPathComponent("qemu", isDirectory: true)
    let system = runtime.appendingPathComponent("system", isDirectory: true)
    let packs = runtime.appendingPathComponent("packs", isDirectory: true)
    let workspace = runtimeRootURL.appendingPathComponent("projects", isDirectory: true)
    try fileManager.createDirectory(at: system, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: packs, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)

    let kernel = runtime.appendingPathComponent("linux-base-1.3.9-aarch64.Image", isDirectory: false)
    if !fileManager.fileExists(atPath: kernel.path) {
      try fileManager.copyItem(at: bundledKernelURL, to: kernel)
    }
    let nodePack = packs.appendingPathComponent(
      "node-js-\(Self.nodePackVersion)-arm64-v8a.img",
      isDirectory: false
    )
    let expectedNodePackSHA256 = try validateBundledNodePack(
      imageURL: bundledNodePackURL,
      configURL: bundledNodePackConfigURL
    )
    if fileManager.fileExists(atPath: nodePack.path),
       try sha256(nodePack) != expectedNodePackSHA256 {
      try fileManager.removeItem(at: nodePack)
    }
    if !fileManager.fileExists(atPath: nodePack.path) {
      try fileManager.copyItem(at: bundledNodePackURL, to: nodePack)
    }
    let embeddedNodeAttachment = RuntimePackAttachment(
      id: Self.nodePackID,
      version: Self.nodePackVersion,
      capabilities: Self.nodePackCapabilities,
      image: nodePack,
      serial: packSerial(Self.nodePackID)
    )
    let installedAttachments = installedPackAttachments(runtimeRootURL: runtimeRootURL)
    let installedNodeAttachment = installedAttachments.first {
      $0.id == Self.nodePackID && usesInstalledNodePack(version: $0.version)
    }
    let nodeAttachment = installedNodeAttachment ?? embeddedNodeAttachment
    let packAttachments = ([nodeAttachment] + installedAttachments.filter { $0.id != Self.nodePackID })
      .sorted { $0.id < $1.id }
    let disk = system.appendingPathComponent("galaxyssi-system.raw", isDirectory: false)
    if !fileManager.fileExists(atPath: disk.path) {
      fileManager.createFile(atPath: disk.path, contents: nil)
      let handle = try FileHandle(forWritingTo: disk)
      try handle.truncate(atOffset: 30 * 1024 * 1024 * 1024)
      try handle.synchronize()
      try handle.close()
    }
    let socket = URL(fileURLWithPath: try socketPath(runtimeRootURL: runtimeRootURL))
    try? fileManager.removeItem(at: socket)
    let session = runtime.appendingPathComponent("guest-session.key", isDirectory: false)
    try sessionKey.write(to: session, options: .atomic)
    let configuration = runtime.appendingPathComponent("guest-config.json", isDirectory: false)
    let packConfiguration = packAttachments.enumerated().map { index, pack -> [String: Any] in
      [
        "id": pack.id,
        "version": pack.version,
        "capabilities": pack.capabilities.sorted(),
        "serial": pack.serial,
        "read_only": true,
        "device_index": index
      ]
    }
    let values: [String: Any] = [
      "format_version": 1,
      "guest_api_version": 1,
      "host_epoch_millis": Int64(Date().timeIntervalSince1970 * 1_000),
      "architecture": "aarch64",
      "api_channel": "org.galaxyssi.runtime",
      "workspace_mount_tag": "galaxyssi_workspaces",
      "workspace_uid": 1000,
      "workspace_gid": 1000,
      "execution_mode": "full_access",
      "execution_principal": "root",
      "network_mode": "host_mediated",
      "dns_servers": ["1.1.1.1", "223.5.5.5", "8.8.8.8"],
      "system_disk": [
        "serial": "sa-system",
        "filesystem": "ext4",
        "mount_path": "/var/lib/galaxyssi",
        "logical_bytes": 30 * 1024 * 1024 * 1024
      ],
      "packs": packConfiguration
    ]
    try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]).write(to: configuration, options: .atomic)
    try ([kernel, disk, workspace, socket, session, configuration] + packAttachments.map(\.image))
      .forEach(validateQemuPath)
    return RuntimeFiles(
      kernel: kernel,
      disk: disk,
      packAttachments: packAttachments,
      workspace: workspace,
      socket: socket,
      session: session,
      configuration: configuration
    )
  }

  private func installedPackAttachments(runtimeRootURL: URL) -> [RuntimePackAttachment] {
    let installer = AgentIOSRuntimePackInstaller(runtimeRootURL: runtimeRootURL, fileManager: fileManager)
    let packsRoot = runtimeRootURL.appendingPathComponent("packs", isDirectory: true)
    return AgentRuntimePackCatalogPolicy.requiredPacks.compactMap { packID in
      guard packID != Self.linuxPackID,
            let manifest = installer.installedManifest(packId: packID) else {
        return nil
      }
      let image = packsRoot
        .appendingPathComponent(packID, isDirectory: true)
        .appendingPathComponent(manifest.imageFile, isDirectory: false)
      guard fileManager.isReadableFile(atPath: image.path) else { return nil }
      return RuntimePackAttachment(
        id: manifest.id,
        version: manifest.version,
        capabilities: manifest.capabilities,
        image: image,
        serial: packSerial(manifest.id)
      )
    }
  }

  private func validateBundledNodePack(imageURL: URL, configURL: URL) throws -> String {
    let data = try Data(contentsOf: configURL, options: [.mappedIfSafe])
    guard data.count <= 64 * 1_024,
          let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          config["id"] as? String == Self.nodePackID,
          config["version"] as? String == Self.nodePackVersion,
          config["architecture"] as? String == "arm64-v8a",
          config["image_file"] as? String == imageURL.lastPathComponent,
          Set(config["capabilities"] as? [String] ?? []) == Set(Self.nodePackCapabilities),
          Set(config["dependencies"] as? [String] ?? []) == Set(["linux-base"]),
          let expectedSHA256 = config["image_sha256"] as? String,
          expectedSHA256.count == 64,
          expectedSHA256.allSatisfy({ $0.isHexDigit }),
          try sha256(imageURL) == expectedSHA256.lowercased() else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration(
        "The embedded Node.js 24.18.0 runtime pack failed manifest verification."
      )
    }
    return expectedSHA256.lowercased()
  }

  private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func launchArguments(files: RuntimeFiles) -> [String] {
    let device = AgentDeviceProfileDetector.detect()
    var arguments = [
      "qemu-system-aarch64",
      "-name", "GalaxySSI Linux",
      "-machine", "virt,gic-version=3,highmem=off",
      "-accel", "tcg,thread=multi",
      "-cpu", "max",
      "-smp", String(device.maxQemuCpuCount),
      "-m", "\(device.maxQemuMemoryMegabytes)M",
      "-display", "none",
      "-nodefaults",
      "-no-user-config",
      "-no-reboot",
      "-monitor", "none",
      "-serial", "null",
      "-netdev", "user,id=galaxyssi_net,restrict=off,ipv6=off",
      "-device", "virtio-net-device,netdev=galaxyssi_net",
      "-kernel", files.kernel.path,
      "-append", "console=ttyAMA0,115200 panic=1 quiet loglevel=3 galaxyssi.runtime=1",
      "-chardev", "socket,id=galaxyssi_api,path=\(files.socket.path),server=on,wait=on",
      "-device", "virtio-serial-device",
      "-device", "virtserialport,chardev=galaxyssi_api,name=org.galaxyssi.runtime",
      "-fsdev", "local,id=galaxyssi_workspaces,path=\(files.workspace.path),security_model=none,multidevs=remap",
      "-device", "virtio-9p-device,fsdev=galaxyssi_workspaces,mount_tag=galaxyssi_workspaces",
      "-fw_cfg", "name=opt/com.galaxyssi/runtime-session,file=\(files.session.path)",
      "-fw_cfg", "name=opt/com.galaxyssi/runtime-config,file=\(files.configuration.path)",
      "-object", "rng-random,id=galaxyssi_rng,filename=/dev/urandom",
      "-device", "virtio-rng-device,rng=galaxyssi_rng",
      "-drive", "if=none,id=galaxyssi_system,file=\(files.disk.path),format=raw,cache=none,aio=threads",
      "-device", "virtio-blk-device,drive=galaxyssi_system,serial=sa-system"
    ]
    for (index, pack) in files.packAttachments.enumerated() {
      let driveID = "galaxyssi_pack_\(index)"
      arguments.append(contentsOf: [
        "-drive", "if=none,id=\(driveID),file=\(pack.image.path),format=raw,readonly=on,cache=none,aio=threads",
        "-device", "virtio-blk-device,drive=\(driveID),serial=\(pack.serial)"
      ])
    }
    return arguments
  }

  private func packSerial(_ packID: String) -> String {
    let allowed = "abcdefghijklmnopqrstuvwxyz0123456789._-"
    let normalized = ("sa-" + packID.lowercased()).map { character in
      allowed.contains(character) ? character : "-"
    }
    return String(normalized.prefix(20))
  }

  private func validateQemuPath(_ url: URL) throws {
    let path = url.path
    guard !path.isEmpty,
          !path.contains(","),
          !path.contains("\n"),
          !path.contains("\r") else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration(
        "A runtime file path cannot be represented safely in the QEMU launch configuration."
      )
    }
  }

  private func runQemu(frameworkURL: URL, arguments: [String]) {
    let executable = frameworkURL.appendingPathComponent("qemu-aarch64-softmmu", isDirectory: false).path
    guard let library = dlopen(executable, RTLD_NOW | RTLD_GLOBAL),
          let initSymbol = dlsym(library, "qemu_init"),
          let mainLoopSymbol = dlsym(library, "qemu_main_loop"),
          let cleanupSymbol = dlsym(library, "qemu_cleanup") else {
      fail("The embedded UTM SE QEMU framework could not be loaded.")
      return
    }
    let qemuInit = unsafeBitCast(initSymbol, to: QemuInit.self)
    let qemuMainLoop = unsafeBitCast(mainLoopSymbol, to: QemuMainLoop.self)
    let qemuCleanup = unsafeBitCast(cleanupSymbol, to: QemuCleanup.self)
    let emptyEnvironment: [UnsafePointer<CChar>?] = [nil]
    let result = arguments.withCStringPointers { pointers in
      emptyEnvironment.withUnsafeBufferPointer { environment in
        qemuInit(Int32(arguments.count), pointers, environment.baseAddress)
      }
    }
    guard result == 0 else {
      fail("The embedded QEMU runtime rejected its launch configuration (\(result)).")
      return
    }
    stateLock.lock()
    phase = .running
    stateLock.unlock()
    qemuMainLoop()
    qemuCleanup()
    fail("The iOS Linux runtime stopped.")
  }

  private func fail(_ message: String) {
    stateLock.lock()
    phase = .failed
    detail = message
    stateLock.unlock()
  }
}

private extension Array where Element == String {
  func withCStringPointers<T>(_ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> T) -> T {
    let storage = map { value -> UnsafeMutablePointer<CChar> in
      guard let pointer = strdup(value) else { fatalError("Unable to allocate QEMU arguments") }
      return pointer
    }
    defer { storage.forEach { free($0) } }
    let pointers = storage.map { UnsafePointer($0) } + [nil]
    return pointers.withUnsafeBufferPointer { body($0.baseAddress) }
  }
}

final class AgentIOSUnixRuntimeBrokerTransport: AgentIOSRuntimeBrokerTransport {
  private let socketPath: () throws -> String

  init(socketPath: @escaping () throws -> String) {
    self.socketPath = socketPath
  }

  func exchange(frame: Data, host: String, port: UInt16, timeoutMillis: Int64) throws -> Data {
    guard frame.count <= AgentIOSRuntimeBrokerClient.maximumFrameBytes else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux request is too large.")
    }
    let connection = NWConnection(to: .unix(path: try socketPath()), using: .tcp)
    let queue = DispatchQueue(label: "com.galaxyssi.ios.qemu-socket", qos: .userInitiated)
    connection.start(queue: queue)
    defer { connection.cancel() }
    let timeout = DispatchTime.now() + .milliseconds(Int(min(30_000, max(250, timeoutMillis))))
    try send(framePrefix(frame) + frame, through: connection, timeout: timeout)
    let header = try receive(exactly: 4, through: connection, timeout: timeout)
    let length = header.reduce(0) { ($0 << 8) | Int($1) }
    guard (1...AgentIOSRuntimeBrokerClient.maximumFrameBytes).contains(length) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return try receive(exactly: length, through: connection, timeout: timeout)
  }

  private func send(_ data: Data, through connection: NWConnection, timeout: DispatchTime) throws {
    let signal = DispatchSemaphore(value: 0)
    var failure: Error?
    connection.send(content: data, completion: .contentProcessed { error in
      failure = error
      signal.signal()
    })
    guard signal.wait(timeout: timeout) == .success else { throw AgentIOSRuntimeBrokerError.timeout }
    if let failure { throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription) }
  }

  private func receive(exactly length: Int, through connection: NWConnection, timeout: DispatchTime) throws -> Data {
    let signal = DispatchSemaphore(value: 0)
    var received: Data?
    var failure: NWError?
    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
      received = data
      failure = error
      signal.signal()
    }
    guard signal.wait(timeout: timeout) == .success else { throw AgentIOSRuntimeBrokerError.timeout }
    if let failure { throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription) }
    guard let received, received.count == length else { throw AgentIOSRuntimeBrokerError.malformedResponse }
    return received
  }

  private func framePrefix(_ frame: Data) -> Data {
    let length = UInt32(frame.count).bigEndian
    return withUnsafeBytes(of: length) { Data($0) }
  }
}

/// Implements the signed guest protocol shared with the Android QEMU runtime.
private final class AgentIOSQemuGuestClient {
  private static let protocolVersion: Int64 = 1
  private static let maximumFrameBytes = 1_048_576

  private let socketPath: String
  private let sessionKey: Data
  private let nowMillis: () -> Int64

  init(socketPath: String, sessionKey: Data, nowMillis: @escaping () -> Int64 = {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }) {
    self.socketPath = socketPath
    self.sessionKey = sessionKey
    self.nowMillis = nowMillis
  }

  func status(deadlineEpochMillis: Int64) throws -> AgentMcpJSONObject {
    let connection = try openConnection()
    defer { connection.cancel() }
    let hello = try handshake(connection: connection, deadlineEpochMillis: deadlineEpochMillis)
    let ready = hello["ready"]?.boolValue ?? false
    let reason = hello["reason"]?.stringValue ?? ""
    return [
      "backend": .string("ios_app_sandbox_qemu_tci"),
      "backend_ready": .bool(ready),
      "reason": .string(reason),
      "architecture": .string("arm64"),
      "execution_target": .string("ios_qemu_debian"),
      "linux_base_version": .string("1.3.9"),
      "linux_system": .object([
        "distribution": .string("Debian 13"),
        "execution_principal": .string(hello["execution_principal"]?.stringValue ?? "root"),
        "persistent": .bool(true),
        "package_managers": .array([.string("apt")]),
        "package_manager_ready": .bool(ready),
        "base_version": .string("1.3.9"),
        "package_management": .string("Linux guest package manager")
      ]),
      "capabilities": hello["capabilities"] ?? .array([]),
      "observed_at_epoch_ms": .int(max(0, nowMillis()))
    ]
  }

  func execute(
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    workspacePath: String,
    deadlineEpochMillis: Int64
  ) throws -> AgentMcpJSONObject {
    let connection = try openConnection()
    defer { connection.cancel() }
    let hello = try handshake(connection: connection, deadlineEpochMillis: deadlineEpochMillis)
    guard hello["ready"]?.boolValue == true else {
      throw AgentIOSRuntimeBrokerError.remote(
        code: "runtime_guest_not_ready",
        message: hello["reason"]?.stringValue?.ifBlank("The embedded Debian guest is not ready.") ?? "The embedded Debian guest is not ready.",
        retryable: true
      )
    }
    let requestId = "execute-\(UUID().uuidString)"
    let payload = try executePayload(input: input, context: context, workspacePath: workspacePath)
    try send(
      envelope(requestId: requestId, type: "execute", sequence: 1, payload: payload),
      through: connection,
      timeout: timeout(deadlineEpochMillis: deadlineEpochMillis, maximum: 30 * 60_000)
    )
    var sequence: Int64 = 0
    let deadline = timeout(deadlineEpochMillis: deadlineEpochMillis, maximum: 30 * 60_000)
    while true {
      let response = try receive(through: connection, timeout: deadline)
      try verify(response)
      guard response["request_id"]?.stringValue == requestId else { continue }
      let currentSequence = response["sequence"]?.intValue ?? 0
      guard currentSequence > sequence else { throw AgentIOSRuntimeBrokerError.malformedResponse }
      sequence = currentSequence
      let type = response["type"]?.stringValue ?? ""
      let responsePayload = response["payload"]?.objectValue ?? [:]
      switch type {
      case "progress":
        continue
      case "result":
        return responsePayload.merging([
          "message": .string("iOS embedded Debian execution completed"),
          "workspace_id": .string(workspaceId(context)),
          "backend": .string("ios_app_sandbox_qemu_tci")
        ]) { current, _ in current }
      case "cancelled":
        throw AgentIOSRuntimeBrokerError.remote(
          code: "runtime_execution_cancelled",
          message: "The embedded Debian execution was cancelled.",
          retryable: true
        )
      case "error":
        throw AgentIOSRuntimeBrokerError.remote(
          code: "runtime_guest_execution_failed",
          message: responsePayload["message"]?.stringValue?.ifBlank("The embedded Debian guest failed.") ?? "The embedded Debian guest failed.",
          retryable: false
        )
      default:
        throw AgentIOSRuntimeBrokerError.malformedResponse
      }
    }
  }

  private func handshake(connection: NWConnection, deadlineEpochMillis: Int64) throws -> AgentMcpJSONObject {
    let requestId = "connect-\(UUID().uuidString)"
    try send(
      envelope(
        requestId: requestId,
        type: "hello",
        sequence: 1,
        payload: [
          "host_api_version": .int(Self.protocolVersion),
          "nonce": .string(UUID().uuidString)
        ]
      ),
      through: connection,
      timeout: timeout(deadlineEpochMillis: deadlineEpochMillis, maximum: 15_000)
    )
    let response = try receive(
      through: connection,
      timeout: timeout(deadlineEpochMillis: deadlineEpochMillis, maximum: 15_000)
    )
    try verify(response)
    guard response["request_id"]?.stringValue == requestId,
          response["type"]?.stringValue == "hello_ack",
          response["sequence"]?.intValue == 1,
          let payload = response["payload"]?.objectValue,
          payload["guest_api_version"]?.intValue == Self.protocolVersion else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return payload
  }

  private func executePayload(
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    workspacePath: String
  ) throws -> AgentMcpJSONObject {
    guard let language = input["language"]?.stringValue,
          supportedLanguages.contains(language) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux execution request is invalid.")
    }
    let arguments = input["arguments"]?.arrayValue ?? []
    guard arguments.allSatisfy({ $0.stringValue != nil }) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux execution arguments are invalid.")
    }
    let timeoutMillis = input["timeout_ms"]?.intValue ?? 60_000
    guard (100...(30 * 60_000)).contains(timeoutMillis) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux execution timeout is invalid.")
    }
    let artifactPaths = input["artifact_paths"]?.arrayValue ?? []
    let allowedDomains = input["allowed_network_domains"]?.arrayValue ?? []
    let secretEnvironment = try validatedSecretEnvironment(input)
    let projectGitProfile = input[AgentIOSRuntimeBrokerInternalInput.resourceProfile]?.stringValue ==
      AgentIOSRuntimeBrokerInternalInput.projectGitResourceProfile
    return [
      "language": .string(language),
      "arguments": .array(arguments),
      "workspace_id": .string(workspaceId(context)),
      "workspace_path": .string(workspacePath),
      "artifact_paths": .array(artifactPaths),
      "secret_environment": .object(secretEnvironment),
      "network": .object([
        "enabled": .bool(input["network_enabled"]?.boolValue ?? false),
        "allowed_domains": .array(allowedDomains)
      ]),
      "limits": .object([
        "wall_clock_ms": .int(timeoutMillis),
        "cpu_ms": .int(min(timeoutMillis, 45_000)),
        "memory_bytes": .int(projectGitProfile ? 1024 * 1024 * 1024 : 512 * 1024 * 1024),
        "disk_bytes": .int(projectGitProfile ? 2 * 1024 * 1024 * 1024 : 512 * 1024 * 1024),
        "max_processes": .int(projectGitProfile ? 128 : 64),
        "max_output_bytes": .int(projectGitProfile ? 1024 * 1024 : 512 * 1024),
        "max_artifact_bytes": .int(256 * 1024 * 1024)
      ])
    ]
  }

  private func validatedSecretEnvironment(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    guard let value = input[AgentIOSRuntimeBrokerInternalInput.secretEnvironment] else { return [:] }
    guard let environment = value.objectValue, environment.count <= 32 else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux secret environment is invalid.")
    }
    for (key, value) in environment {
      guard key.range(of: "^[A-Z_][A-Z0-9_]{0,63}$", options: .regularExpression) != nil,
            let secret = value.stringValue,
            !secret.contains("\u{0}"),
            secret.utf8.count <= 4_096 else {
        throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux secret environment is invalid.")
      }
    }
    return environment
  }

  private func envelope(
    requestId: String,
    type: String,
    sequence: Int64,
    payload: AgentMcpJSONObject
  ) -> AgentMcpJSONObject {
    var value: AgentMcpJSONObject = [
      "protocol_version": .int(Self.protocolVersion),
      "message_id": .string(UUID().uuidString),
      "request_id": .string(requestId),
      "type": .string(type),
      "sequence": .int(sequence),
      "timestamp_millis": .int(max(0, nowMillis())),
      "payload": .object(payload)
    ]
    value["mac"] = .string(mac(for: value))
    return value
  }

  private func verify(_ envelope: AgentMcpJSONObject) throws {
    guard envelope["protocol_version"]?.intValue == Self.protocolVersion,
          (envelope["message_id"]?.stringValue?.isEmpty == false),
          (envelope["request_id"]?.stringValue?.isEmpty == false),
          (envelope["type"]?.stringValue?.isEmpty == false),
          (envelope["sequence"]?.intValue ?? 0) >= 1,
          let timestamp = envelope["timestamp_millis"]?.intValue,
          abs(timestamp - nowMillis()) <= 5 * 60_000,
          let suppliedBase64 = envelope["mac"]?.stringValue,
          let supplied = Data(base64Encoded: suppliedBase64) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    guard constantTimeEquals(supplied, Data(base64Encoded: mac(for: envelope)) ?? Data()) else {
      throw AgentIOSRuntimeBrokerError.authenticationFailed
    }
  }

  private func mac(for envelope: AgentMcpJSONObject) -> String {
    let values = [
      String(envelope["protocol_version"]?.intValue ?? 0),
      envelope["message_id"]?.stringValue ?? "",
      envelope["request_id"]?.stringValue ?? "",
      envelope["type"]?.stringValue ?? "",
      String(envelope["sequence"]?.intValue ?? 0),
      String(envelope["timestamp_millis"]?.intValue ?? 0),
      AgentMcpJSONCodec.stringify(envelope["payload"]?.objectValue ?? [:])
    ].joined(separator: "\n")
    let key = SymmetricKey(data: sessionKey)
    return Data(HMAC<SHA256>.authenticationCode(for: Data(values.utf8), using: key)).base64EncodedString()
  }

  private func openConnection() throws -> NWConnection {
    let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
    connection.start(queue: DispatchQueue(label: "com.galaxyssi.ios.qemu-guest", qos: .userInitiated))
    return connection
  }

  private func send(_ envelope: AgentMcpJSONObject, through connection: NWConnection, timeout: DispatchTime) throws {
    let frame = Data(AgentMcpJSONCodec.stringify(envelope).utf8)
    guard (1...Self.maximumFrameBytes).contains(frame.count) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux request is too large.")
    }
    let length = UInt32(frame.count).bigEndian
    let data = withUnsafeBytes(of: length) { Data($0) } + frame
    let signal = DispatchSemaphore(value: 0)
    var failure: Error?
    connection.send(content: data, completion: .contentProcessed { error in
      failure = error
      signal.signal()
    })
    guard signal.wait(timeout: timeout) == .success else { throw AgentIOSRuntimeBrokerError.timeout }
    if let failure { throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription) }
  }

  private func receive(through connection: NWConnection, timeout: DispatchTime) throws -> AgentMcpJSONObject {
    let header = try receive(exactly: 4, through: connection, timeout: timeout)
    let length = header.reduce(0) { ($0 << 8) | Int($1) }
    guard (1...Self.maximumFrameBytes).contains(length) else { throw AgentIOSRuntimeBrokerError.malformedResponse }
    let frame = try receive(exactly: length, through: connection, timeout: timeout)
    guard let envelope = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: frame) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return envelope
  }

  private func receive(exactly length: Int, through connection: NWConnection, timeout: DispatchTime) throws -> Data {
    let signal = DispatchSemaphore(value: 0)
    var received: Data?
    var failure: NWError?
    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
      received = data
      failure = error
      signal.signal()
    }
    guard signal.wait(timeout: timeout) == .success else { throw AgentIOSRuntimeBrokerError.timeout }
    if let failure { throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription) }
    guard let received, received.count == length else { throw AgentIOSRuntimeBrokerError.malformedResponse }
    return received
  }

  private func timeout(deadlineEpochMillis: Int64, maximum: Int64) -> DispatchTime {
    let remaining = deadlineEpochMillis > nowMillis() ? deadlineEpochMillis - nowMillis() : maximum
    return .now() + .milliseconds(Int(min(maximum, max(250, remaining))))
  }

  private func workspaceId(_ context: AgentNativeToolInvocationContext) -> String {
    let raw = [context.attributes["workspace_id"], context.turnId, context.conversationId, context.invocationId]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "default"
    return raw
  }

  private let supportedLanguages: Set<String> = [
    "shell", "python", "uv", "javascript", "typescript", "go", "rust", "c", "cpp", "java", "browser", "ffmpeg", "ffprobe"
  ]

  private func constantTimeEquals(_ left: Data, _ right: Data) -> Bool {
    guard left.count == right.count else { return false }
    return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }
}

struct AgentIOSInAppQemuRuntimeBroker: AgentIOSRuntimeBrokerProviding {
  // TCI has no JIT on non-jailbroken iOS, so a cold Debian boot needs a longer health window.
  static let coldBootHealthTimeoutMillis: Int64 = 45_000
  private static let guestStartupAttempts = 180

  var implementationId: String = "galaxyssi.ios.qemu_tci.debian_v1"
  var runtimeRootURL: URL
  var controller: AgentIOSQemuRuntimeController = .shared
  var credentials: AgentIOSRuntimeBrokerCredentials = AgentIOSRuntimeBrokerCredentials()

  func availability() -> AgentNativeToolAvailability {
    controller.availability()
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    deadlineEpochMillis: Int64
  ) throws -> AgentMcpJSONObject {
    if credentials.sessionKey() == nil {
      try credentials.storeSessionKey(base64Encoded: AgentIOSRuntimeBrokerPairingKey.generate())
    }
    guard let key = credentials.sessionKey() else { throw AgentIOSRuntimeBrokerError.pairingRequired }
    try controller.startIfNeeded(runtimeRootURL: runtimeRootURL, sessionKey: key)
    var lastError: Error?
    // A no-JIT TCI guest can take up to 45 seconds to boot on a physical iPhone.
    for _ in 0..<Self.guestStartupAttempts {
      do {
        let client = AgentIOSQemuGuestClient(
          socketPath: try controller.socketPath(runtimeRootURL: runtimeRootURL),
          sessionKey: key
        )
        switch operation {
        case .status:
          return try client.status(deadlineEpochMillis: deadlineEpochMillis)
        case .execute:
          return try client.execute(
            input: input,
            context: context,
            workspacePath: try prepareWorkspace(input: input, context: context),
            deadlineEpochMillis: deadlineEpochMillis
          )
        case .softwareCatalog, .softwareSearch, .softwareInspect, .softwareInstall, .softwareRemove:
          let executionInput = try AgentIOSQemuLinuxSoftware.executionInput(operation: operation, input: input)
          let result = try client.execute(
            input: executionInput,
            context: context,
            workspacePath: try prepareWorkspace(input: executionInput, context: context),
            deadlineEpochMillis: deadlineEpochMillis
          )
          return try AgentIOSQemuLinuxSoftware.result(
            operation: operation,
            input: input,
            guestResult: result
          )
        default:
          throw AgentIOSRuntimeBrokerError.remote(
            code: "runtime_operation_not_supported",
            message: "The embedded Debian guest currently supports runtime status and execution.",
            retryable: false
          )
        }
      } catch let error as AgentIOSRuntimeBrokerError {
        guard shouldRetryGuestStartup(error) else { throw error }
        lastError = error
        Thread.sleep(forTimeInterval: 0.25)
      } catch {
        throw error
      }
    }
    throw lastError ?? AgentIOSRuntimeBrokerError.timeout
  }

  private func prepareWorkspace(
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) throws -> String {
    let workspaceId = [context.attributes["workspace_id"], context.turnId, context.conversationId, context.invocationId]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "default"
    guard workspaceId.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil,
          let language = input["language"]?.stringValue,
          let fileName = sourceFileName(language: language),
          let source = input["source"]?.stringValue,
          source.utf8.count <= 512 * 1_024 else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The iOS Linux workspace request is invalid.")
    }
    let workspace = runtimeRootURL
      .appendingPathComponent("projects", isDirectory: true)
      .appendingPathComponent(workspaceId, isDirectory: true)
    let control = workspace.appendingPathComponent(".galaxyssi-runtime", isDirectory: true)
    try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
    try Data(source.utf8).write(to: control.appendingPathComponent(fileName), options: [.atomic])
    return "/workspace/\(workspaceId)"
  }

  private func sourceFileName(language: String) -> String? {
    [
      "shell": "main.sh", "python": "main.py", "uv": "main.py", "javascript": "main.js",
      "typescript": "main.ts", "go": "main.go", "rust": "main.rs", "c": "main.c",
      "cpp": "main.cpp", "java": "Main.java", "browser": "main.browser.js",
      "ffmpeg": "main.sh", "ffprobe": "main.sh"
    ][language]
  }

  private func shouldRetryGuestStartup(_ error: AgentIOSRuntimeBrokerError) -> Bool {
    switch error {
    case .timeout, .transport:
      return true
    case .remote(let code, _, _):
      return code == "runtime_guest_not_ready"
    default:
      return false
    }
  }
}
