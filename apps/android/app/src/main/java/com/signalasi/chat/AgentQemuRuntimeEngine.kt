package com.signalasi.chat

import android.app.ActivityManager
import android.content.Context
import android.system.Os
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.TimeUnit

internal data class AgentQemuLaunchPlan(
    val command: List<String>,
    val environment: Map<String, String>,
    val logFile: File
)

internal object AgentQemuMemoryPolicy {
    fun resolve(totalRamBytes: Long, availableRamBytes: Long, profileMaximumMegabytes: Int): Int {
        val totalTier = when {
            totalRamBytes >= 8L * GIBIBYTE -> 1_536
            totalRamBytes >= 6L * GIBIBYTE -> 1_024
            totalRamBytes >= 4L * GIBIBYTE -> 768
            else -> 512
        }
        val availableTier = when {
            availableRamBytes >= 3L * GIBIBYTE -> 1_536
            availableRamBytes >= 2L * GIBIBYTE -> 1_024
            availableRamBytes >= 1L * GIBIBYTE -> 768
            else -> 512
        }
        return minOf(totalTier, availableTier, profileMaximumMegabytes)
            .coerceAtLeast(minOf(MINIMUM_BOOT_MEGABYTES, profileMaximumMegabytes))
    }

    private const val GIBIBYTE = 1024L * 1024L * 1024L
    private const val MINIMUM_BOOT_MEGABYTES = 512
}

internal object AgentQemuLaunchPlanBuilder {
    fun build(
        spec: AgentRuntimeEngineLaunchSpec,
        sessionFile: File,
        configFile: File,
        logFile: File,
        memoryMegabytes: Int,
        cpuCount: Int,
        userNetworkBackendAvailable: Boolean = true
    ): AgentQemuLaunchPlan {
        val files = buildList {
            add(spec.engineFile)
            add(spec.baseImageFile)
            add(spec.systemDiskFile)
            add(spec.socketFile)
            add(spec.workspacesDirectory)
            add(sessionFile)
            add(configFile)
            add(logFile)
            addAll(spec.packAttachments.map(AgentRuntimePackAttachment::imageFile))
        }
        files.forEach(::requireSafeQemuPath)
        require(spec.socketFile.absolutePath.toByteArray(Charsets.UTF_8).size <= MAX_UNIX_SOCKET_PATH_BYTES) {
            "Runtime socket path is too long"
        }
        require(memoryMegabytes in MIN_MEMORY_MEGABYTES..MAX_MEMORY_MEGABYTES)
        require(cpuCount in 1..MAX_CPU_COUNT)

        val command = buildList {
            add(spec.engineFile.absolutePath)
            addAll(listOf(
                "-name", "SignalASI Runtime",
                "-machine", "virt,gic-version=3,highmem=off",
                "-accel", "tcg,thread=multi",
                "-cpu", "max",
                "-smp", cpuCount.toString(),
                "-m", "${memoryMegabytes}M",
                "-display", "none",
                "-nodefaults",
                "-no-user-config",
                "-no-reboot",
                "-monitor", "none",
                "-serial", "stdio",
            ))
            if (userNetworkBackendAvailable) {
                addAll(listOf(
                    "-netdev", "user,id=signalasi_net,restrict=off,ipv6=off",
                    "-device", "virtio-net-device,netdev=signalasi_net"
                ))
            } else {
                addAll(listOf("-nic", "none"))
            }
            addAll(listOf(
                "-kernel", spec.baseImageFile.absolutePath,
                "-append", "console=ttyAMA0,115200 panic=1 quiet loglevel=3 signalasi.runtime=1",
                "-chardev",
                "socket,id=signalasi_api,path=${spec.socketFile.absolutePath},server=on,wait=on",
                "-device", "virtio-serial-device",
                "-device", "virtserialport,chardev=signalasi_api,name=org.signalasi.runtime",
                "-fsdev",
                "local,id=signalasi_workspaces,path=${spec.workspacesDirectory.absolutePath},security_model=none,multidevs=remap",
                "-device", "virtio-9p-device,fsdev=signalasi_workspaces,mount_tag=signalasi_workspaces",
                "-fw_cfg", "name=opt/com.signalasi/runtime-session,file=${sessionFile.absolutePath}",
                "-fw_cfg", "name=opt/com.signalasi/runtime-config,file=${configFile.absolutePath}",
                "-object", "rng-random,id=signalasi_rng,filename=/dev/urandom",
                "-device", "virtio-rng-device,rng=signalasi_rng"
            ))
            addAll(listOf(
                "-drive",
                "if=none,id=signalasi_system,file=${spec.systemDiskFile.absolutePath},format=raw,cache=none,aio=threads",
                "-device",
                "virtio-blk-device,drive=signalasi_system,serial=${AgentRuntimePersistentDisk.SERIAL}"
            ))
            spec.packAttachments.sortedBy(AgentRuntimePackAttachment::packId).forEachIndexed { index, pack ->
                val driveId = "signalasi_pack_$index"
                addAll(listOf(
                    "-drive",
                    "if=none,id=$driveId,file=${pack.imageFile.absolutePath},format=raw,readonly=on,cache=none,aio=threads",
                    "-device",
                    "virtio-blk-device,drive=$driveId,serial=${packSerial(pack.packId)}"
                ))
            }
        }
        require(command.size <= MAX_COMMAND_ARGUMENTS) { "Runtime launch command is too large" }
        val runtimeDirectory = requireNotNull(spec.socketFile.parentFile) { "Runtime socket directory is unavailable" }
        val nativeLibraryDirectory = requireNotNull(spec.engineFile.parentFile) {
            "Native runtime directory is unavailable"
        }
        return AgentQemuLaunchPlan(
            command = command,
            environment = mapOf(
                "HOME" to runtimeDirectory.absolutePath,
                "TMPDIR" to runtimeDirectory.absolutePath,
                "LD_LIBRARY_PATH" to nativeLibraryDirectory.absolutePath,
                "LC_ALL" to "C",
                "LANG" to "C"
            ),
            logFile = logFile
        )
    }

