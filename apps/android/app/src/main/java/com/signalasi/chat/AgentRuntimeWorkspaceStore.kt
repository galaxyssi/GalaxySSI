package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

enum class AgentRuntimeReceiptStatus { RUNNING, COMPLETED, FAILED, CANCELLED, TIMED_OUT }

enum class AgentRuntimeVerificationKind(val wireValue: String) {
    NONE("none"),
    TEST("test"),
    BUILD("build"),
    LINT("lint"),
    PACKAGE("package");

    companion object {
        fun fromWireValue(value: String): AgentRuntimeVerificationKind =
            entries.firstOrNull { it.wireValue == value.trim().lowercase(Locale.ROOT) } ?: NONE
    }
}

enum class AgentRuntimeWorkspaceDisposition(val wireValue: String) {
    UNCHANGED("unchanged"),
    COMMITTED("committed"),
    PERSISTED_WITH_FAILURE("persisted_with_failure"),
    FAILED_CANDIDATE("failed_candidate"),
    ROLLED_BACK("rolled_back"),
    ROLLBACK_FAILED("rollback_failed")
}

data class AgentRuntimeExecutionReceipt(
    val requestId: String,
    val workspaceId: String,
    val language: AgentRuntimeLanguage,
    val sourceSha256: String,
    val verificationKind: AgentRuntimeVerificationKind = AgentRuntimeVerificationKind.NONE,
    val packVersions: Map<String, String>,
    val networkEnabled: Boolean,
    val allowedNetworkDomains: List<String>,
    val limits: AgentRuntimeResourceLimits,
    val status: AgentRuntimeReceiptStatus,
    val exitCode: Int? = null,
    val stdoutSha256: String = "",
    val stderrSha256: String = "",
    val artifacts: List<Map<String, Any?>> = emptyList(),
    val error: String = "",
    val projectFingerprint: String = "",
    val projectFingerprintChecked: Boolean = false,
    val checkpointId: String = "",
    val workspaceDisposition: AgentRuntimeWorkspaceDisposition = AgentRuntimeWorkspaceDisposition.UNCHANGED,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val completedAtMillis: Long = 0L
)

fun AgentRuntimeExecutionReceipt.toEvidenceMap(): AgentNativeJsonObject = linkedMapOf(
    "request_id" to requestId,
    "workspace_id" to workspaceId,
    "language" to language.wireValue,
    "source_sha256" to sourceSha256,
    "verification_kind" to verificationKind.wireValue,
    "pack_versions" to packVersions.toSortedMap(),
    "network_enabled" to networkEnabled,
    "allowed_network_domains" to allowedNetworkDomains.sorted(),
    "limits" to linkedMapOf(
        "wall_clock_ms" to limits.wallClockMillis,
        "cpu_ms" to limits.cpuMillis,
        "memory_bytes" to limits.memoryBytes,
        "disk_bytes" to limits.diskBytes,
        "max_processes" to limits.maxProcesses,
        "max_output_bytes" to limits.maxOutputBytes,
        "max_artifact_bytes" to limits.maxArtifactBytes
    ),
    "status" to status.name.lowercase(Locale.ROOT),
    "exit_code" to exitCode,
    "stdout_sha256" to stdoutSha256,
    "stderr_sha256" to stderrSha256,
    "artifacts" to artifacts.map { artifact ->
        linkedMapOf(
            "relative_path" to artifact["relative_path"],
            "size_bytes" to artifact["size_bytes"],
            "sha256" to artifact["sha256"]
        )
    },
    "error" to error,
    "checkpoint_id" to checkpointId,
    "workspace_disposition" to workspaceDisposition.wireValue,
    "created_at_millis" to createdAtMillis,
    "completed_at_millis" to completedAtMillis
)

internal interface AgentRuntimeReceiptPersistence {
    fun contains(key: String): Boolean
    fun readString(key: String, defaultValue: String): String
    fun writeString(key: String, value: String)
    fun mutateStrings(upserts: Map<String, String>, removeKeys: Collection<String> = emptyList())
    fun keys(prefix: String): List<String>
    fun clear()
}

private class AgentRuntimeEncryptedReceiptPersistence(context: Context) : AgentRuntimeReceiptPersistence {
    private val database = AgentEncryptedDatabase(context.applicationContext, "signalasi_runtime_receipts_v2")

    override fun contains(key: String): Boolean = database.contains(key)

    override fun readString(key: String, defaultValue: String): String = database.readString(key, defaultValue)

    override fun writeString(key: String, value: String) = database.writeString(key, value)

    override fun mutateStrings(upserts: Map<String, String>, removeKeys: Collection<String>) =
        database.mutateStrings(upserts, removeKeys)

    override fun keys(prefix: String): List<String> = database.keys(prefix)

    override fun clear() = database.clear()
}

