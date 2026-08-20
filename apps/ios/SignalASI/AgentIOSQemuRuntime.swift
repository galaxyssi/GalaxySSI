import CryptoKit
import Darwin
import Foundation
import Network

/// Runs the UTM SE QEMU library inside the app process. The TCI build does not require JIT.
final class AgentIOSQemuRuntimeController {
  static let shared = AgentIOSQemuRuntimeController()

  private typealias QemuInit = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
  private typealias QemuMainLoop = @convention(c) () -> Void
  private typealias QemuCleanup = @convention(c) () -> Void

  private let fileManager: FileManager
  private let queue = DispatchQueue(label: "com.signalasi.ios.qemu-tci", qos: .userInitiated)
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
        reason: "The embedded SignalASI Linux 1.3.9 kernel image is unavailable."
      )
    }
    stateLock.lock()
    defer { stateLock.unlock() }
    if phase == .failed {
      return AgentNativeToolAvailability(status: .unavailable, reason: detail.ifBlank("The iOS Linux runtime failed."))
    }
    return .available
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
    guard let frameworkURL = qemuFrameworkURL, let bundledKernelURL else {
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
      let files = try provision(runtimeRootURL: runtimeRootURL, bundledKernelURL: bundledKernelURL, sessionKey: sessionKey)
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

  private struct RuntimeFiles {
    var kernel: URL
    var disk: URL
    var workspace: URL
    var socket: URL
    var session: URL
    var configuration: URL
  }

  private func provision(runtimeRootURL: URL, bundledKernelURL: URL, sessionKey: Data) throws -> RuntimeFiles {
    let runtime = runtimeRootURL.appendingPathComponent("qemu", isDirectory: true)
    let system = runtime.appendingPathComponent("system", isDirectory: true)
    let workspace = runtimeRootURL.appendingPathComponent("projects", isDirectory: true)
    try fileManager.createDirectory(at: system, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)

    let kernel = runtime.appendingPathComponent("linux-base-1.3.9-aarch64.Image", isDirectory: false)
    if !fileManager.fileExists(atPath: kernel.path) {
      try fileManager.copyItem(at: bundledKernelURL, to: kernel)
    }
    let disk = system.appendingPathComponent("signalasi-system.raw", isDirectory: false)
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
    let values: [String: Any] = [
      "format_version": 1,
      "guest_api_version": 1,
      "host_epoch_millis": Int64(Date().timeIntervalSince1970 * 1_000),
      "architecture": "aarch64",
      "api_channel": "org.signalasi.runtime",
      "workspace_mount_tag": "signalasi_workspaces",
      "workspace_uid": 1000,
      "workspace_gid": 1000,
      "execution_mode": "full_access",
      "execution_principal": "root",
      "network_mode": "disabled",
      "dns_servers": [],
      "system_disk": [
        "serial": "sa-system",
        "filesystem": "ext4",
        "mount_path": "/var/lib/signalasi",
        "logical_bytes": 30 * 1024 * 1024 * 1024
      ],
      "packs": []
    ]
    try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]).write(to: configuration, options: .atomic)
    return RuntimeFiles(kernel: kernel, disk: disk, workspace: workspace, socket: socket, session: session, configuration: configuration)
  }

  private func launchArguments(files: RuntimeFiles) -> [String] {
    [
      "qemu-system-aarch64",
      "-name", "SignalASI Linux",
      "-machine", "virt,gic-version=3,highmem=off",
      "-accel", "tcg,thread=multi",
      "-cpu", "max",
      "-smp", "2",
      "-m", "768M",
      "-display", "none",
      "-nodefaults",
      "-no-user-config",
      "-no-reboot",
      "-monitor", "none",
      "-serial", "null",
      "-nic", "none",
      "-kernel", files.kernel.path,
      "-append", "console=ttyAMA0,115200 panic=1 quiet loglevel=3 signalasi.runtime=1",
      "-chardev", "socket,id=signalasi_api,path=\(files.socket.path),server=on,wait=on",
      "-device", "virtio-serial-device",
      "-device", "virtserialport,chardev=signalasi_api,name=org.signalasi.runtime",
      "-fsdev", "local,id=signalasi_workspaces,path=\(files.workspace.path),security_model=none,multidevs=remap",
      "-device", "virtio-9p-device,fsdev=signalasi_workspaces,mount_tag=signalasi_workspaces",
      "-fw_cfg", "name=opt/com.signalasi/runtime-session,file=\(files.session.path)",
      "-fw_cfg", "name=opt/com.signalasi/runtime-config,file=\(files.configuration.path)",
      "-object", "rng-random,id=signalasi_rng,filename=/dev/urandom",
      "-device", "virtio-rng-device,rng=signalasi_rng",
      "-drive", "if=none,id=signalasi_system,file=\(files.disk.path),format=raw,cache=none,aio=threads",
      "-device", "virtio-blk-device,drive=signalasi_system,serial=sa-system"
    ]
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
    let queue = DispatchQueue(label: "com.signalasi.ios.qemu-socket", qos: .userInitiated)
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

struct AgentIOSInAppQemuRuntimeBroker: AgentIOSRuntimeBrokerProviding {
  var implementationId: String = "signalasi.ios.qemu_tci.debian_v1"
  var runtimeRootURL: URL
  var controller: AgentIOSQemuRuntimeController = .shared
  var configurationStore: AgentIOSRuntimeBrokerConfigurationStore = AgentIOSRuntimeBrokerConfigurationStore()
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
    var configuration = configurationStore.load()
    if !configuration.enabled {
      configuration.enabled = true
      try configurationStore.save(configuration)
    }
    if credentials.sessionKey() == nil {
      try credentials.storeSessionKey(base64Encoded: AgentIOSRuntimeBrokerPairingKey.generate())
    }
    guard let key = credentials.sessionKey() else { throw AgentIOSRuntimeBrokerError.pairingRequired }
    try controller.startIfNeeded(runtimeRootURL: runtimeRootURL, sessionKey: key)
    let client = AgentIOSRuntimeBrokerClient(
      configurationStore: configurationStore,
      credentials: credentials,
      transport: AgentIOSUnixRuntimeBrokerTransport(socketPath: {
        try controller.socketPath(runtimeRootURL: runtimeRootURL)
      })
    )
    var lastError: Error?
    for _ in 0..<20 {
      do {
        return try client.invoke(operation: operation, input: input, context: context, deadlineEpochMillis: deadlineEpochMillis)
      } catch {
        lastError = error
        Thread.sleep(forTimeInterval: 0.25)
      }
    }
    throw lastError ?? AgentIOSRuntimeBrokerError.timeout
  }
}