    private fun requireSafeQemuPath(file: File) {
        val path = file.absolutePath
        require(path.isNotBlank() && '\n' !in path && '\r' !in path && ',' !in path) {
            "Runtime path cannot be represented safely in the QEMU command"
        }
    }

    internal fun packSerial(packId: String): String = "sa-${packId.lowercase(Locale.ROOT)}"
        .replace(Regex("[^a-z0-9._-]"), "-")
        .take(MAX_PACK_SERIAL_CHARS)

    private const val MIN_MEMORY_MEGABYTES = 256
    private const val MAX_MEMORY_MEGABYTES = 2_048
    private const val MAX_CPU_COUNT = 8
    private const val MAX_COMMAND_ARGUMENTS = 256
    private const val MAX_UNIX_SOCKET_PATH_BYTES = 100
    private const val MAX_PACK_SERIAL_CHARS = 20
}

internal object AgentQemuRuntimeConfigBuilder {
    fun build(
        spec: AgentRuntimeEngineLaunchSpec,
        userNetworkBackendAvailable: Boolean,
        dnsServers: List<String> = DEFAULT_DIRECT_DNS_SERVERS,
        workspaceUid: Int = android.os.Process.myUid()
    ): JSONObject {
        require(dnsServers.size in 1..MAX_DNS_SERVERS) { "Runtime DNS server list is invalid" }
        require(dnsServers.all(::isIpv4Address)) { "Runtime DNS servers must be IPv4 addresses" }
        return JSONObject()
        .put("format_version", 1)
        .put("guest_api_version", AgentRuntimeGuestProtocol.VERSION)
        .put("host_epoch_millis", System.currentTimeMillis())
        .put("architecture", spec.architecture)
        .put("api_channel", "org.signalasi.runtime")
        .put("workspace_mount_tag", "signalasi_workspaces")
        .put("workspace_uid", workspaceUid)
        .put("workspace_gid", workspaceUid)
        .put("execution_mode", "full_access")
        .put("execution_principal", "root")
        .put("network_mode", if (userNetworkBackendAvailable) "host_mediated" else "disabled")
        .put("dns_servers", JSONArray(dnsServers.distinct()))
        .put("system_disk", JSONObject()
            .put("serial", AgentRuntimePersistentDisk.SERIAL)
            .put("filesystem", "ext4")
            .put("mount_path", "/var/lib/signalasi")
            .put("logical_bytes", AgentRuntimePersistentDisk.LOGICAL_BYTES))
        .put("packs", JSONArray().apply {
            spec.packAttachments.sortedBy(AgentRuntimePackAttachment::packId).forEachIndexed { index, pack ->
                put(JSONObject()
                    .put("id", pack.packId)
                    .put("version", pack.version)
                    .put("capabilities", JSONArray(pack.capabilities.sorted()))
                    .put("serial", AgentQemuLaunchPlanBuilder.packSerial(pack.packId))
                    .put("read_only", true)
                    .put("device_index", index))
            }
        })
    }