class AgentRuntimeExecutionReceiptStore internal constructor(
    private val persistence: AgentRuntimeReceiptPersistence,
    private val clock: () -> Long = System::currentTimeMillis
) {
    constructor(context: Context) : this(AgentRuntimeEncryptedReceiptPersistence(context), System::currentTimeMillis)

    fun begin(request: AgentRuntimeExecutionRequest, packVersions: Map<String, String>): AgentRuntimeExecutionReceipt {
        return synchronized(STORE_LOCK) {
            val indexKey = indexKey(request.requestId)
            check(!persistence.contains(indexKey)) { "Runtime request id was already used" }
            val receipt = AgentRuntimeExecutionReceipt(
                requestId = request.requestId,
                workspaceId = request.workspaceId,
                language = request.language,
                sourceSha256 = sha256(request.source.toByteArray(Charsets.UTF_8)),
                verificationKind = request.verificationKind,
                packVersions = packVersions.toSortedMap(),
                networkEnabled = request.networkEnabled,
                allowedNetworkDomains = request.allowedNetworkDomains.sorted(),
                limits = request.resourceLimits,
                status = AgentRuntimeReceiptStatus.RUNNING,
                createdAtMillis = clock()
            )
            val receiptKey = receiptKey(receipt)
            val existingReceiptKeys = persistence.keys(RECEIPT_PREFIX)
            val staleReceiptKeys = existingReceiptKeys.take(
                (existingReceiptKeys.size + 1 - MAX_RECEIPTS).coerceAtLeast(0)
            )
            persistence.mutateStrings(
                upserts = mapOf(
                    receiptKey to receipt.toJson().toString(),
                    indexKey to receiptKey
                ),
                removeKeys = staleReceiptKeys + staleReceiptKeys.map(::indexKeyFromReceiptKey)
            )
            receipt
        }
    }

    fun complete(
        requestId: String,
        response: AgentRuntimeExecutionResponse,
        artifacts: List<Map<String, Any?>>
    ): AgentRuntimeExecutionReceipt? = update(requestId) { receipt ->
        receipt.copy(
            status = if (response.exitCode == 0) AgentRuntimeReceiptStatus.COMPLETED else AgentRuntimeReceiptStatus.FAILED,
            exitCode = response.exitCode,
            stdoutSha256 = sha256(response.stdout.toByteArray(Charsets.UTF_8)),
            stderrSha256 = sha256(response.stderr.toByteArray(Charsets.UTF_8)),
            artifacts = artifacts.take(MAX_ARTIFACTS),
            projectFingerprint = response.projectFingerprint,
            projectFingerprintChecked = response.projectFingerprintChecked,
            checkpointId = response.checkpointId,
            workspaceDisposition = response.workspaceDisposition,
            completedAtMillis = clock()
        )
    }

    fun fail(
        requestId: String,
        error: Throwable,
        checkpointId: String = "",
        workspaceDisposition: AgentRuntimeWorkspaceDisposition = AgentRuntimeWorkspaceDisposition.UNCHANGED
    ): AgentRuntimeExecutionReceipt? = update(requestId) { receipt ->
        receipt.copy(
            status = when (error) {
                is AgentNativeToolCancelledException -> AgentRuntimeReceiptStatus.CANCELLED
                is AgentNativeToolTimeoutException -> AgentRuntimeReceiptStatus.TIMED_OUT
                else -> AgentRuntimeReceiptStatus.FAILED
            },
            error = error.message.orEmpty().take(MAX_ERROR_CHARS),
            checkpointId = checkpointId.ifBlank { receipt.checkpointId },
            workspaceDisposition = workspaceDisposition,
            completedAtMillis = clock()
        )
    }

    fun find(requestId: String): AgentRuntimeExecutionReceipt? = synchronized(STORE_LOCK) {
        readReceipt(requestId)
    }

    fun list(limit: Int = MAX_RECEIPTS): List<AgentRuntimeExecutionReceipt> = synchronized(STORE_LOCK) {
        val safeLimit = limit.coerceIn(0, MAX_RECEIPTS)
        persistence.keys(RECEIPT_PREFIX)
            .takeLast(safeLimit)
            .mapNotNull { key -> decodeReceipt(persistence.readString(key, "")) }
            .asReversed()
    }

    fun clear() = synchronized(STORE_LOCK) { persistence.clear() }

    private fun update(
        requestId: String,
        transform: (AgentRuntimeExecutionReceipt) -> AgentRuntimeExecutionReceipt
    ): AgentRuntimeExecutionReceipt? = synchronized(STORE_LOCK) {
        val indexKey = indexKey(requestId)
        val receiptKey = persistence.readString(indexKey, "").takeIf(String::isNotBlank) ?: return@synchronized null
        val receipt = decodeReceipt(persistence.readString(receiptKey, ""))
            ?.takeIf { it.requestId == requestId }
            ?: return@synchronized null
        transform(receipt).also { updated ->
            persistence.writeString(receiptKey, updated.toJson().toString())
        }
    }

    private fun readReceipt(requestId: String): AgentRuntimeExecutionReceipt? {
        val receiptKey = persistence.readString(indexKey(requestId), "").takeIf(String::isNotBlank) ?: return null
        return decodeReceipt(persistence.readString(receiptKey, ""))?.takeIf { it.requestId == requestId }
    }

    private fun decodeReceipt(raw: String): AgentRuntimeExecutionReceipt? =
        runCatching { JSONObject(raw).toReceipt() }.getOrNull()

    private fun receiptKey(receipt: AgentRuntimeExecutionReceipt): String =
        "$RECEIPT_PREFIX${receipt.createdAtMillis.toString().padStart(13, '0')}:${requestHash(receipt.requestId)}"

    private fun indexKey(requestId: String): String = "$INDEX_PREFIX${requestHash(requestId)}"

    private fun indexKeyFromReceiptKey(receiptKey: String): String = "$INDEX_PREFIX${receiptKey.substringAfterLast(':')}"

    private fun requestHash(requestId: String): String = sha256(requestId.toByteArray(Charsets.UTF_8))

    private fun AgentRuntimeExecutionReceipt.toJson(): JSONObject = JSONObject()
        .put("request_id", requestId)
        .put("workspace_id", workspaceId)
        .put("language", language.wireValue)
        .put("source_sha256", sourceSha256)
        .put("verification_kind", verificationKind.wireValue)
        .put("pack_versions", JSONObject(packVersions))
        .put("network_enabled", networkEnabled)
        .put("allowed_network_domains", JSONArray(allowedNetworkDomains))
        .put("limits", limits.toJson())
        .put("status", status.name)
        .put("exit_code", exitCode)
        .put("stdout_sha256", stdoutSha256)
        .put("stderr_sha256", stderrSha256)
        .put("artifacts", JSONArray(artifacts.map(::JSONObject)))
        .put("error", error)
        .put("project_fingerprint", projectFingerprint)
        .put("project_fingerprint_checked", projectFingerprintChecked)
        .put("checkpoint_id", checkpointId)
        .put("workspace_disposition", workspaceDisposition.wireValue)
        .put("created_at_millis", createdAtMillis)
        .put("completed_at_millis", completedAtMillis)

    private fun JSONObject.toReceipt(): AgentRuntimeExecutionReceipt? {
        val requestId = optString("request_id")
        val language = AgentRuntimeLanguage.entries.firstOrNull { it.wireValue == optString("language") }
        if (requestId.isBlank() || language == null) return null
        val packJson = optJSONObject("pack_versions") ?: JSONObject()
        val artifactsJson = optJSONArray("artifacts") ?: JSONArray()
        return AgentRuntimeExecutionReceipt(
            requestId = requestId,
            workspaceId = optString("workspace_id"),
            language = language,
            sourceSha256 = optString("source_sha256"),
            verificationKind = AgentRuntimeVerificationKind.fromWireValue(optString("verification_kind")),
            packVersions = buildMap {
                packJson.keys().asSequence().forEach { key -> put(key, packJson.optString(key)) }
            },
            networkEnabled = optBoolean("network_enabled"),
            allowedNetworkDomains = optJSONArray("allowed_network_domains").strings(),
            limits = optJSONObject("limits").toLimits(),
            status = runCatching { AgentRuntimeReceiptStatus.valueOf(optString("status")) }
                .getOrDefault(AgentRuntimeReceiptStatus.FAILED),
            exitCode = if (has("exit_code") && !isNull("exit_code")) optInt("exit_code") else null,
            stdoutSha256 = optString("stdout_sha256"),
            stderrSha256 = optString("stderr_sha256"),
            artifacts = buildList {
                for (index in 0 until artifactsJson.length()) {
                    artifactsJson.optJSONObject(index)?.let { artifact ->
                        add(buildMap {
                            artifact.keys().asSequence().forEach { key -> put(key, artifact.opt(key)) }
                        })
                    }
                }
            },
            error = optString("error"),
            projectFingerprint = optString("project_fingerprint"),
            projectFingerprintChecked = optBoolean("project_fingerprint_checked"),
            checkpointId = optString("checkpoint_id"),
            workspaceDisposition = AgentRuntimeWorkspaceDisposition.entries.firstOrNull {
                it.wireValue == optString("workspace_disposition")
            } ?: AgentRuntimeWorkspaceDisposition.UNCHANGED,
            createdAtMillis = optLong("created_at_millis"),
            completedAtMillis = optLong("completed_at_millis")
        )
    }

    private fun AgentRuntimeResourceLimits.toJson(): JSONObject = JSONObject()
        .put("wall_clock_ms", wallClockMillis)
        .put("cpu_ms", cpuMillis)
        .put("memory_bytes", memoryBytes)
        .put("disk_bytes", diskBytes)
        .put("max_processes", maxProcesses)
        .put("max_output_bytes", maxOutputBytes)
        .put("max_artifact_bytes", maxArtifactBytes)

    private fun JSONObject?.toLimits(): AgentRuntimeResourceLimits {
        val source = this ?: return AgentRuntimeResourceLimits()
        return AgentRuntimeResourceLimits(
            wallClockMillis = source.optLong("wall_clock_ms", 60_000L),
            cpuMillis = source.optLong("cpu_ms", 45_000L),
            memoryBytes = source.optLong("memory_bytes", 512L * 1024L * 1024L),
            diskBytes = source.optLong("disk_bytes", 512L * 1024L * 1024L),
            maxProcesses = source.optInt("max_processes", 64),
            maxOutputBytes = source.optLong("max_output_bytes", 512L * 1024L),
            maxArtifactBytes = source.optLong("max_artifact_bytes", 256L * 1024L * 1024L)
        )
    }

    private fun JSONArray?.strings(): List<String> = buildList {
        val source = this@strings ?: return@buildList
        for (index in 0 until source.length()) source.optString(index).takeIf(String::isNotBlank)?.let(::add)
    }

    companion object {
        private val STORE_LOCK = Any()
        private const val RECEIPT_PREFIX = "receipt:"
        private const val INDEX_PREFIX = "index:"
        private const val MAX_RECEIPTS = 1_000
        private const val MAX_ARTIFACTS = 32
        private const val MAX_ERROR_CHARS = 4_096
    }
}

data class AgentRuntimePreparedWorkspace(
    val requestId: String,
    val workspaceId: String,
    val directory: File,
    val sourceFile: File,
    val guestPath: String,
    val projectDirectory: File,
    val importedProjectBytes: Long,
    val buildArtifactBaseline: Map<String, Long>,
    val direct: Boolean = false,
    val metadataDirectory: File = directory
)

data class AgentRuntimeProjectSync(
    val fileCount: Int,
    val totalBytes: Long,
    val projectDirectory: File
)

data class AgentRuntimeProjectCommit(
    val project: AgentRuntimeProjectSync,
    val checkpoint: AgentRuntimeWorkspaceCheckpoint?
)

data class AgentRuntimeWorkspaceCheckpoint(
    val checkpointId: String,
    val workspaceId: String,
    val directory: File,
    val fileCount: Int,
    val totalBytes: Long,
    val createdAtMillis: Long
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "checkpoint_id" to checkpointId,
        "file_count" to fileCount,
        "total_bytes" to totalBytes,
        "created_at_millis" to createdAtMillis
    )
}

data class AgentRuntimeWorkspaceStatus(
    val workspaceId: String,
    val fileCount: Int,
    val totalBytes: Long,
    val checkpoints: List<AgentRuntimeWorkspaceCheckpoint>
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "workspace_id" to workspaceId,
        "file_count" to fileCount,
        "total_bytes" to totalBytes,
        "checkpoints" to checkpoints.map(AgentRuntimeWorkspaceCheckpoint::publicValue)
    )
}