    private fun isIpv4Address(value: String): Boolean {
        val octets = value.split('.')
        return octets.size == 4 && octets.all { octet ->
            octet.isNotEmpty() && octet.length <= 3 && octet.all(Char::isDigit) &&
                octet.toIntOrNull() in 0..255
        }
    }

    internal val DEFAULT_DIRECT_DNS_SERVERS = listOf("1.1.1.1", "223.5.5.5", "8.8.8.8")
    private const val MAX_DNS_SERVERS = 4
}

class AgentQemuRuntimeEngineController(
    context: Context
) : AgentRuntimeEngineController {
    private val appContext = context.applicationContext
    private val runtimeDirectory = File(appContext.filesDir, "agent-runtime")
    private val sessionFile = File(runtimeDirectory, "guest-session.key")
    private val configFile = File(runtimeDirectory, "guest-config.json")
    private val logFile = File(runtimeDirectory, "qemu.log")

    @Volatile private var process: Process? = null
    @Volatile private var activeSocketFile: File? = null
    @Volatile private var startedAtMillis: Long = 0L
    @Volatile private var lastExitCode: Int? = null

    override val controllerId: String = "signalasi.qemu.tcg.v1"

    @Synchronized
    override fun isRunning(): Boolean {
        val current = process ?: return false
        if (current.isAlive) return true
        lastExitCode = runCatching(current::exitValue).getOrNull()
        process = null
        clearEphemeralFiles()
        return false
    }

    @Synchronized
    override fun start(spec: AgentRuntimeEngineLaunchSpec) {
        check(!isRunning()) { "The QEMU runtime is already running" }
        validate(spec)
        check(runtimeDirectory.mkdirs() || runtimeDirectory.isDirectory) { "Runtime storage is unavailable" }
        check(!spec.socketFile.exists() || spec.socketFile.delete()) { "Cannot remove a stale runtime socket" }
        rotateLog()
        val userNetworkBackendAvailable = userNetworkBackendAvailable(spec.engineFile)
        secureWrite(sessionFile, spec.sessionKey)
        secureWrite(
            configFile,
            AgentQemuRuntimeConfigBuilder.build(spec, userNetworkBackendAvailable)
                .toString().toByteArray(Charsets.UTF_8)
        )
        val deviceProfile = AgentDeviceProfileDetector.detect(appContext)
        val plan = AgentQemuLaunchPlanBuilder.build(
            spec = spec,
            sessionFile = sessionFile,
            configFile = configFile,
            logFile = logFile,
            memoryMegabytes = runtimeMemoryMegabytes(deviceProfile.maxQemuMemoryMegabytes),
            cpuCount = Runtime.getRuntime().availableProcessors()
                .coerceIn(1, deviceProfile.maxQemuCpuCount),
            userNetworkBackendAvailable = userNetworkBackendAvailable
        )
        val child = try {
            ProcessBuilder(plan.command).apply {
                environment().clear()
                environment().putAll(plan.environment)
                redirectInput(ProcessBuilder.Redirect.PIPE)
                redirectOutput(ProcessBuilder.Redirect.appendTo(plan.logFile))
                redirectErrorStream(true)
            }.start()
        } catch (error: Throwable) {
            clearEphemeralFiles()
            throw error
        }
        runCatching { child.outputStream.close() }
        process = child
        activeSocketFile = spec.socketFile
        startedAtMillis = System.currentTimeMillis()
        lastExitCode = null
        monitor(child)
    }

    @Synchronized
    override fun stop() {
        val current = process
        process = null
        if (current != null && current.isAlive) {
            current.destroy()
            if (!runCatching { current.waitFor(GRACEFUL_STOP_MILLIS, TimeUnit.MILLISECONDS) }.getOrDefault(false)) {
                current.destroyForcibly()
                runCatching { current.waitFor(FORCED_STOP_MILLIS, TimeUnit.MILLISECONDS) }
            }
        }
        lastExitCode = current?.let { runCatching(it::exitValue).getOrNull() } ?: lastExitCode
        activeSocketFile?.delete()
        activeSocketFile = null
        clearEphemeralFiles()
    }

    private fun validate(spec: AgentRuntimeEngineLaunchSpec) {
        check(spec.engineFile.isFile && spec.engineFile.canExecute()) { "Install the SignalASI QEMU engine" }
        check(spec.baseImageFile.isFile && spec.baseImageFile.canRead()) { "The linux-base image is unavailable" }
        check(spec.systemDiskFile.isFile && spec.systemDiskFile.canRead() && spec.systemDiskFile.canWrite()) {
            "Persistent Linux system disk is unavailable"
        }
        check(spec.workspacesDirectory.isDirectory && spec.workspacesDirectory.canWrite()) {
            "Runtime workspace storage is unavailable"
        }
        check(spec.sessionKey.size >= MIN_SESSION_KEY_BYTES) { "Runtime session key is too short" }
        spec.packAttachments.forEach { pack ->
            check(pack.packId.matches(PACK_ID_PATTERN) && pack.version.isNotBlank()) { "Runtime pack metadata is invalid" }
            check(pack.imageFile.isFile && pack.imageFile.canRead()) { "Runtime pack image is unavailable: ${pack.packId}" }
        }
    }

    private fun userNetworkBackendAvailable(engineFile: File): Boolean =
        engineFile.parentFile
            ?.listFiles()
            ?.any { file -> file.isFile && file.name.contains("slirp", ignoreCase = true) }
            ?: false

    private fun runtimeMemoryMegabytes(profileMaximumMegabytes: Int): Int {
        val memory = ActivityManager.MemoryInfo()
        runCatching { appContext.getSystemService(ActivityManager::class.java)?.getMemoryInfo(memory) }
        return AgentQemuMemoryPolicy.resolve(
            totalRamBytes = memory.totalMem,
            availableRamBytes = memory.availMem,
            profileMaximumMegabytes = profileMaximumMegabytes
        )
    }

    private fun monitor(child: Process) {
        Thread({
            val exitCode = runCatching(child::waitFor).getOrNull()
            synchronized(this) {
                if (process === child) {
                    process = null
                    lastExitCode = exitCode
                    activeSocketFile?.delete()
                    activeSocketFile = null
                    clearEphemeralFiles()
                }
            }
        }, "signalasi-qemu-monitor").apply {
            isDaemon = true
            start()
        }
    }

    private fun rotateLog() {
        if (!logFile.isFile || logFile.length() <= MAX_LOG_BYTES) return
        val previous = File(runtimeDirectory, "qemu.log.1")
        previous.delete()
        logFile.renameTo(previous)
    }

    private fun secureWrite(target: File, bytes: ByteArray) {
        val temporary = File(target.parentFile, ".${target.name}.tmp")
        temporary.delete()
        FileOutputStream(temporary).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
        Os.chmod(temporary.absolutePath, PRIVATE_FILE_MODE)
        check(!target.exists() || target.delete()) { "Cannot replace runtime bootstrap data" }
        check(temporary.renameTo(target)) { "Cannot publish runtime bootstrap data" }
        Os.chmod(target.absolutePath, PRIVATE_FILE_MODE)
    }

    private fun clearEphemeralFiles() {
        sessionFile.delete()
        configFile.delete()
    }

    companion object {
        private const val MIN_SESSION_KEY_BYTES = 32
        private const val GRACEFUL_STOP_MILLIS = 3_000L
        private const val FORCED_STOP_MILLIS = 1_000L
        private const val MAX_LOG_BYTES = 2L * 1024L * 1024L
        private const val PRIVATE_FILE_MODE = 384
        private val PACK_ID_PATTERN = Regex("[a-z0-9][a-z0-9._-]{0,79}")
    }
}