class AgentRuntimeWorkspaceManager private constructor(
    private val root: File,
    private val projectRoot: File,
    private val checkpointRoot: File,
    private val directExecution: Boolean
) {
    constructor(context: Context) : this(
        File(context.applicationContext.filesDir, "agent-runtime/workspaces"),
        File(context.applicationContext.filesDir, "agent-native-workspaces"),
        File(context.applicationContext.filesDir, "agent-runtime/checkpoints"),
        true
    )

    internal constructor(
        runtimeRoot: File,
        projectRoot: File,
        forTesting: Boolean = true,
        directExecution: Boolean = false
    ) :
        this(
            runtimeRoot,
            projectRoot,
            File(runtimeRoot.parentFile ?: runtimeRoot, "checkpoints"),
            directExecution
        )

    @Synchronized
    fun prepare(request: AgentRuntimeExecutionRequest): AgentRuntimePreparedWorkspace {
        require(request.requestId.matches(ID_PATTERN)) { "Runtime request id is invalid" }
        require(request.workspaceId.isNotBlank() && request.workspaceId.length <= MAX_WORKSPACE_ID_CHARS) {
            "Runtime workspace id is invalid"
        }
        request.resourceLimits.validated()
        require(request.artifactPaths.distinct().size == request.artifactPaths.size) {
            "Runtime artifact paths must be unique"
        }
        request.artifactPaths.forEach(::validateRelativePath)
        require(request.hostInputFiles.size <= MAX_HOST_INPUT_FILES) { "Too many runtime host input files" }
        require(request.hostInputFiles.map { it.relativePath }.distinct().size == request.hostInputFiles.size) {
            "Runtime host input paths must be unique"
        }
        request.hostInputFiles.forEach { input ->
            validateRelativePath(input.relativePath)
            require(input.sourceFile.isFile && input.sourceFile.canRead()) { "Runtime host input is unavailable" }
            require(!Files.isSymbolicLink(input.sourceFile.toPath())) { "Runtime host input cannot be a symbolic link" }
        }
        request.allowedNetworkDomains.forEach(::validateDomain)
        if (!request.networkEnabled) require(request.allowedNetworkDomains.isEmpty()) {
            "Runtime network domains require network access"
        }
        check(root.mkdirs() || root.isDirectory) { "Runtime workspace storage is unavailable" }
        cleanupExpiredIfDue()
        check(projectRoot.mkdirs() || projectRoot.isDirectory) { "Agent project storage is unavailable" }
        val projectDirectory = safeChild(projectRoot, request.workspaceId)
            ?: error("Agent project path is invalid")
        check(projectDirectory.mkdirs() || projectDirectory.isDirectory) { "Agent project could not be opened" }
        val workspaceDirectory = safeChild(root, sha256(request.workspaceId.toByteArray()).take(32))
            ?: error("Runtime workspace path is invalid")
        val runDirectory = safeChild(workspaceDirectory, request.requestId)
            ?: error("Runtime request path is invalid")
        check(!runDirectory.exists()) { "Runtime request workspace already exists" }
        check(runDirectory.mkdirs()) { "Runtime request workspace could not be created" }
        val executionDirectory = if (directExecution) projectDirectory else runDirectory
        if (directExecution) {
            cleanupRuntimeFiles(executionDirectory)
            excludeRuntimeFilesFromGit(executionDirectory)
            if (request.workspaceMutationExpected) {
                writeGitCheckpoint(executionDirectory, File(runDirectory, GIT_CHECKPOINT_MANIFEST))
            }
        }
        val importedProjectBytes = if (directExecution) {
            0L
        } else {
            copyTree(
                source = projectDirectory,
                destination = executionDirectory,
                byteLimit = request.resourceLimits.diskBytes
            ).totalBytes
        }
        var stagedInputBytes = importedProjectBytes
        request.hostInputFiles.forEach { input ->
            val target = safeChild(executionDirectory, "$RUNTIME_INPUT_DIRECTORY/${input.relativePath}")
                ?: error("Runtime host input path is invalid")
            stagedInputBytes += input.sourceFile.length()
            check(stagedInputBytes <= request.resourceLimits.diskBytes) {
                "Runtime host inputs exceed the runtime disk quota"
            }
            check(target.parentFile?.mkdirs() != false || target.parentFile?.isDirectory == true) {
                "Runtime host input storage is unavailable"
            }
            Files.copy(
                input.sourceFile.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING
            )
        }
        val buildArtifactBaseline = if (request.discoverBuildArtifacts) {
            buildArtifactCandidates(executionDirectory)
                .associate { candidate ->
                    candidate.relativeTo(executionDirectory).path.replace('\\', '/') to artifactStamp(candidate)
                }
        } else {
            emptyMap()
        }
        val sourceFile = File(executionDirectory, sourceFileName(request.language)).apply {
            val controlDirectory = requireNotNull(parentFile)
            check(controlDirectory.mkdirs() || controlDirectory.isDirectory) {
                "Runtime control storage is unavailable"
            }
        }
        sourceFile.writeText(request.source, Charsets.UTF_8)
        if (!directExecution) {
            check(directorySize(executionDirectory, request.resourceLimits.diskBytes) <= request.resourceLimits.diskBytes) {
                "Agent project exceeds the runtime disk quota"
            }
        }
        File(runDirectory, "request.json").writeText(
            JSONObject()
                .put("request_id", request.requestId)
                .put("workspace_id_hash", sha256(request.workspaceId.toByteArray()))
                .put("language", request.language.wireValue)
                .put("source_sha256", sha256(request.source.toByteArray(Charsets.UTF_8)))
                .put("created_at_millis", System.currentTimeMillis())
                .toString(),
            Charsets.UTF_8
        )
        return AgentRuntimePreparedWorkspace(
            requestId = request.requestId,
            workspaceId = request.workspaceId,
            directory = executionDirectory,
            sourceFile = sourceFile,
            guestPath = if (directExecution) {
                "/workspace/${projectDirectory.name}"
            } else {
                "/workspace/${workspaceDirectory.name}/${runDirectory.name}"
            },
            projectDirectory = projectDirectory,
            importedProjectBytes = importedProjectBytes,
            buildArtifactBaseline = buildArtifactBaseline,
            direct = directExecution,
            metadataDirectory = runDirectory
        )
    }

    /** Replaces the durable project snapshot only after a complete, bounded copy succeeds. */
    @Synchronized
    fun syncProject(prepared: AgentRuntimePreparedWorkspace, byteLimit: Long): AgentRuntimeProjectSync {
        if (prepared.direct) {
            return AgentRuntimeProjectSync(0, 0L, prepared.projectDirectory)
        }
        val parent = prepared.projectDirectory.parentFile ?: error("Agent project storage is invalid")
        val staging = safeChild(parent, ".${prepared.projectDirectory.name}.${prepared.requestId}.staging")
            ?: error("Agent project staging path is invalid")
        val backup = safeChild(parent, ".${prepared.projectDirectory.name}.${prepared.requestId}.backup")
            ?: error("Agent project backup path is invalid")
        staging.deleteRecursively()
        backup.deleteRecursively()
        check(staging.mkdirs()) { "Agent project staging directory could not be created" }
        val copied = try {
            copyTree(prepared.directory, staging, byteLimit, excludeRuntimeControlFiles = true)
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
        val current = prepared.projectDirectory
        if (current.exists()) check(current.renameTo(backup)) { "Agent project backup could not be created" }
        if (!staging.renameTo(current)) {
            current.deleteRecursively()
            if (backup.exists()) backup.renameTo(current)
            error("Agent project snapshot could not be committed")
        }
        backup.deleteRecursively()
        return AgentRuntimeProjectSync(copied.fileCount, copied.totalBytes, current)
    }

    /**
     * Commits the isolated run and promotes the previous durable project to a checkpoint.
     * This reuses the atomic backup move instead of copying the project a second time.
     */
    @Synchronized
    fun commitProject(
        prepared: AgentRuntimePreparedWorkspace,
        byteLimit: Long,
        checkpointId: String
    ): AgentRuntimeProjectCommit {
        require(checkpointId.matches(ID_PATTERN)) { "Runtime checkpoint id is invalid" }
        if (prepared.direct) {
            return AgentRuntimeProjectCommit(
                project = AgentRuntimeProjectSync(0, 0L, prepared.projectDirectory),
                checkpoint = null
            )
        }
        val current = prepared.projectDirectory
        val parent = current.parentFile ?: error("Agent project storage is invalid")
        val projectStaging = safeChild(parent, ".${current.name}.${prepared.requestId}.commit-staging")
            ?: error("Agent project staging path is invalid")
        val checkpointWorkspace = checkpointWorkspace(prepared.workspaceId)
        check(checkpointWorkspace.mkdirs() || checkpointWorkspace.isDirectory) {
            "Runtime checkpoint storage is unavailable"
        }
        val checkpointTarget = safeChild(checkpointWorkspace, checkpointId)
            ?: error("Runtime checkpoint path is invalid")
        val checkpointStaging = safeChild(checkpointWorkspace, ".$checkpointId.commit-staging")
            ?: error("Runtime checkpoint staging path is invalid")
        check(!checkpointTarget.exists()) { "Runtime checkpoint already exists" }
        projectStaging.deleteRecursively()
        checkpointStaging.deleteRecursively()
        check(projectStaging.mkdirs()) { "Agent project staging directory could not be created" }
        val candidate = try {
            copyTree(prepared.directory, projectStaging, byteLimit, excludeRuntimeControlFiles = true)
        } catch (error: Throwable) {
            projectStaging.deleteRecursively()
            throw error
        }
        val previous = treeStats(current, byteLimit)
        check(current.renameTo(checkpointStaging)) { "Agent project checkpoint could not be staged" }
        if (!projectStaging.renameTo(current)) {
            check(checkpointStaging.renameTo(current)) { "Agent project could not be restored after commit failure" }
            error("Agent project snapshot could not be committed")
        }
        val createdAt = System.currentTimeMillis()
        try {
            writeCheckpointManifest(
                directory = checkpointStaging,
                checkpointId = checkpointId,
                workspaceId = prepared.workspaceId,
                fileCount = previous.fileCount,
                totalBytes = previous.totalBytes,
                createdAtMillis = createdAt
            )
            check(checkpointStaging.renameTo(checkpointTarget)) {
                "Runtime checkpoint could not be committed"
            }
        } catch (error: Throwable) {
            File(checkpointStaging, CHECKPOINT_MANIFEST).delete()
            check(current.deleteRecursively()) { "Failed project candidate could not be removed" }
            check(checkpointStaging.renameTo(current)) {
                "Agent project could not be restored after checkpoint failure"
            }
            throw error
        }
        checkpointTarget.setLastModified(createdAt)
        pruneCheckpoints(checkpointWorkspace)
        return AgentRuntimeProjectCommit(
            project = AgentRuntimeProjectSync(candidate.fileCount, candidate.totalBytes, current),
            checkpoint = AgentRuntimeWorkspaceCheckpoint(
                checkpointId = checkpointId,
                workspaceId = prepared.workspaceId,
                directory = checkpointTarget,
                fileCount = previous.fileCount,
                totalBytes = previous.totalBytes,
                createdAtMillis = createdAt
            )
        )
    }

    @Synchronized
    fun checkpoint(
        workspaceId: String,
        checkpointId: String,
        byteLimit: Long
    ): AgentRuntimeWorkspaceCheckpoint {
        require(checkpointId.matches(ID_PATTERN)) { "Runtime checkpoint id is invalid" }
        val project = projectDirectory(workspaceId)
        val workspace = checkpointWorkspace(workspaceId)
        check(workspace.mkdirs() || workspace.isDirectory) { "Runtime checkpoint storage is unavailable" }
        val target = safeChild(workspace, checkpointId) ?: error("Runtime checkpoint path is invalid")
        val staging = safeChild(workspace, ".$checkpointId.staging")
            ?: error("Runtime checkpoint staging path is invalid")
        check(!target.exists()) { "Runtime checkpoint already exists" }
        staging.deleteRecursively()
        check(staging.mkdirs()) { "Runtime checkpoint staging directory could not be created" }
        val copied = try {
            copyTree(project, staging, byteLimit, excludeRuntimeControlFiles = true)
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
        val createdAt = System.currentTimeMillis()
        writeCheckpointManifest(
            directory = staging,
            checkpointId = checkpointId,
            workspaceId = workspaceId,
            fileCount = copied.fileCount,
            totalBytes = copied.totalBytes,
            createdAtMillis = createdAt
        )
        if (!staging.renameTo(target)) {
            staging.deleteRecursively()
            error("Runtime checkpoint could not be committed")
        }
        target.setLastModified(createdAt)
        pruneCheckpoints(workspace)
        return AgentRuntimeWorkspaceCheckpoint(
            checkpointId,
            workspaceId,
            target,
            copied.fileCount,
            copied.totalBytes,
            createdAt
        )
    }

    @Synchronized
    fun checkpoints(workspaceId: String): List<AgentRuntimeWorkspaceCheckpoint> {
        val workspace = checkpointWorkspace(workspaceId)
        if (!workspace.isDirectory) return emptyList()
        return workspace.listFiles().orEmpty()
            .filter { it.isDirectory && !it.name.startsWith(".") }
            .mapNotNull { checkpointValue(workspaceId, it) }
            .sortedByDescending(AgentRuntimeWorkspaceCheckpoint::createdAtMillis)
    }

    @Synchronized
    fun workspaceStatus(workspaceId: String): AgentRuntimeWorkspaceStatus {
        val project = projectDirectory(workspaceId)
        val stats = treeStats(project, MAX_WORKSPACE_STATUS_BYTES)
        return AgentRuntimeWorkspaceStatus(
            workspaceId = workspaceId,
            fileCount = stats.fileCount,
            totalBytes = stats.totalBytes,
            checkpoints = checkpoints(workspaceId)
        )
    }

    @Synchronized
    internal fun projectVerificationPlan(
        workspaceId: String,
        projectScope: String,
        verificationKind: AgentRuntimeVerificationKind
    ): AgentRuntimeProjectVerificationPlan {
        val project = projectDirectory(workspaceId)
        check(project.isDirectory) { "The phone project workspace is empty" }
        return AgentRuntimeProjectVerificationPlanner.plan(project, projectScope, verificationKind)
    }

    @Synchronized
    internal fun projectProfiles(workspaceId: String): List<AgentRuntimeProjectProfile> =
        AgentRuntimeProjectVerificationPlanner.profiles(projectDirectory(workspaceId))

    @Synchronized
    fun rollback(
        workspaceId: String,
        checkpointId: String,
        byteLimit: Long
    ): AgentRuntimeProjectSync {
        require(checkpointId.matches(ID_PATTERN)) { "Runtime checkpoint id is invalid" }
        val checkpoint = safeChild(checkpointWorkspace(workspaceId), checkpointId)
            ?.takeIf(File::isDirectory)
            ?: error("Runtime checkpoint was not found")
        val manifest = checkpointValue(workspaceId, checkpoint)
            ?: error("Runtime checkpoint manifest is invalid")
        check(manifest.checkpointId == checkpointId) { "Runtime checkpoint identity does not match" }
        val current = projectDirectory(workspaceId)
        val parent = current.parentFile ?: error("Agent project storage is invalid")
        val staging = safeChild(parent, ".${current.name}.$checkpointId.rollback-staging")
            ?: error("Runtime rollback staging path is invalid")
        val backup = safeChild(parent, ".${current.name}.$checkpointId.rollback-backup")
            ?: error("Runtime rollback backup path is invalid")
        staging.deleteRecursively()
        backup.deleteRecursively()
        check(staging.mkdirs()) { "Runtime rollback staging directory could not be created" }
        val copied = try {
            copyTree(checkpoint, staging, byteLimit, excludeRuntimeControlFiles = true)
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
        if (current.exists()) check(current.renameTo(backup)) { "Runtime rollback backup could not be created" }
        if (!staging.renameTo(current)) {
            current.deleteRecursively()
            if (backup.exists()) backup.renameTo(current)
            error("Runtime checkpoint could not be restored")
        }
        backup.deleteRecursively()
        return AgentRuntimeProjectSync(copied.fileCount, copied.totalBytes, current)
    }

    @Synchronized
    fun installArchiveCompatibilityTools(prepared: AgentRuntimePreparedWorkspace): File {
        val bin = safeChild(prepared.directory, RUNTIME_TOOL_DIRECTORY)
            ?: error("Runtime tool path is invalid")
        check(bin.mkdirs() || bin.isDirectory) { "Runtime tool directory is unavailable" }
        writeExecutable(File(bin, "zip"), ZIP_COMPATIBILITY_TOOL)
        writeExecutable(File(bin, "unzip"), UNZIP_COMPATIBILITY_TOOL)
        return bin
    }

    @Synchronized
    fun collectArtifacts(
        prepared: AgentRuntimePreparedWorkspace,
        request: AgentRuntimeExecutionRequest
    ): List<Map<String, Any?>> {
        val explicitlyRequested = request.artifactPaths.mapNotNull { relative ->
            val runtimeArtifact = safeChild(prepared.directory, relative) ?: return@mapNotNull null
            val artifact = runtimeArtifact.takeIf { it.exists() }
                ?: safeChild(prepared.projectDirectory, relative)?.takeIf { it.exists() }
                ?: return@mapNotNull null
            relative.replace('\\', '/') to artifact
        }
        val requested = explicitlyRequested.ifEmpty {
            discoverChangedBuildArtifact(prepared)?.let(::listOf).orEmpty()
        }
        if (requested.size > 1 || requested.any { it.second.isDirectory }) {
            return listOf(packageProjectArtifacts(prepared, request, requested))
        }
        var totalBytes = 0L
        return requested.mapNotNull { (relative, artifact) ->
            if (!artifact.isFile) return@mapNotNull null
            val bytes = artifact.length()
            check(bytes <= request.resourceLimits.maxArtifactBytes) { "Runtime artifact exceeds its size limit" }
            totalBytes += bytes
            check(totalBytes <= request.resourceLimits.diskBytes) { "Runtime artifacts exceed the workspace quota" }
            mapOf(
                "relative_path" to relative,
                "size_bytes" to bytes,
                "sha256" to sha256File(artifact),
                "host_path" to artifact.absolutePath,
                "artifact_kind" to "file"
            )
        }
    }

    private fun discoverChangedBuildArtifact(
        prepared: AgentRuntimePreparedWorkspace
    ): Pair<String, File>? = buildArtifactCandidates(prepared.directory)
        .asSequence()
        .map { candidate -> candidate.relativeTo(prepared.directory).path.replace('\\', '/') to candidate }
        .filter { (relative, candidate) ->
            prepared.buildArtifactBaseline[relative] != artifactStamp(candidate)
        }
        .sortedWith(
            compareByDescending<Pair<String, File>> { (_, file) -> buildArtifactPriority(file) }
                .thenByDescending { (_, file) -> file.lastModified() }
                .thenBy { (relative, _) -> relative }
        )
        .firstOrNull()

    private fun buildArtifactCandidates(directory: File): List<File> {
        if (!directory.isDirectory) return emptyList()
        return Files.walk(directory.toPath()).use { paths ->
            paths.filter { path -> Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) }
                .map { it.toFile() }
                .filter(::isStandardBuildArtifact)
                .limit(MAX_DISCOVERED_BUILD_ARTIFACT_CANDIDATES.toLong())
                .toList()
        }
    }

    private fun isStandardBuildArtifact(file: File): Boolean {
        val extension = file.extension.lowercase(Locale.ROOT)
        if (extension !in AUTO_DISCOVERED_BUILD_EXTENSIONS) return false
        val normalized = file.path.replace('\\', '/').lowercase(Locale.ROOT)
        return AUTO_DISCOVERED_BUILD_DIRECTORIES.any { marker -> marker in normalized }
    }

    private fun buildArtifactPriority(file: File): Int = when (file.extension.lowercase(Locale.ROOT)) {
        "apk" -> 3
        "aab" -> 2
        "zip" -> 1
        else -> 0
    }

    private fun artifactStamp(file: File): Long = file.lastModified() * 31L + file.length()

    private fun packageProjectArtifacts(
        prepared: AgentRuntimePreparedWorkspace,
        request: AgentRuntimeExecutionRequest,
        requested: List<Pair<String, File>>
    ): Map<String, Any?> {
        val exportDirectory = safeChild(File(root.parentFile, "exports").apply { mkdirs() }, sha256(prepared.workspaceId.toByteArray()).take(32))
            ?: error("Runtime export path is invalid")
        check(exportDirectory.mkdirs() || exportDirectory.isDirectory) { "Runtime export storage is unavailable" }
        val baseName = requested.firstOrNull()?.first
            ?.substringAfterLast('/')
            ?.substringBeforeLast('.')
            ?.replace(Regex("[^A-Za-z0-9._-]"), "-")
            ?.take(48)
            ?.ifBlank { "project" }
            ?: "project"
        val archive = File(exportDirectory, "$baseName-project.zip")
        val temporary = File(exportDirectory, ".${archive.name}.${prepared.requestId}.tmp")
        temporary.delete()
        var fileCount = 0
        var sourceBytes = 0L
        val entryNames = linkedSetOf<String>()
        try {
            ZipOutputStream(temporary.outputStream().buffered()).use { zip ->
                requested.forEach { (relative, source) ->
                    if (source.isFile) {
                        addProjectZipFile(zip, source, relative, request, entryNames).also { bytes ->
                            sourceBytes += bytes
                            fileCount++
                        }
                    } else {
                        val rootPath = source.toPath()
                        Files.walk(rootPath).use { paths ->
                            paths.filter { path -> Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) }
                                .forEach { path ->
                                    check(!Files.isSymbolicLink(path)) { "Symbolic links are not allowed in runtime artifacts" }
                                    val child = path.toFile()
                                    val suffix = rootPath.relativize(path).toString().replace('\\', '/')
                                    val entryName = listOf(relative.trimEnd('/'), suffix)
                                        .filter(String::isNotBlank)
                                        .joinToString("/")
                                    addProjectZipFile(zip, child, entryName, request, entryNames).also { bytes ->
                                        sourceBytes += bytes
                                        fileCount++
                                    }
                                }
                        }
                    }
                    check(fileCount <= MAX_PROJECT_ARCHIVE_FILES) { "Runtime project contains too many files" }
                    check(sourceBytes <= request.resourceLimits.diskBytes) { "Runtime project exceeds the workspace quota" }
                }
            }
            check(fileCount > 0) { "Runtime project does not contain exportable files" }
            check(temporary.length() <= request.resourceLimits.maxArtifactBytes) { "Runtime project archive exceeds its size limit" }
            if (archive.exists()) check(archive.delete()) { "Previous runtime project archive could not be replaced" }
            check(temporary.renameTo(archive)) { "Runtime project archive could not be committed" }
        } catch (error: Throwable) {
            temporary.delete()
            throw error
        }
        return mapOf(
            "relative_path" to archive.name,
            "size_bytes" to archive.length(),
            "sha256" to sha256File(archive),
            "host_path" to archive.absolutePath,
            "artifact_kind" to "project_archive",
            "file_count" to fileCount,
            "source_bytes" to sourceBytes
        )
    }

    private fun addProjectZipFile(
        zip: ZipOutputStream,
        source: File,
        relativePath: String,
        request: AgentRuntimeExecutionRequest,
        entryNames: MutableSet<String>
    ): Long {
        val normalized = relativePath.replace('\\', '/').trimStart('/')
        validateRelativePath(normalized)
        if (!entryNames.add(normalized)) return 0L
        val bytes = source.length()
        check(bytes <= request.resourceLimits.maxArtifactBytes) { "Runtime project file exceeds its size limit" }
        zip.putNextEntry(ZipEntry(normalized).apply { time = 0L })
        source.inputStream().buffered().use { it.copyTo(zip) }
        zip.closeEntry()
        return bytes
    }

    @Synchronized
    fun markFinished(prepared: AgentRuntimePreparedWorkspace, status: AgentRuntimeReceiptStatus) {
        File(prepared.metadataDirectory, "status.json").writeText(
            JSONObject()
                .put("status", status.name.lowercase(Locale.ROOT))
                .put("completed_at_millis", System.currentTimeMillis())
                .toString(),
            Charsets.UTF_8
        )
        if (prepared.direct) cleanupRuntimeFiles(prepared.directory)
    }

    @Synchronized
    fun cleanupExpired(nowMillis: Long = System.currentTimeMillis()) {
        if (root.isDirectory) {
            root.listFiles().orEmpty().filter(File::isDirectory).forEach { workspace ->
                workspace.listFiles().orEmpty().filter(File::isDirectory).forEach { run ->
                    val age = nowMillis - run.lastModified().coerceAtLeast(0L)
                    if (age > WORKSPACE_TTL_MILLIS) run.deleteRecursively()
                }
                if (workspace.listFiles().isNullOrEmpty()) workspace.delete()
            }
        }
    }

    internal fun cleanupExpiredIfDue(nowMillis: Long = System.currentTimeMillis()): Boolean {
        check(root.mkdirs() || root.isDirectory) { "Runtime workspace storage is unavailable" }
        val marker = File(root, CLEANUP_MARKER)
        if (!cleanupDue(marker, nowMillis)) return false
        return synchronized(MAINTENANCE_LOCK) {
            if (!cleanupDue(marker, nowMillis)) return@synchronized false
            cleanupExpired(nowMillis)
            val temporary = File(root, "$CLEANUP_MARKER.tmp")
            temporary.writeText(nowMillis.toString(), Charsets.UTF_8)
            runCatching {
                Files.move(
                    temporary.toPath(),
                    marker.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                )
            }.getOrElse {
                Files.move(temporary.toPath(), marker.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
            true
        }
    }

    private fun cleanupDue(marker: File, nowMillis: Long): Boolean {
        val lastCleanup = marker.takeIf(File::isFile)
            ?.let { file -> runCatching { file.readText(Charsets.UTF_8).trim().toLong() }.getOrNull() }
            ?: return true
        val age = nowMillis - lastCleanup
        return age < 0L || age >= CLEANUP_INTERVAL_MILLIS
    }

    private fun projectDirectory(workspaceId: String): File {
        require(workspaceId.isNotBlank() && workspaceId.length <= MAX_WORKSPACE_ID_CHARS) {
            "Runtime workspace id is invalid"
        }
        check(projectRoot.mkdirs() || projectRoot.isDirectory) { "Agent project storage is unavailable" }
        return safeChild(projectRoot, workspaceId)?.apply {
            check(mkdirs() || isDirectory) { "Agent project could not be opened" }
        } ?: error("Agent project path is invalid")
    }

    private fun checkpointWorkspace(workspaceId: String): File {
        require(workspaceId.isNotBlank() && workspaceId.length <= MAX_WORKSPACE_ID_CHARS) {
            "Runtime workspace id is invalid"
        }
        check(checkpointRoot.mkdirs() || checkpointRoot.isDirectory) {
            "Runtime checkpoint storage is unavailable"
        }
        return safeChild(
            checkpointRoot,
            sha256(workspaceId.toByteArray(Charsets.UTF_8)).take(32)
        ) ?: error("Runtime checkpoint workspace path is invalid")
    }

    private fun checkpointValue(
        workspaceId: String,
        directory: File
    ): AgentRuntimeWorkspaceCheckpoint? = runCatching {
        val manifest = JSONObject(File(directory, CHECKPOINT_MANIFEST).readText(Charsets.UTF_8))
        check(
            manifest.optString("workspace_id_sha256") ==
                sha256(workspaceId.toByteArray(Charsets.UTF_8))
        ) { "Runtime checkpoint belongs to another workspace" }
        AgentRuntimeWorkspaceCheckpoint(
            checkpointId = manifest.getString("checkpoint_id"),
            workspaceId = workspaceId,
            directory = directory,
            fileCount = manifest.getInt("file_count"),
            totalBytes = manifest.getLong("total_bytes"),
            createdAtMillis = manifest.getLong("created_at_millis")
        )
    }.getOrNull()

    private fun writeCheckpointManifest(
        directory: File,
        checkpointId: String,
        workspaceId: String,
        fileCount: Int,
        totalBytes: Long,
        createdAtMillis: Long
    ) {
        File(directory, CHECKPOINT_MANIFEST).writeText(
            JSONObject()
                .put("checkpoint_id", checkpointId)
                .put("workspace_id_sha256", sha256(workspaceId.toByteArray(Charsets.UTF_8)))
                .put("file_count", fileCount)
                .put("total_bytes", totalBytes)
                .put("created_at_millis", createdAtMillis)
                .toString(),
            Charsets.UTF_8
        )
    }

    private fun pruneCheckpoints(workspace: File) {
        var retainedBytes = 0L
        workspace.listFiles().orEmpty()
            .filter { it.isDirectory && !it.name.startsWith(".") }
            .sortedByDescending(File::lastModified)
            .forEachIndexed { index, checkpoint ->
                val storedBytes = runCatching {
                    JSONObject(File(checkpoint, CHECKPOINT_MANIFEST).readText(Charsets.UTF_8))
                        .getLong("total_bytes")
                }.getOrNull()
                val keep = storedBytes != null &&
                    index < MAX_CHECKPOINTS_PER_WORKSPACE &&
                    (index == 0 || retainedBytes + storedBytes <= MAX_CHECKPOINT_BYTES_PER_WORKSPACE)
                if (keep) retainedBytes += storedBytes else checkpoint.deleteRecursively()
            }
    }

    private fun treeStats(directory: File, byteLimit: Long): AgentRuntimeProjectSync {
        var files = 0
        var bytes = 0L
        if (!directory.isDirectory) return AgentRuntimeProjectSync(0, 0L, directory)
        Files.walk(directory.toPath()).use { paths ->
            paths.forEach { path ->
                if (Files.isSymbolicLink(path)) error("Symbolic links are not allowed in Agent projects")
                if (Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    bytes += Files.size(path)
                    check(bytes <= byteLimit) { "Agent project exceeds the inspection quota" }
                    files += 1
                }
            }
        }
        return AgentRuntimeProjectSync(files, bytes, directory)
    }

    private fun safeChild(parent: File, relative: String): File? {
        if (relative.isBlank() || File(relative).isAbsolute) return null
        val canonicalParent = parent.canonicalFile
        val candidate = File(canonicalParent, relative).canonicalFile
        return candidate.takeIf { it.path.startsWith(canonicalParent.path + File.separator) }
    }

    private fun copyTree(
        source: File,
        destination: File,
        byteLimit: Long,
        excludeRuntimeControlFiles: Boolean = false
    ): AgentRuntimeProjectSync {
        val sourcePath = source.toPath()
        val destinationPath = destination.toPath()
        var files = 0
        var bytes = 0L
        Files.walk(sourcePath).use { paths ->
            paths.forEach { current ->
                if (Files.isSymbolicLink(current)) error("Symbolic links are not allowed in Agent projects")
                val relative = sourcePath.relativize(current)
                if (relative.toString().isEmpty()) return@forEach
                val portable = relative.toString().replace('\\', '/')
                if (excludeRuntimeControlFiles && isRuntimeControlPath(portable)) return@forEach
                val target = destinationPath.resolve(relative).normalize()
                check(target.startsWith(destinationPath)) { "Agent project path escapes its workspace" }
                when {
                    Files.isDirectory(current, LinkOption.NOFOLLOW_LINKS) -> Files.createDirectories(target)
                    Files.isRegularFile(current, LinkOption.NOFOLLOW_LINKS) -> {
                        val size = Files.size(current)
                        bytes += size
                        check(bytes <= byteLimit) { "Agent project exceeds the runtime disk quota" }
                        Files.createDirectories(target.parent)
                        Files.copy(
                            current,
                            target,
                            StandardCopyOption.REPLACE_EXISTING,
                            StandardCopyOption.COPY_ATTRIBUTES
                        )
                        files += 1
                    }
                    else -> error("Unsupported entry in Agent project: $portable")
                }
            }
        }
        return AgentRuntimeProjectSync(files, bytes, destination)
    }

    private fun cleanupRuntimeFiles(directory: File) {
        listOf(
            RUNTIME_CONTROL_DIRECTORY,
            RUNTIME_INPUT_DIRECTORY,
            RUNTIME_TOOL_DIRECTORY.substringBefore('/')
        ).forEach { relative ->
            safeChild(directory, relative)?.deleteRecursively()
        }
        RUNTIME_CONTROL_FILES.forEach { relative -> safeChild(directory, relative)?.delete() }
    }

    private fun excludeRuntimeFilesFromGit(directory: File) {
        val exclude = File(directory, ".git/info/exclude")
        val parent = exclude.parentFile ?: return
        if (!parent.isDirectory || !exclude.canWrite() && exclude.exists()) return
        val entries = listOf(
            "/$RUNTIME_CONTROL_DIRECTORY/",
            "/$RUNTIME_INPUT_DIRECTORY/",
            "/${RUNTIME_TOOL_DIRECTORY.substringBefore('/')}/"
        )
        val existing = exclude.takeIf(File::isFile)?.readLines(Charsets.UTF_8).orEmpty()
        val missing = entries.filterNot(existing::contains)
        if (missing.isEmpty()) return
        check(parent.mkdirs() || parent.isDirectory) {
            "Git exclude storage is unavailable"
        }
        exclude.appendText(
            buildString {
                if (exclude.length() > 0L && !exclude.readText(Charsets.UTF_8).endsWith("\n")) append('\n')
                missing.forEach { append(it).append('\n') }
            },
            Charsets.UTF_8
        )
    }

    private fun writeGitCheckpoint(directory: File, target: File) {
        val git = File(directory, ".git")
        val headFile = File(git, "HEAD").takeIf(File::isFile) ?: return
        val head = headFile.readText(Charsets.UTF_8).trim().take(MAX_GIT_REFERENCE_CHARS)
        val reference = head.removePrefix("ref:").trim().takeIf { head.startsWith("ref:") }
        val commit = when {
            reference != null -> File(git, reference).takeIf(File::isFile)
                ?.readText(Charsets.UTF_8)?.trim()
                ?: packedReference(File(git, "packed-refs"), reference)
            else -> head
        }.orEmpty().take(MAX_GIT_OBJECT_ID_CHARS)
        target.writeText(
            JSONObject()
                .put("format_version", 1)
                .put("head", head)
                .put("reference", reference.orEmpty())
                .put("commit", commit)
                .put("created_at_millis", System.currentTimeMillis())
                .toString(),
            Charsets.UTF_8
        )
    }

    private fun packedReference(file: File, reference: String): String? = file
        .takeIf(File::isFile)
        ?.useLines(Charsets.UTF_8) { lines ->
            lines.map(String::trim)
                .filter { it.isNotEmpty() && !it.startsWith('#') && !it.startsWith('^') }
                .map { it.split(Regex("\\s+"), limit = 2) }
                .firstOrNull { it.size == 2 && it[1] == reference }
                ?.firstOrNull()
        }

    private fun directorySize(directory: File, limit: Long): Long {
        var total = 0L
        Files.walk(directory.toPath()).use { paths ->
            paths.forEach { path ->
                if (Files.isSymbolicLink(path)) error("Symbolic links are not allowed in Agent projects")
                if (Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    total += Files.size(path)
                    check(total <= limit) { "Agent project exceeds the runtime disk quota" }
                }
            }
        }
        return total
    }

    private fun isRuntimeControlPath(path: String): Boolean =
        path in RUNTIME_CONTROL_FILES || path == ".tmp" || path.startsWith(".tmp/") ||
            path == RUNTIME_TOOL_DIRECTORY || path.startsWith("$RUNTIME_TOOL_DIRECTORY/") ||
            path == RUNTIME_CONTROL_DIRECTORY || path.startsWith("$RUNTIME_CONTROL_DIRECTORY/") ||
            path == RUNTIME_INPUT_DIRECTORY || path.startsWith("$RUNTIME_INPUT_DIRECTORY/")

    private fun writeExecutable(file: File, source: String) {
        file.writeText(source.trimIndent() + "\n", Charsets.UTF_8)
        check(file.setExecutable(true, true) || file.canExecute()) { "Runtime compatibility tool is not executable" }
    }

    private fun validateRelativePath(value: String) {
        require(value.isNotBlank() && value.length <= MAX_ARTIFACT_PATH_CHARS && !File(value).isAbsolute) {
            "Runtime artifact path is invalid"
        }
        require(value.replace('\\', '/').split('/').none { it.isBlank() || it == "." || it == ".." }) {
            "Runtime artifact path is unsafe"
        }
    }

    private fun validateDomain(value: String) {
        require(DOMAIN_PATTERN.matches(value.lowercase(Locale.ROOT))) { "Runtime network domain is invalid" }
    }

    private fun sourceFileName(language: AgentRuntimeLanguage): String = when (language) {
        AgentRuntimeLanguage.SHELL -> "$RUNTIME_CONTROL_DIRECTORY/main.sh"
        AgentRuntimeLanguage.PYTHON, AgentRuntimeLanguage.UV -> "$RUNTIME_CONTROL_DIRECTORY/main.py"
        AgentRuntimeLanguage.JAVASCRIPT -> "$RUNTIME_CONTROL_DIRECTORY/main.js"
        AgentRuntimeLanguage.TYPESCRIPT -> "$RUNTIME_CONTROL_DIRECTORY/main.ts"
        AgentRuntimeLanguage.GO -> "$RUNTIME_CONTROL_DIRECTORY/main.go"
        AgentRuntimeLanguage.RUST -> "$RUNTIME_CONTROL_DIRECTORY/main.rs"
        AgentRuntimeLanguage.C -> "$RUNTIME_CONTROL_DIRECTORY/main.c"
        AgentRuntimeLanguage.CPP -> "$RUNTIME_CONTROL_DIRECTORY/main.cpp"
        AgentRuntimeLanguage.JAVA -> "$RUNTIME_CONTROL_DIRECTORY/Main.java"
        AgentRuntimeLanguage.BROWSER -> "$RUNTIME_CONTROL_DIRECTORY/main.browser.js"
        AgentRuntimeLanguage.FFMPEG -> "$RUNTIME_CONTROL_DIRECTORY/main.ffmpeg.json"
        AgentRuntimeLanguage.FFPROBE -> "$RUNTIME_CONTROL_DIRECTORY/main.ffprobe.json"
    }

    companion object {
        private const val MAX_WORKSPACE_ID_CHARS = 64
        private const val MAX_HOST_INPUT_FILES = 8
        private const val MAX_ARTIFACT_PATH_CHARS = 1_024
        private const val MAX_PROJECT_ARCHIVE_FILES = 1_024
        private const val MAX_DISCOVERED_BUILD_ARTIFACT_CANDIDATES = 128
        private const val MAX_CHECKPOINTS_PER_WORKSPACE = 20
        private const val MAX_CHECKPOINT_BYTES_PER_WORKSPACE = 1024L * 1024L * 1024L
        private const val MAX_WORKSPACE_STATUS_BYTES = 2L * 1024L * 1024L * 1024L
        private const val RUNTIME_TOOL_DIRECTORY = ".signalasi-tools/bin"
        private const val RUNTIME_CONTROL_DIRECTORY = ".signalasi-runtime"
        private const val RUNTIME_INPUT_DIRECTORY = ".signalasi-inputs"
        private const val WORKSPACE_TTL_MILLIS = 7L * 24L * 60L * 60L * 1_000L
        internal const val CLEANUP_INTERVAL_MILLIS = 6L * 60L * 60L * 1_000L
        private const val CLEANUP_MARKER = ".last-successful-cleanup"
        private const val CHECKPOINT_MANIFEST = ".signalasi-checkpoint.json"
        private const val GIT_CHECKPOINT_MANIFEST = "git-checkpoint.json"
        private const val MAX_GIT_REFERENCE_CHARS = 1_024
        private const val MAX_GIT_OBJECT_ID_CHARS = 128
        private val ID_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
        private val DOMAIN_PATTERN = Regex("(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")
        private val AUTO_DISCOVERED_BUILD_EXTENSIONS = setOf("apk", "aab", "zip")
        private val MAINTENANCE_LOCK = Any()
        private val AUTO_DISCOVERED_BUILD_DIRECTORIES = setOf(
            "/build/outputs/",
            "/dist/",
            "/out/",
            "/release/",
            "/releases/"
        )
        private val RUNTIME_CONTROL_FILES = setOf(
            "request.json",
            "status.json",
            CHECKPOINT_MANIFEST,
            ".signalasi-stdout",
            ".signalasi-stderr",
            ".signalasi-main"
        )
        private val ZIP_COMPATIBILITY_TOOL = """
            #!/usr/bin/env python3
            import os
            import sys
            import zipfile

            args = [arg for arg in sys.argv[1:] if not (arg.startswith("-") and arg != "-")]
            if len(args) < 2:
                raise SystemExit("usage: zip archive.zip PATH...")
            archive = args[0] if args[0].lower().endswith(".zip") else args[0] + ".zip"
            sources = args[1:]
            try:
                import zlib
                compression = zipfile.ZIP_DEFLATED
            except ImportError:
                compression = zipfile.ZIP_STORED
            with zipfile.ZipFile(archive, "w", compression=compression) as output:
                for source in sources:
                    if os.path.isdir(source):
                        for root, directories, files in os.walk(source):
                            directories.sort()
                            files.sort()
                            for name in files:
                                path = os.path.join(root, name)
                                output.write(path, os.path.normpath(path).replace(os.sep, "/"))
                    elif os.path.isfile(source):
                        output.write(source, os.path.normpath(source).replace(os.sep, "/"))
                    else:
                        raise SystemExit("zip source not found: " + source)
        """
        private val UNZIP_COMPATIBILITY_TOOL = """
            #!/usr/bin/env python3
            import os
            import shutil
            import stat
            import sys
            import zipfile

            args = sys.argv[1:]
            listing = "-l" in args
            destination = "."
            if "-d" in args:
                index = args.index("-d")
                destination = args[index + 1]
                del args[index:index + 2]
            args = [arg for arg in args if not arg.startswith("-")]
            if not args:
                raise SystemExit("usage: unzip archive.zip [-d DIRECTORY]")
            archive = args[0]
            destination_root = os.path.realpath(destination)
            with zipfile.ZipFile(archive) as source:
                if listing:
                    for item in source.infolist():
                        print(f"{item.file_size:10d}  {item.filename}")
                    raise SystemExit(0)
                for item in source.infolist():
                    normalized = item.filename.replace("\\", "/")
                    target = os.path.realpath(os.path.join(destination_root, normalized))
                    if normalized.startswith("/") or target != destination_root and not target.startswith(destination_root + os.sep):
                        raise SystemExit("unsafe archive entry: " + item.filename)
                    mode = item.external_attr >> 16
                    if stat.S_ISLNK(mode):
                        raise SystemExit("archive links are not allowed: " + item.filename)
                    if item.is_dir():
                        os.makedirs(target, exist_ok=True)
                    else:
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        with source.open(item) as input_file, open(target, "wb") as output_file:
                            shutil.copyfileobj(input_file, output_file)
        """
    }
}

private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
    .digest(bytes)
    .joinToString("") { "%02x".format(it) }

private fun sha256File(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}
