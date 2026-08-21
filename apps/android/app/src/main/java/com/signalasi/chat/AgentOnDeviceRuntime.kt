package com.signalasi.chat

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.CertificateFactory
import java.util.Locale
import java.util.UUID

internal fun guestArchiveToolPath(guestWorkspacePath: String, relativeToolPath: String): String =
    "${guestWorkspacePath.trimEnd('/')}/${relativeToolPath.replace('\\', '/').trimStart('/')}"

internal fun shellSingleQuote(value: String): String = "'${value.replace("'", "'\"'\"'")}'"

enum class AgentOnDeviceRuntimeBackend(val wireValue: String) {
    QEMU_TCG("qemu_tcg"),
    ANDROID_VIRTUALIZATION_FRAMEWORK("android_virtualization_framework"),
    NONE("none")
}

enum class AgentRuntimePackState(val wireValue: String) {
    READY("ready"),
    NOT_INSTALLED("not_installed"),
    INVALID("invalid"),
    INCOMPATIBLE("incompatible")
}

enum class AgentRuntimeLanguage(
    val wireValue: String,
    val requiredPack: String,
    val requiredCapability: String
) {
    SHELL("shell", "linux-base", "shell.execute"),
    PYTHON("python", "python-uv", "python.execute"),
    UV("uv", "python-uv", "uv.sync"),
    JAVASCRIPT("javascript", "node-js", "javascript.execute"),
    TYPESCRIPT("typescript", "node-js", "typescript.execute"),
    GO("go", "go", "go.execute"),
    RUST("rust", "rust", "rust.execute"),
    C("c", "cpp", "c.execute"),
    CPP("cpp", "cpp", "cpp.execute"),
    JAVA("java", "java", "java.execute"),
    BROWSER("browser", "browser-automation", "browser.automation.execute"),
    FFMPEG("ffmpeg", "ffmpeg", "ffmpeg.execute"),
    FFPROBE("ffprobe", "ffmpeg", "ffprobe.inspect")
}

data class AgentRuntimePackManifest(
    val id: String,
    val version: String,
    val architecture: String,
    val imageFile: String,
    val imageSha256: String,
    val capabilities: List<String>,
    val dependencies: List<String>,
    val installedSizeBytes: Long,
    val license: String,
    val signatureKeyId: String,
    val signature: String,
    val formatVersion: Int = 1,
    val archiveSizeBytes: Long = 0L,
    val minimumHostVersionCode: Long = 1L,
    val guestApiVersion: Int = 1
) {
    fun signingPayload(): ByteArray = listOf(
        formatVersion.toString(),
        id,
        version,
        architecture,
        imageFile,
        imageSha256.lowercase(Locale.ROOT),
        capabilities.sorted().joinToString(","),
        dependencies.sorted().joinToString(","),
        installedSizeBytes.toString(),
        archiveSizeBytes.toString(),
        minimumHostVersionCode.toString(),
        guestApiVersion.toString(),
        license,
        signatureKeyId.lowercase(Locale.ROOT)
    ).joinToString("") { value -> "${value.toByteArray(Charsets.UTF_8).size}:$value" }
        .toByteArray(Charsets.UTF_8)
}

fun interface AgentRuntimePackSignatureVerifier {
    fun verify(manifest: AgentRuntimePackManifest): Boolean
}

class AndroidTrustedRuntimePackVerifier(context: Context) : AgentRuntimePackSignatureVerifier {
    private val verifier = AndroidRuntimePayloadVerifier(context)

    override fun verify(manifest: AgentRuntimePackManifest): Boolean = verifier.verify(
        manifest.signatureKeyId,
        manifest.signature,
        manifest.signingPayload()
    )
}

class AndroidRuntimePayloadVerifier(context: Context) {
    private val appContext = context.applicationContext

    fun verify(signatureKeyId: String, signature: String, payload: ByteArray): Boolean {
        val signatureBytes = runCatching { Base64.decode(signature, Base64.DEFAULT) }.getOrNull()
            ?: return false
        return trustedCertificates().any { certificateBytes ->
            runCatching {
                val certificate = CertificateFactory.getInstance("X.509")
                    .generateCertificate(certificateBytes.inputStream())
                val keyId = MessageDigest.getInstance("SHA-256")
                    .digest(certificate.encoded)
                    .joinToString("") { "%02x".format(it) }
                if (!keyId.equals(signatureKeyId, ignoreCase = true)) return@runCatching false
                val algorithm = when (certificate.publicKey.algorithm.uppercase(Locale.ROOT)) {
                    "RSA" -> "SHA256withRSA"
                    "EC", "ECDSA" -> "SHA256withECDSA"
                    "ED25519", "EDDSA" -> "Ed25519"
                    else -> return@runCatching false
                }
                Signature.getInstance(algorithm).run {
                    initVerify(certificate.publicKey)
                    update(payload)
                    verify(signatureBytes)
                }
            }.getOrDefault(false)
        }
    }

    private fun trustedCertificates(): List<ByteArray> {
        val embedded = decodeTrustAnchors(runCatching {
            appContext.resources.openRawResource(R.raw.signalasi_runtime_trust_anchors)
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
        }.getOrNull())
        val bundled = decodeTrustAnchors(runCatching {
            appContext.assets.open(BUNDLED_TRUST_ANCHORS)
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
        }.getOrNull())
        val debugSigningCertificates = if (
            appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        ) signingCertificates() else emptyList()
        return (embedded + bundled + debugSigningCertificates).distinctBy { certificate ->
            MessageDigest.getInstance("SHA-256").digest(certificate).joinToString("") { "%02x".format(it) }
        }.take(MAX_TRUST_ANCHORS)
    }

    private fun decodeTrustAnchors(raw: String?): List<ByteArray> = runCatching {
        if (raw == null || raw.toByteArray(Charsets.UTF_8).size !in 1..MAX_TRUST_ANCHOR_DOCUMENT_BYTES) {
            return@runCatching emptyList()
        }
        val root = JSONObject(raw)
        require(root.optInt("format_version") == 1)
        val values = root.optJSONArray("certificates") ?: JSONArray()
        buildList {
            for (index in 0 until minOf(values.length(), MAX_TRUST_ANCHORS)) {
                val encoded = values.optString(index)
                if (encoded.isBlank()) continue
                val decoded = Base64.decode(encoded, Base64.DEFAULT)
                require(decoded.size in 1..MAX_CERTIFICATE_BYTES)
                add(decoded)
            }
        }
    }.getOrDefault(emptyList())

    @Suppress("DEPRECATION")
    private fun signingCertificates(): List<ByteArray> {
        val info = appContext.packageManager.getPackageInfo(
            appContext.packageName,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                PackageManager.GET_SIGNATURES
            }
        )
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners.orEmpty()
        } else {
            info.signatures.orEmpty()
        }
        return signatures.map { it.toByteArray() }
    }

    companion object {
        private const val BUNDLED_TRUST_ANCHORS = "runtime/bootstrap/trust-anchors.json"
        private const val MAX_TRUST_ANCHORS = 8
        private const val MAX_CERTIFICATE_BYTES = 32 * 1024
        private const val MAX_TRUST_ANCHOR_DOCUMENT_BYTES = 256 * 1024
    }
}

data class AgentRuntimePackStatus(
    val id: String,
    val state: AgentRuntimePackState,
    val reason: String = "",
    val manifest: AgentRuntimePackManifest? = null
)

data class AgentOnDeviceRuntimeStatus(
    val backend: AgentOnDeviceRuntimeBackend,
    val backendReady: Boolean,
    val reason: String,
    val architecture: String,
    val enginePath: String,
    val avfAdvertised: Boolean,
    val packs: List<AgentRuntimePackStatus>,
    val lifecyclePhase: AgentRuntimeLifecyclePhase = AgentRuntimeLifecyclePhase.STOPPED,
    val lifecycleReason: String = "",
    val lifecycleFailures: Int = 0,
    val lifecycleNextAttemptAtMillis: Long = 0L
) {
    fun languageReady(language: AgentRuntimeLanguage): Boolean = readinessFailure(language) == null

    fun readinessFailure(language: AgentRuntimeLanguage): String? {
        val pack = packs.firstOrNull { it.id == language.requiredPack }
            ?: return "${language.wireValue} requires the ${language.requiredPack} pack"
        if (pack.state != AgentRuntimePackState.READY) {
            return "${language.requiredPack} is ${pack.state.wireValue}: ${pack.reason.ifBlank { "runtime pack is unavailable" }}"
        }
        if (language.requiredCapability !in pack.manifest?.capabilities.orEmpty()) {
            return "${language.requiredPack} does not provide ${language.requiredCapability}"
        }
        if (backend == AgentOnDeviceRuntimeBackend.NONE) {
            return reason.ifBlank { "The on-device Linux runtime engine is unavailable" }
        }
        if (!backendReady) {
            return lifecycleReason.ifBlank { reason }.ifBlank { "The on-device Linux guest bridge is not ready" }
        }
        return null
    }
}

internal data class AgentRuntimeBootstrapFiles(
    val engineFile: File,
    val baseImageFile: File,
    val systemDiskFile: File,
    val socketFile: File,
    val packsDirectory: File,
    val workspacesDirectory: File,
    val architecture: String,
    val packAttachments: List<AgentRuntimePackAttachment>
)

data class AgentRuntimeExecutionRequest(
    val language: AgentRuntimeLanguage,
    val source: String,
    val arguments: List<String>,
    val timeoutMillis: Long,
    val networkEnabled: Boolean,
    val artifactPaths: List<String>,
    val workspaceId: String,
    val verificationKind: AgentRuntimeVerificationKind = AgentRuntimeVerificationKind.NONE,
    val requestId: String = UUID.randomUUID().toString(),
    val allowedNetworkDomains: List<String> = emptyList(),
    val resourceLimits: AgentRuntimeResourceLimits = AgentRuntimeResourceLimits(
        wallClockMillis = timeoutMillis,
        cpuMillis = (timeoutMillis * 3L / 4L).coerceAtLeast(100L)
    ),
    val cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
    val progressListener: (AgentRuntimeProgress) -> Unit = {},
    val guestWorkspacePath: String = "",
    val secretEnvironment: Map<String, String> = emptyMap(),
    val hostInputFiles: List<AgentRuntimeHostInput> = emptyList(),
    val workspaceMutationExpected: Boolean = true
)

/** A host-owned file staged read-only in spirit into one isolated guest run. */
data class AgentRuntimeHostInput(
    val sourceFile: File,
    val relativePath: String
)

data class AgentRuntimeExecutionResponse(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
    val durationMillis: Long,
    val artifacts: List<Map<String, Any?>> = emptyList(),
    val requestId: String = "",
    val executionReceipt: AgentRuntimeExecutionReceipt? = null,
    val projectFileCount: Int = 0,
    val projectBytes: Long = 0L,
    val checkpointId: String = "",
    val workspaceDisposition: AgentRuntimeWorkspaceDisposition = AgentRuntimeWorkspaceDisposition.UNCHANGED
)

fun interface AgentOnDeviceRuntimeBridge {
    fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse
    fun health(): AgentRuntimeBridgeHealth = AgentRuntimeBridgeHealth(ready = true)
    fun cancel(requestId: String): Boolean = false
}

object AgentOnDeviceRuntimeBridgeRegistry {
    @Volatile
    private var active: AgentOnDeviceRuntimeBridge? = null

    fun register(bridge: AgentOnDeviceRuntimeBridge) {
        active = bridge
    }

    fun unregister(bridge: AgentOnDeviceRuntimeBridge) {
        if (active === bridge) active = null
    }

    fun current(): AgentOnDeviceRuntimeBridge? = active
}

class AgentOnDeviceRuntimeManager(
    context: Context,
    private val bridge: AgentOnDeviceRuntimeBridge? = null,
    private val signatureVerifier: AgentRuntimePackSignatureVerifier = AndroidTrustedRuntimePackVerifier(context)
) {
    private val appContext = context.applicationContext
    private val runtimeRoot = File(appContext.filesDir, RUNTIME_DIRECTORY)
    private val packsRoot = File(runtimeRoot, PACKS_DIRECTORY)
    private val integrityCache = appContext.getSharedPreferences(INTEGRITY_CACHE, Context.MODE_PRIVATE)
    private val workspaceManager = AgentRuntimeWorkspaceManager(appContext)
    private val receiptStore = AgentRuntimeExecutionReceiptStore(appContext)
    private val publicationGuard = AgentEncryptedProjectPublicationGuard(appContext)

    fun packStatuses(): List<AgentRuntimePackStatus> = REQUIRED_PACKS.map(::packStatus)

    fun architecture(): String = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()

    fun status(): AgentOnDeviceRuntimeStatus {
        return buildStatus(probeGuest = true, verifyPackIntegrity = true)
    }

    /**
     * A bounded status snapshot for planning and recovery. It never starts, connects to, or
     * health-probes the guest, and it does not hash runtime images.
     */
    fun cachedStatus(): AgentOnDeviceRuntimeStatus {
        return buildStatus(probeGuest = false, verifyPackIntegrity = false)
    }

    private fun buildStatus(
        probeGuest: Boolean,
        verifyPackIntegrity: Boolean
    ): AgentOnDeviceRuntimeStatus {
        val engine = qemuEngineFile()
        val avf = appContext.packageManager.hasSystemFeature(AVF_FEATURE)
        val statuses = REQUIRED_PACKS.map { id -> packStatus(id, verifyPackIntegrity) }
        val base = statuses.first { it.id == "linux-base" }
        val engineReady = engine.isFile && engine.canExecute()
        val baseReady = base.state == AgentRuntimePackState.READY
        val backend = when {
            engineReady && baseReady -> AgentOnDeviceRuntimeBackend.QEMU_TCG
            else -> AgentOnDeviceRuntimeBackend.NONE
        }
        val activeBridge = bridge ?: if (probeGuest) {
            AgentOnDeviceRuntimeSupervisor.discover(appContext)
        } else {
            AgentOnDeviceRuntimeBridgeRegistry.current()
        }
        val bridgeHealth = activeBridge?.let { candidate ->
            if (!probeGuest || bridge == null) {
                AgentOnDeviceRuntimeSupervisor.cachedHealth(candidate)
            } else {
                runCatching { candidate.health() }.getOrElse { error ->
                    AgentRuntimeBridgeHealth(false, reason = error.message ?: "Guest bridge health check failed")
                }
            }
        }
        val lifecycle = if (bridgeHealth?.ready == true) {
            AgentRuntimeLifecycleSnapshot(
                phase = AgentRuntimeLifecyclePhase.READY,
                reason = "Guest runtime health handshake completed"
            )
        } else if (!probeGuest) {
            AgentOnDeviceRuntimeLifecycle.cached(appContext)
        } else {
            AgentOnDeviceRuntimeLifecycle.inspectAfterBridgeProbe(appContext, bridgeHealth)
        }
        val reason = when {
            backend == AgentOnDeviceRuntimeBackend.QEMU_TCG && activeBridge == null -> lifecycle.reason.ifBlank {
                "Runtime engine and base pack are present, but the guest bridge is not connected"
            }
            backend == AgentOnDeviceRuntimeBackend.QEMU_TCG && bridgeHealth?.ready != true ->
                bridgeHealth?.reason.orEmpty().ifBlank { "The guest bridge is not healthy" }
            backend == AgentOnDeviceRuntimeBackend.QEMU_TCG -> "On-device Linux runtime is ready"
            !engineReady -> "Install the SignalASI QEMU engine"
            !baseReady -> "Install the linux-base runtime pack"
            else -> "On-device Linux runtime requires setup"
        }
        return AgentOnDeviceRuntimeStatus(
            backend = backend,
            backendReady = backend != AgentOnDeviceRuntimeBackend.NONE && bridgeHealth?.ready == true,
            reason = reason,
            architecture = architecture(),
            enginePath = engine.absolutePath,
            avfAdvertised = avf,
            packs = statuses,
            lifecyclePhase = lifecycle.phase,
            lifecycleReason = lifecycle.reason,
            lifecycleFailures = lifecycle.consecutiveFailures,
            lifecycleNextAttemptAtMillis = lifecycle.nextAttemptAtMillis
        )
    }

    fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
        return AgentWorkspaceScope.withLock(request.workspaceId) { executeLocked(request) }
    }

    fun workspaceStatus(workspaceId: String): AgentRuntimeWorkspaceStatus =
        AgentWorkspaceScope.withLock(workspaceId) {
            workspaceManager.workspaceStatus(workspaceId)
        }

    fun rollbackWorkspace(workspaceId: String, checkpointId: String): AgentRuntimeProjectSync =
        AgentWorkspaceScope.withLock(workspaceId) {
            workspaceManager.rollback(workspaceId, checkpointId, MAX_MANUAL_ROLLBACK_BYTES)
        }

    private fun executeLocked(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
        require(request.source.toByteArray().size <= MAX_SOURCE_BYTES) { "Runtime source exceeds the limit" }
        require(request.arguments.size <= MAX_ARGUMENTS) { "Runtime argument count exceeds the limit" }
        require(request.arguments.all { it.toByteArray().size <= MAX_ARGUMENT_BYTES }) {
            "A runtime argument exceeds the limit"
        }
        require(request.timeoutMillis in MIN_TIMEOUT_MILLIS..MAX_TIMEOUT_MILLIS) {
            "Runtime timeout is outside the allowed range"
        }
        require(request.artifactPaths.size <= MAX_ARTIFACTS) { "Too many runtime artifact paths" }
        require(request.requestId.matches(REQUEST_ID_PATTERN)) { "Runtime request id is invalid" }
        require(request.workspaceId.isNotBlank()) { "Runtime workspace id is required" }
        require(request.allowedNetworkDomains.size <= MAX_NETWORK_DOMAINS) { "Too many runtime network domains" }
        require(request.secretEnvironment.size <= MAX_SECRET_ENVIRONMENT_VALUES) { "Too many runtime secret environment values" }
        require(request.secretEnvironment.all { (name, value) ->
            SECRET_ENVIRONMENT_KEY.matches(name) && value.toByteArray(Charsets.UTF_8).size <= MAX_SECRET_ENVIRONMENT_VALUE_BYTES &&
                '\u0000' !in value
        }) { "Runtime secret environment is invalid" }
        request.resourceLimits.validated()
        if (request.cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
        return if (bridge == null) {
            AgentRuntimePackMountState.withStableGuest(appContext, ::packStatuses) {
                executeWithStableGuest(request)
            }
        } else {
            executeWithStableGuest(request)
        }
    }

    private fun executeWithStableGuest(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
        var runtimeLease = if (bridge == null) AgentOnDeviceRuntimeRecovery.acquire(appContext) else null
        runtimeLease?.lifecycle?.takeUnless { it.phase == AgentRuntimeLifecyclePhase.READY }?.let { lifecycle ->
            error(lifecycle.reason.ifBlank { "The on-device Linux runtime could not be started" })
        }
        val current = status()
        current.readinessFailure(request.language)?.let { failure ->
            error(failure)
        }
        var activeBridge = bridge ?: AgentOnDeviceRuntimeBridgeRegistry.current()
            ?: AgentOnDeviceRuntimeSupervisor.discover(appContext)
            ?: error("The on-device guest bridge is not connected")
        val prepared = workspaceManager.prepare(request)
        val checkpointId = automaticCheckpointId(request.requestId)
        val archiveToolBin = workspaceManager.installArchiveCompatibilityTools(prepared)
        val guestArchiveToolBin = guestArchiveToolPath(
            guestWorkspacePath = prepared.guestPath,
            relativeToolPath = archiveToolBin.relativeTo(prepared.directory).path
        )
        val normalizedRequest = request.copy(
            source = if (request.language == AgentRuntimeLanguage.SHELL) {
                AgentRuntimeShellBootstrap.wrap(request.source, guestArchiveToolBin)
            } else {
                request.source
            },
            guestWorkspacePath = prepared.guestPath
        )
        if (normalizedRequest.source != request.source) {
            prepared.sourceFile.writeText(normalizedRequest.source, Charsets.UTF_8)
        }
        val packVersions = current.packs.mapNotNull { pack ->
            pack.manifest?.version?.takeIf(String::isNotBlank)?.let { version -> pack.id to version }
        }.toMap()
        receiptStore.begin(normalizedRequest, packVersions)
        var committedCheckpoint: AgentRuntimeWorkspaceCheckpoint? = null
        return try {
            val bridgeStartedAt = SystemClock.elapsedRealtime()
            var rawResponse = activeBridge.execute(normalizedRequest)
            if (runtimeLease != null && AgentPersistentRuntimeFailurePolicy.requiresSystemRebuild(rawResponse)) {
                Log.w(
                    "SignalASIAgentRuntime",
                    "Persistent Linux userspace is damaged; rebuilding the system disk and retrying " +
                        "request=${normalizedRequest.requestId} workspace=${normalizedRequest.workspaceId}"
                )
                val rebuilt = AgentOnDeviceRuntimeRecovery.rebuildPersistentSystem(
                    appContext,
                    requireNotNull(runtimeLease),
                    runtimeRoot
                )
                check(rebuilt) { "The damaged Linux system disk could not be isolated" }
                runtimeLease = AgentOnDeviceRuntimeRecovery.acquire(appContext)
                check(runtimeLease.lifecycle.phase == AgentRuntimeLifecyclePhase.READY) {
                    runtimeLease.lifecycle.reason.ifBlank { "The rebuilt Linux runtime could not be started" }
                }
                activeBridge = AgentOnDeviceRuntimeBridgeRegistry.current()
                    ?: AgentOnDeviceRuntimeSupervisor.discover(appContext)
                    ?: error("The rebuilt Linux guest bridge is not connected")
                rawResponse = activeBridge.execute(normalizedRequest)
            }
            Log.i(
                "SignalASILatency",
                "agent_runtime stage=bridge_completed request=${normalizedRequest.requestId.take(8)} " +
                    "elapsed_ms=${SystemClock.elapsedRealtime() - bridgeStartedAt} exit_code=${rawResponse.exitCode}"
            )
            if (normalizedRequest.source != request.source) prepared.sourceFile.writeText(request.source, Charsets.UTF_8)
            val succeeded = rawResponse.exitCode == 0
            val artifacts = if (succeeded) {
                workspaceManager.collectArtifacts(prepared, normalizedRequest)
            } else {
                emptyList()
            }
            val commit = if (succeeded && normalizedRequest.workspaceMutationExpected) {
                workspaceManager.commitProject(
                    prepared = prepared,
                    byteLimit = normalizedRequest.resourceLimits.diskBytes,
                    checkpointId = checkpointId
                ).also { committedCheckpoint = it.checkpoint }
            } else {
                null
            }
            val durableProject = commit?.project
            val durableStatus = if (durableProject == null && !prepared.direct) {
                workspaceManager.workspaceStatus(normalizedRequest.workspaceId)
            } else {
                null
            }
            val disposition = if (succeeded) {
                if (normalizedRequest.workspaceMutationExpected) {
                    AgentRuntimeWorkspaceDisposition.COMMITTED
                } else {
                    AgentRuntimeWorkspaceDisposition.UNCHANGED
                }
            } else if (prepared.direct) {
                AgentRuntimeWorkspaceDisposition.PERSISTED_WITH_FAILURE
            } else {
                AgentRuntimeWorkspaceDisposition.FAILED_CANDIDATE
            }
            val response = rawResponse.copy(
                artifacts = artifacts,
                requestId = normalizedRequest.requestId,
                projectFileCount = durableProject?.fileCount ?: durableStatus?.fileCount ?: 0,
                projectBytes = durableProject?.totalBytes ?: durableStatus?.totalBytes ?: 0L,
                checkpointId = commit?.checkpoint?.checkpointId.orEmpty(),
                workspaceDisposition = disposition
            ).bounded()
            val receipt = receiptStore.complete(normalizedRequest.requestId, response, artifacts)
            runCatching {
                workspaceManager.markFinished(
                    prepared,
                    if (response.exitCode == 0) AgentRuntimeReceiptStatus.COMPLETED else AgentRuntimeReceiptStatus.FAILED
                )
            }
            if (receipt != null && receipt.verificationKind != AgentRuntimeVerificationKind.NONE && response.exitCode == 0) {
                runCatching { publicationGuard.recordVerification(receipt) }
                    .onFailure { error ->
                        Log.w(
                            "SignalASIAgentRuntime",
                            "Project publication verification was not recorded request=${normalizedRequest.requestId} " +
                                "workspace=${normalizedRequest.workspaceId}",
                            error
                        )
                    }
            }
            Log.i(
                "SignalASILatency",
                "agent_runtime stage=result_committed request=${normalizedRequest.requestId.take(8)} " +
                    "elapsed_ms=${SystemClock.elapsedRealtime() - bridgeStartedAt}"
            )
            response.copy(executionReceipt = receipt)
        } catch (error: Throwable) {
            val runtimeWasReset = if (error is AgentNativeToolTimeoutException && runtimeLease != null) {
                runCatching { AgentOnDeviceRuntimeRecovery.quarantine(appContext, runtimeLease) }
                    .onFailure { recoveryError -> error.addSuppressed(recoveryError) }
                    .getOrDefault(false)
            } else {
                false
            }
            Log.e(
                "SignalASIAgentRuntime",
                "Runtime result finalization failed request=${normalizedRequest.requestId} " +
                    "workspace=${normalizedRequest.workspaceId} exit_success=${committedCheckpoint != null} " +
                    "runtime_reset=$runtimeWasReset",
                error
            )
            if (normalizedRequest.source != request.source) {
                runCatching { prepared.sourceFile.writeText(request.source, Charsets.UTF_8) }
            }
            val rollback = committedCheckpoint?.let { checkpoint ->
                runCatching {
                    workspaceManager.rollback(
                        normalizedRequest.workspaceId,
                        checkpoint.checkpointId,
                        normalizedRequest.resourceLimits.diskBytes
                    )
                }
            }
            val disposition = when {
                prepared.direct -> AgentRuntimeWorkspaceDisposition.PERSISTED_WITH_FAILURE
                rollback == null -> AgentRuntimeWorkspaceDisposition.UNCHANGED
                rollback.isSuccess -> AgentRuntimeWorkspaceDisposition.ROLLED_BACK
                else -> {
                    rollback.exceptionOrNull()?.let(error::addSuppressed)
                    AgentRuntimeWorkspaceDisposition.ROLLBACK_FAILED
                }
            }
            receiptStore.fail(
                normalizedRequest.requestId,
                error,
                committedCheckpoint?.checkpointId.orEmpty(),
                disposition
            )
            runCatching {
                workspaceManager.markFinished(
                    prepared,
                    when (error) {
                        is AgentNativeToolCancelledException -> AgentRuntimeReceiptStatus.CANCELLED
                        is AgentNativeToolTimeoutException -> AgentRuntimeReceiptStatus.TIMED_OUT
                        else -> AgentRuntimeReceiptStatus.FAILED
                    }
                )
            }
            if (disposition == AgentRuntimeWorkspaceDisposition.ROLLBACK_FAILED) {
                throw IllegalStateException(
                    "On-device execution failed and its workspace could not be restored",
                    error
                )
            }
            throw error
        }
    }

    fun receipt(requestId: String): AgentRuntimeExecutionReceipt? = receiptStore.find(requestId)

    private fun qemuEngineFile(): File = File(appContext.applicationInfo.nativeLibraryDir, QEMU_ENGINE_FILE)

    internal fun packsDirectory(): File = packsRoot

    internal fun runtimeSocketFile(): File = File(appContext.filesDir, "$RUNTIME_DIRECTORY/guest.sock")

    internal fun runtimeBootstrapFiles(): AgentRuntimeBootstrapFiles {
        val engine = qemuEngineFile()
        check(engine.isFile) { "Install the SignalASI QEMU engine" }
        val base = inspectPackDirectory(
            directory = File(packsRoot, "linux-base"),
            expectedId = "linux-base",
            checkDependencies = true
        )
        check(base.state == AgentRuntimePackState.READY && base.manifest != null) {
            base.reason.ifBlank { "Install the linux-base runtime pack" }
        }
        val image = safeChild(File(packsRoot, "linux-base"), base.manifest.imageFile)
        check(image?.isFile == true) { "The linux-base runtime image is unavailable" }
        val runtimeRoot = File(appContext.filesDir, RUNTIME_DIRECTORY)
        val workspaces = File(appContext.filesDir, "agent-native-workspaces")
        check(runtimeRoot.mkdirs() || runtimeRoot.isDirectory) { "Runtime storage is unavailable" }
        check(workspaces.mkdirs() || workspaces.isDirectory) { "Runtime workspace storage is unavailable" }
        val systemDisk = AgentRuntimePersistentDisk.provision(runtimeRoot)
        val bootStore = AgentRuntimePackBootStore(appContext)
        val packAttachments = REQUIRED_PACKS.asSequence()
            .filterNot { it == "linux-base" }
            .map(::packStatus)
            .filter { it.state == AgentRuntimePackState.READY && it.manifest != null }
            .filterNot { status ->
                val manifest = requireNotNull(status.manifest)
                bootStore.isQuarantined(manifest.id, manifest.version)
            }
            .map { status ->
                val manifest = requireNotNull(status.manifest)
                val image = requireNotNull(safeChild(File(packsRoot, manifest.id), manifest.imageFile))
                AgentRuntimePackAttachment(
                    packId = manifest.id,
                    version = manifest.version,
                    capabilities = manifest.capabilities.toSet(),
                    imageFile = image
                )
            }
            .toList()
        return AgentRuntimeBootstrapFiles(
            engineFile = engine,
            baseImageFile = image,
            systemDiskFile = systemDisk,
            socketFile = runtimeSocketFile(),
            packsDirectory = packsRoot,
            workspacesDirectory = workspaces,
            architecture = Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
            packAttachments = packAttachments
        )
    }

    internal fun inspectPackDirectory(
        directory: File,
        expectedId: String? = null,
        checkDependencies: Boolean = true,
        forceIntegrityCheck: Boolean = false,
        verifyIntegrity: Boolean = true
    ): AgentRuntimePackStatus {
        val manifestFile = File(directory, MANIFEST_FILE)
        val fallbackId = expectedId ?: directory.name
        if (!manifestFile.isFile) return AgentRuntimePackStatus(fallbackId, AgentRuntimePackState.NOT_INSTALLED)
        val manifest = runCatching { decodeManifest(manifestFile.readText()) }.getOrNull()
            ?: return AgentRuntimePackStatus(fallbackId, AgentRuntimePackState.INVALID, "Invalid runtime pack manifest")
        if (expectedId != null && manifest.id != expectedId) {
            return AgentRuntimePackStatus(expectedId, AgentRuntimePackState.INVALID, "Runtime pack id does not match its directory", manifest)
        }
        if (manifest.id !in REQUIRED_PACKS || !PACK_ID_PATTERN.matches(manifest.id)) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INCOMPATIBLE, "Runtime pack id is not supported", manifest)
        }
        if (manifest.architecture !in supportedArchitectures()) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INCOMPATIBLE, "Runtime pack architecture is incompatible", manifest)
        }
        if (!VERSION_PATTERN.matches(manifest.version) || !SHA256_PATTERN.matches(manifest.imageSha256)) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack metadata is invalid", manifest)
        }
        if (manifest.formatVersion != SUPPORTED_PACK_FORMAT_VERSION ||
            manifest.minimumHostVersionCode > installedHostVersionCode() ||
            manifest.guestApiVersion != SUPPORTED_GUEST_API_VERSION
        ) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INCOMPATIBLE, "Runtime pack protocol is incompatible", manifest)
        }
        if (manifest.archiveSizeBytes !in 1..MAX_ARCHIVE_BYTES ||
            manifest.installedSizeBytes !in 1..MAX_INSTALLED_BYTES ||
            manifest.license.isBlank() || manifest.license.length > MAX_LICENSE_CHARS ||
            manifest.capabilities.distinct().size != manifest.capabilities.size ||
            manifest.capabilities.any { !CAPABILITY_PATTERN.matches(it) } ||
            manifest.dependencies.distinct().size != manifest.dependencies.size ||
            manifest.dependencies.any { it !in REQUIRED_PACKS || it == manifest.id }
        ) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack metadata is incomplete", manifest)
        }
        val missingCapabilities = REQUIRED_PACK_CAPABILITIES[manifest.id].orEmpty() - manifest.capabilities.toSet()
        if (missingCapabilities.isNotEmpty()) {
            return AgentRuntimePackStatus(
                manifest.id,
                AgentRuntimePackState.INVALID,
                "Runtime pack capabilities are incomplete: ${missingCapabilities.sorted().joinToString()}",
                manifest
            )
        }
        if (manifest.signature.isBlank() || !SHA256_PATTERN.matches(manifest.signatureKeyId)) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack signature is missing", manifest)
        }
        if (!signatureVerifier.verify(manifest)) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack signature is not trusted", manifest)
        }
        val image = safeChild(directory, manifest.imageFile)
            ?: return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack image path is unsafe", manifest)
        if (!image.isFile) return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack image is missing", manifest)
        if (manifest.installedSizeBytes <= 0L || image.length() > manifest.installedSizeBytes + INSTALL_SIZE_TOLERANCE_BYTES) {
            return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack installed size is invalid", manifest)
        }
        if (verifyIntegrity) {
            val actualHash = sha256(image, manifest.imageSha256, forceIntegrityCheck)
            if (!actualHash.equals(manifest.imageSha256, ignoreCase = true)) {
                return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INVALID, "Runtime pack image integrity check failed", manifest)
            }
        }
        if (checkDependencies) {
            val missingDependency = manifest.dependencies.firstOrNull { dependency ->
                dependency != manifest.id &&
                    packStatusWithoutDependencies(dependency, verifyIntegrity).state != AgentRuntimePackState.READY
            }
            if (missingDependency != null) {
                return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.INCOMPATIBLE, "Missing dependency: $missingDependency", manifest)
            }
        }
        return AgentRuntimePackStatus(manifest.id, AgentRuntimePackState.READY, manifest = manifest)
    }

    internal fun clearIntegrityCache(packId: String) {
        val prefix = "$packId|"
        integrityCache.edit().also { editor ->
            integrityCache.all.keys.filter { it.startsWith(prefix) }.forEach(editor::remove)
        }.apply()
    }

    private fun packStatus(
        id: String,
        verifyIntegrity: Boolean = true
    ): AgentRuntimePackStatus {
        val status = inspectPackDirectory(
            directory = File(packsRoot, id),
            expectedId = id,
            verifyIntegrity = verifyIntegrity
        )
        val manifest = status.manifest
        return if (
            status.state == AgentRuntimePackState.READY && manifest != null &&
            AgentRuntimePackBootStore(appContext).isQuarantined(manifest.id, manifest.version)
        ) {
            status.copy(
                state = AgentRuntimePackState.INCOMPATIBLE,
                reason = "Disabled after preventing the phone Linux guest from starting"
            )
        } else status
    }

    private fun packStatusWithoutDependencies(
        id: String,
        verifyIntegrity: Boolean = true
    ): AgentRuntimePackStatus {
        val directory = File(packsRoot, id)
        return inspectPackDirectory(
            directory,
            expectedId = id,
            checkDependencies = false,
            verifyIntegrity = verifyIntegrity
        )
    }

    internal fun decodeManifest(raw: String): AgentRuntimePackManifest {
        require(raw.toByteArray().size <= MAX_MANIFEST_BYTES) { "Runtime manifest is too large" }
        val json = JSONObject(raw)
        return AgentRuntimePackManifest(
            id = json.getString("id").take(MAX_ID_CHARS),
            version = json.getString("version"),
            architecture = json.getString("architecture").lowercase(Locale.ROOT),
            imageFile = json.getString("image_file"),
            imageSha256 = json.getString("image_sha256").lowercase(Locale.ROOT),
            capabilities = json.optJSONArray("capabilities").strings(MAX_CAPABILITIES),
            dependencies = json.optJSONArray("dependencies").strings(MAX_DEPENDENCIES),
            installedSizeBytes = json.optLong("installed_size_bytes", 0L).coerceAtLeast(0L),
            license = json.optString("license"),
            signatureKeyId = json.optString("signature_key_id"),
            signature = json.optString("signature"),
            formatVersion = json.optInt("format_version", 0),
            archiveSizeBytes = json.optLong("archive_size_bytes", 0L).coerceAtLeast(0L),
            minimumHostVersionCode = json.optLong("minimum_host_version_code", 1L).coerceAtLeast(1L),
            guestApiVersion = json.optInt("guest_api_version", 0)
        )
    }

    @Suppress("DEPRECATION")
    private fun installedHostVersionCode(): Long = appContext.packageManager
        .getPackageInfo(appContext.packageName, 0)
        .let { info -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong() }

    private fun safeChild(root: File, relative: String): File? {
        if (relative.isBlank() || File(relative).isAbsolute) return null
        val canonicalRoot = root.canonicalFile
        val candidate = File(canonicalRoot, relative).canonicalFile
        return candidate.takeIf { it.path.startsWith(canonicalRoot.path + File.separator) }
    }

    internal fun supportedArchitectures(): Set<String> = Build.SUPPORTED_ABIS.flatMapTo(linkedSetOf()) { abi ->
        when (abi.lowercase(Locale.ROOT)) {
            "arm64-v8a" -> listOf("arm64-v8a", "aarch64")
            "x86_64" -> listOf("x86_64", "amd64")
            else -> listOf(abi.lowercase(Locale.ROOT))
        }
    }

    private fun sha256(file: File, expectedHash: String, force: Boolean = false): String {
        val cacheKey = "${file.parentFile?.name.orEmpty()}|${file.canonicalPath}"
        val cacheStamp = "${file.length()}:${file.lastModified()}:${expectedHash.lowercase(Locale.ROOT)}"
        if (!force) {
            integrityCache.getString(cacheKey, null)?.let { cached ->
                val separator = cached.indexOf('|')
                if (separator > 0 && cached.substring(0, separator) == cacheStamp) {
                    return cached.substring(separator + 1)
                }
            }
        }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }.also { actual ->
            integrityCache.edit().putString(cacheKey, "$cacheStamp|$actual").apply()
        }
    }

    private fun AgentRuntimeExecutionResponse.bounded(): AgentRuntimeExecutionResponse = copy(
        stdout = stdout.take(MAX_OUTPUT_CHARS),
        stderr = stderr.take(MAX_OUTPUT_CHARS),
        artifacts = artifacts.take(MAX_ARTIFACTS)
    )

    private fun automaticCheckpointId(requestId: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(requestId.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return "pre-${digest.take(24)}"
    }

    private fun JSONArray?.strings(limit: Int): List<String> = buildList {
        val source = this@strings ?: return@buildList
        for (index in 0 until minOf(source.length(), limit)) {
            source.optString(index).takeIf(String::isNotBlank)?.let(::add)
        }
    }

    companion object {
        val REQUIRED_PACKS = listOf(
            "linux-base",
            "python-uv",
            "node-js",
            "go",
            "rust",
            "cpp",
            "java",
            "gradle",
            "android-sdk",
            "browser-automation",
            "ffmpeg"
        )
        val REQUIRED_PACK_CAPABILITIES: Map<String, Set<String>> = AgentRuntimeLanguage.entries
            .groupBy(AgentRuntimeLanguage::requiredPack)
            .mapValues { (_, languages) ->
                languages.mapTo(linkedSetOf(), AgentRuntimeLanguage::requiredCapability)
            } + mapOf(
                "gradle" to setOf("gradle.execute"),
                "android-sdk" to setOf("android.build", "android.package", "android.sign")
            )
        private const val RUNTIME_DIRECTORY = "agent-runtime"
        private const val PACKS_DIRECTORY = "packs"
        private const val MANIFEST_FILE = "manifest.json"
        private const val QEMU_ENGINE_FILE = "libsignalasi_qemu.so"
        private const val AVF_FEATURE = "android.software.virtualization_framework"
        private const val INTEGRITY_CACHE = "signalasi_runtime_integrity_cache_v1"
        private const val MAX_MANIFEST_BYTES = 64 * 1024
        private const val MAX_SOURCE_BYTES = 256 * 1024
        private const val MAX_ARGUMENTS = 256
        private const val MAX_ARGUMENT_BYTES = 8 * 1024
        private const val MAX_ARTIFACTS = 32
        private const val MAX_NETWORK_DOMAINS = 64
        private const val MAX_SECRET_ENVIRONMENT_VALUES = 32
        private const val MAX_SECRET_ENVIRONMENT_VALUE_BYTES = 4 * 1024
        private const val MAX_OUTPUT_CHARS = 512 * 1024
        private const val MAX_MANUAL_ROLLBACK_BYTES = 2L * 1024L * 1024L * 1024L
        private const val MAX_ID_CHARS = 80
        private const val MAX_CAPABILITIES = 128
        private const val MAX_DEPENDENCIES = 32
        private const val MAX_LICENSE_CHARS = 256
        private const val MAX_ARCHIVE_BYTES = 6L * 1024L * 1024L * 1024L
        private const val MAX_INSTALLED_BYTES = 12L * 1024L * 1024L * 1024L
        private const val INSTALL_SIZE_TOLERANCE_BYTES = 16L * 1024L * 1024L
        private const val SUPPORTED_PACK_FORMAT_VERSION = 1
        private const val SUPPORTED_GUEST_API_VERSION = 1
        private const val MIN_TIMEOUT_MILLIS = 100L
        private const val MAX_TIMEOUT_MILLIS = 30 * 60_000L
        private val VERSION_PATTERN = Regex("[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?")
        private val SHA256_PATTERN = Regex("[0-9a-f]{64}")
        private val PACK_ID_PATTERN = Regex("[a-z0-9][a-z0-9._-]{0,79}")
        private val REQUEST_ID_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
        private val SECRET_ENVIRONMENT_KEY = Regex("[A-Z_][A-Z0-9_]{0,63}")
        private val CAPABILITY_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
    }
}

internal object AgentPersistentRuntimeFailurePolicy {
    fun requiresSystemRebuild(response: AgentRuntimeExecutionResponse): Boolean {
        if (response.exitCode !in setOf(126, 127)) return false
        val diagnostic = response.stderr.lowercase()
        return "input/output error" in diagnostic &&
            ("chroot" in diagnostic || "/bin/sh" in diagnostic || "rootfs" in diagnostic)
    }
}

object AgentOnDeviceRuntimeTools {
    const val STATUS = "signalasi.runtime.status"
    const val WORKSPACE_STATUS = "signalasi.runtime.workspace.status"
    const val WORKSPACE_ROLLBACK = "signalasi.runtime.workspace.rollback"
    const val LIST_PACKS = "signalasi.runtime.packs.list"
    const val INSTALL_PACK = "signalasi.runtime.packs.install"
    const val EXECUTE = "signalasi.runtime.execute"

    val toolIds = setOf(
        STATUS,
        WORKSPACE_STATUS,
        WORKSPACE_ROLLBACK,
        LIST_PACKS,
        INSTALL_PACK,
        EXECUTE
    )

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val manager = AgentOnDeviceRuntimeManager(context.applicationContext)
        return listOf(
            AgentNativeToolDefinition(
                descriptor = descriptor(
                    id = STATUS,
                    title = "Inspect on-device runtime",
                    description = "Reports Android-local Linux backend, language, toolchain, and media-pack readiness.",
                    input = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                    risk = AgentNativeToolRisk.LOW,
                    availability = AgentNativeToolAvailability.AVAILABLE
                ),
                executor = AgentNativeToolExecutor {
                    val status = manager.cachedStatus()
                    AgentNativeToolExecutionResult.success(runtimeStatusOutput(status), "On-device runtime inspected")
                },
                executorId = "signalasi.android_runtime_broker"
            ),
            AgentNativeToolDefinition(
                descriptor = descriptor(
                    id = WORKSPACE_STATUS,
                    title = "Inspect the on-device project workspace",
                    description = "Reports the current conversation project size and durable recovery checkpoints without exposing host paths.",
                    input = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                    risk = AgentNativeToolRisk.LOW,
                    availability = AgentNativeToolAvailability.AVAILABLE
                ),
                executor = AgentNativeToolExecutor { invocation ->
                    val status = manager.workspaceStatus(invocationWorkspaceId(invocation))
                    AgentNativeToolExecutionResult.success(
                        status.publicValue(),
                        "On-device project workspace inspected"
                    )
                },
                executorId = "signalasi.android_runtime_workspace"
            ),
            AgentNativeToolDefinition(
                descriptor = descriptor(
                    id = LIST_PACKS,
                    title = "List on-device runtime packs",
                    description = "Lists Android-local Linux, language, FFmpeg, and toolchain pack state.",
                    input = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                    risk = AgentNativeToolRisk.LOW,
                    availability = AgentNativeToolAvailability.AVAILABLE
                ),
                executor = AgentNativeToolExecutor {
                    val status = manager.status()
                    AgentNativeToolExecutionResult.success(
                        mapOf("packs" to status.packs.map(::packOutput)),
                        "On-device runtime packs listed"
                    )
                },
                executorId = "signalasi.android_runtime_broker"
            ),
            runtimePackInstallDefinition(context.applicationContext, manager),
            AgentNativeToolDefinition(
                descriptor = descriptor(
                    id = WORKSPACE_ROLLBACK,
                    title = "Restore an on-device project checkpoint",
                    description = "Atomically restores this conversation project from a durable checkpoint after an execution failure or unwanted change.",
                    input = AgentNativeJsonSchema.objectSchema(
                        properties = mapOf(
                            "checkpoint_id" to AgentNativeJsonSchema.string(maxLength = 128)
                        ),
                        required = setOf("checkpoint_id"),
                        additionalProperties = false
                    ),
                    risk = AgentNativeToolRisk.LOW,
                    availability = AgentNativeToolAvailability.AVAILABLE
                ),
                executor = AgentNativeToolExecutor { invocation ->
                    val checkpointId = invocation.input["checkpoint_id"]?.toString().orEmpty()
                    runCatching {
                        manager.rollbackWorkspace(invocationWorkspaceId(invocation), checkpointId)
                    }.fold(
                        onSuccess = { restored ->
                            AgentNativeToolExecutionResult.success(
                                mapOf(
                                    "checkpoint_id" to checkpointId,
                                    "workspace_file_count" to restored.fileCount,
                                    "workspace_bytes" to restored.totalBytes,
                                    "workspace_disposition" to AgentRuntimeWorkspaceDisposition.ROLLED_BACK.wireValue
                                ),
                                "On-device project checkpoint restored"
                            )
                        },
                        onFailure = { error ->
                            AgentNativeToolExecutionResult.failure(
                                "runtime_workspace_rollback_failed",
                                error.message ?: "On-device project checkpoint could not be restored"
                            )
                        }
                    )
                },
                executorId = "signalasi.android_runtime_workspace",
                provenanceMetadata = mapOf("operation" to "atomic_checkpoint_restore")
            ),
            AgentNativeToolDefinition(
                descriptor = descriptor(
                    id = EXECUTE,
                    title = "Execute in the on-device Linux system",
                    description = "Runs shell, language, dependency installation, build, test, browser, or media work as root in the persistent Android-local Linux system. Files and artifacts remain available to later turns.",
                    input = executionInputSchema(),
                    risk = AgentNativeToolRisk.LOW,
                    timeoutMillis = 30 * 60_000L,
                    availability = executionAvailability(manager)
                ),
                executor = AgentNativeToolExecutor { invocation ->
                    val language = AgentRuntimeLanguage.entries.firstOrNull {
                        it.wireValue == invocation.input["language"]?.toString()
                    } ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                        "invalid_runtime_language", "Runtime language is invalid"
                    )
                    val request = AgentRuntimeExecutionRequest(
                        language = language,
                        source = invocation.input["source"]?.toString().orEmpty(),
                        arguments = invocation.input.stringList("arguments"),
                        timeoutMillis = (invocation.input["timeout_ms"] as? Number)?.toLong() ?: 60_000L,
                        networkEnabled = invocation.input["network_enabled"] as? Boolean ?: false,
                        allowedNetworkDomains = invocation.input.stringList("allowed_network_domains"),
                        artifactPaths = invocation.input.stringList("artifact_paths"),
                        verificationKind = AgentRuntimeVerificationKind.fromWireValue(
                            invocation.input["verification_kind"]?.toString().orEmpty()
                        ),
                        workspaceId = invocationWorkspaceId(invocation),
                        requestId = invocation.context.invocationId,
                        cancellationToken = invocation.cancellationToken,
                        progressListener = { progress ->
                            invocation.reportProgress(
                                stage = progress.stage,
                                message = progress.message,
                                percent = progress.percent,
                                sequence = progress.sequence,
                                timestampEpochMillis = progress.timestampMillis
                            )
                        }
                    )
                    runCatching { manager.execute(request) }.fold(
                        onSuccess = { response ->
                            Log.i(
                                "SignalASILatency",
                                "agent_runtime stage=tool_executor_return request=${request.requestId.take(8)}"
                            )
                            runtimeExecutionResult(response)
                        },
                        onFailure = { error ->
                            Log.e(
                                "SignalASIAgentRuntime",
                                "On-device runtime request failed before returning request=${request.requestId} " +
                                    "workspace=${request.workspaceId}",
                                error
                            )
                            val evidence = manager.receipt(request.requestId)?.toEvidenceMap()
                            val timedOut = error is AgentNativeToolTimeoutException
                            AgentNativeToolExecutionResult(
                                output = evidence?.let { mapOf("execution_receipt" to it) }.orEmpty(),
                                error = AgentNativeToolError(
                                    code = "on_device_runtime_failed",
                                    message = if (timedOut) {
                                        "On-device Linux timed out and its guest was reset. Retry the action in the same workspace."
                                    } else {
                                        error.message ?: "On-device runtime failed"
                                    },
                                    retryable = timedOut,
                                    details = evidence.orEmpty()
                                )
                            )
                        }
                    )
                },
                executorId = "signalasi.android_runtime_broker",
                provenanceMetadata = mapOf(
                    "platform" to "android",
                    "runtime" to "linux_guest",
                    "execution_principal" to "root",
                    "network_default" to "enabled"
                ),
                availabilityProvider = AgentNativeToolAvailabilityProvider { executionAvailability(manager) }
            )
        )
    }

    internal fun runtimeExecutionResult(response: AgentRuntimeExecutionResponse): AgentNativeToolExecutionResult {
        val output = runtimeExecutionOutput(response)
        if (response.exitCode == 0) {
            return AgentNativeToolExecutionResult.success(output, "On-device runtime completed")
        }
        return AgentNativeToolExecutionResult(
            output = output,
            message = "On-device runtime exited with ${response.exitCode}",
            error = AgentNativeToolError(
                code = "on_device_runtime_nonzero_exit",
                message = "On-device runtime exited with ${response.exitCode}",
                retryable = false,
                details = response.executionReceipt?.toEvidenceMap().orEmpty()
            )
        )
    }

    private fun runtimePackInstallDefinition(
        context: Context,
        manager: AgentOnDeviceRuntimeManager
    ): AgentNativeToolDefinition = AgentNativeToolDefinition(
        descriptor = descriptor(
            id = INSTALL_PACK,
            title = "Install a trusted on-device runtime pack",
            description = "Downloads, verifies, and installs a signed Linux, language, or media runtime pack and its dependencies.",
            input = AgentNativeJsonSchema.objectSchema(
                properties = mapOf(
                    "pack_id" to AgentNativeJsonSchema.string(enumValues = AgentOnDeviceRuntimeManager.REQUIRED_PACKS)
                ),
                required = setOf("pack_id"),
                additionalProperties = false
            ),
            risk = AgentNativeToolRisk.LOW,
            timeoutMillis = 30 * 60_000L,
            availability = AgentNativeToolAvailability.AVAILABLE
        ),
        executor = AgentNativeToolExecutor { invocation ->
            val requestedPack = invocation.input["pack_id"]?.toString().orEmpty()
            installRuntimePack(context, manager, invocation, requestedPack)
        },
        executorId = "signalasi.android_runtime_pack_manager",
        provenanceMetadata = mapOf("verification" to "signed_catalog_and_pack")
    )

    internal fun installRuntimePack(
        context: Context,
        manager: AgentOnDeviceRuntimeManager,
        invocation: AgentNativeToolInvocation,
        requestedPack: String
    ): AgentNativeToolExecutionResult {
        if (requestedPack !in AgentOnDeviceRuntimeManager.REQUIRED_PACKS) {
            return AgentNativeToolExecutionResult.failure(
                "invalid_runtime_pack", "Runtime pack is invalid"
            )
        }
        readyRuntimePackInstallOutput(requestedPack, manager.packStatuses())?.let { output ->
            return AgentNativeToolExecutionResult.success(
                output,
                "Trusted runtime pack is already ready"
            )
        }
        val catalogManager = AgentRuntimePackCatalogManager(context)
        return try {
            invocation.reportProgress("catalog", "Refreshing the trusted runtime catalog")
            catalogManager.refresh(cancellationToken = invocation.cancellationToken)
            val entry = catalogManager.cachedCompatible().firstOrNull {
                it.packId == requestedPack && it.architecture == manager.architecture()
            } ?: error("No compatible signed runtime pack is available for $requestedPack")
            val plan = catalogManager.installationPlan(entry)
            val installed = mutableListOf<Map<String, Any?>>()
            plan.forEachIndexed { index, item ->
                if (invocation.cancellationToken.isCancellationRequested) {
                    throw AgentNativeToolCancelledException()
                }
                val current = manager.packStatuses().first { it.id == item.packId }
                if (current.state == AgentRuntimePackState.READY && current.manifest?.version == item.version) {
                    installed += mapOf(
                        "pack_id" to item.packId,
                        "version" to item.version,
                        "state" to "already_ready"
                    )
                } else {
                    invocation.reportProgress(
                        "download",
                        "Downloading ${item.packId}",
                        (index * 100) / plan.size.coerceAtLeast(1)
                    )
                    val result = catalogManager.downloadAndInstall(
                        item,
                        invocation.cancellationToken,
                        onDownloadProgress = { progress ->
                            val percent = if (progress.totalBytes > 0L) {
                                ((progress.downloadedBytes * 100L) / progress.totalBytes)
                                    .toInt().coerceIn(0, 100)
                            } else null
                            invocation.reportProgress("download", "Downloading ${item.packId}", percent)
                        },
                        onInstallProgress = { progress ->
                            invocation.reportProgress(
                                "install",
                                "Installing ${item.packId}: ${progress.stage.name.lowercase(Locale.ROOT)}"
                            )
                        }
                    )
                    installed += mapOf(
                        "pack_id" to result.packId,
                        "version" to result.version,
                        "state" to result.state.wireValue,
                        "installed_bytes" to result.installedBytes
                    )
                }
            }
            AgentNativeToolExecutionResult.success(
                mapOf("requested_pack" to requestedPack, "installed" to installed),
                "Trusted runtime pack is ready"
            )
        } catch (error: AgentNativeToolCancelledException) {
            throw error
        } catch (error: Throwable) {
            AgentNativeToolExecutionResult.failure(
                "runtime_pack_install_failed",
                error.message ?: "Runtime pack installation failed"
            )
        } finally {
            catalogManager.close()
        }
    }

    internal fun readyRuntimePackInstallOutput(
        requestedPack: String,
        statuses: List<AgentRuntimePackStatus>
    ): AgentNativeJsonObject? {
        val ready = statuses.firstOrNull { status ->
            status.id == requestedPack &&
                status.state == AgentRuntimePackState.READY &&
                status.manifest != null
        } ?: return null
        return mapOf(
            "requested_pack" to requestedPack,
            "installed" to listOf(
                mapOf(
                    "pack_id" to requestedPack,
                    "version" to ready.manifest!!.version,
                    "state" to "already_ready"
                )
            )
        )
    }

    private fun runtimeExecutionOutput(response: AgentRuntimeExecutionResponse): AgentNativeJsonObject = buildMap {
        put("exit_code", response.exitCode)
        put("stdout", response.stdout)
        put("stderr", response.stderr)
        put("duration_ms", response.durationMillis)
        put("workspace_file_count", response.projectFileCount)
        put("workspace_bytes", response.projectBytes)
        put("checkpoint_id", response.checkpointId)
        put("workspace_disposition", response.workspaceDisposition.wireValue)
        put("artifacts", response.artifacts)
        response.executionReceipt?.let { put("execution_receipt", it.toEvidenceMap()) }
    }

    private fun descriptor(
        id: String,
        title: String,
        description: String,
        input: AgentNativeJsonSchema,
        risk: AgentNativeToolRisk,
        timeoutMillis: Long = 30_000L,
        availability: AgentNativeToolAvailability
    ) = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = title,
        description = description,
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = input,
        outputSchema = AgentNativeJsonSchema.any(),
        risk = risk,
        capabilities = setOf("runtime.android_local", "runtime.linux", "runtime.full_access", "runtime.root"),
        timeoutMillis = timeoutMillis,
        idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT,
        availability = availability
    )

    private fun executionInputSchema() = AgentNativeJsonSchema.objectSchema(
        properties = mapOf(
            "language" to AgentNativeJsonSchema.string(enumValues = AgentRuntimeLanguage.entries.map { it.wireValue }),
            "source" to AgentNativeJsonSchema.string(maxLength = 256 * 1024),
            "arguments" to AgentNativeJsonSchema.array(AgentNativeJsonSchema.string(maxLength = 8 * 1024), maxItems = 256),
            "timeout_ms" to AgentNativeJsonSchema.integer(100, 30 * 60_000L),
            "network_enabled" to AgentNativeJsonSchema.boolean(),
            "allowed_network_domains" to AgentNativeJsonSchema.array(
                AgentNativeJsonSchema.string(maxLength = 253),
                maxItems = 64
            ),
            "artifact_paths" to AgentNativeJsonSchema.array(
                AgentNativeJsonSchema.string(maxLength = 1_024),
                maxItems = 32
            ),
            "verification_kind" to AgentNativeJsonSchema.string(
                enumValues = AgentRuntimeVerificationKind.entries.map { it.wireValue }
            )
        ),
        required = setOf("language", "source"),
        additionalProperties = false
    )

    private fun executionAvailability(manager: AgentOnDeviceRuntimeManager): AgentNativeToolAvailability {
        return executionAvailability(manager.status())
    }

    internal fun executionAvailability(status: AgentOnDeviceRuntimeStatus): AgentNativeToolAvailability {
        return if (status.backend != AgentOnDeviceRuntimeBackend.NONE) {
            AgentNativeToolAvailability.AVAILABLE
        } else AgentNativeToolAvailability(
            AgentNativeToolAvailabilityStatus.REQUIRES_SETUP,
            status.reason,
            System.currentTimeMillis()
        )
    }

    private fun invocationWorkspaceId(invocation: AgentNativeToolInvocation): String =
        invocation.context.attributes["workspace_id"].orEmpty()
            .ifBlank { invocation.context.turnId }
            .ifBlank { invocation.context.conversationId }
            .ifBlank { invocation.context.invocationId }

    private fun runtimeStatusOutput(status: AgentOnDeviceRuntimeStatus): Map<String, Any?> = mapOf(
        "backend" to status.backend.wireValue,
        "backend_ready" to status.backendReady,
        "reason" to status.reason,
        "lifecycle" to mapOf(
            "phase" to status.lifecyclePhase.wireValue,
            "reason" to status.lifecycleReason,
            "consecutive_failures" to status.lifecycleFailures,
            "next_attempt_at_millis" to status.lifecycleNextAttemptAtMillis
        ),
        "architecture" to status.architecture,
        "avf_advertised" to status.avfAdvertised,
        "linux_system" to persistentLinuxSystemOutput(status),
        "packs" to status.packs.map(::packOutput),
        "languages" to AgentRuntimeLanguage.entries.map { language ->
            mapOf(
                "id" to language.wireValue,
                "required_pack" to language.requiredPack,
                "required_capability" to language.requiredCapability,
                "ready" to status.languageReady(language)
            )
        }
    )

    internal fun persistentLinuxSystemOutput(status: AgentOnDeviceRuntimeStatus): Map<String, Any?> {
        val baseVersion = status.packs.firstOrNull { it.id == "linux-base" }
            ?.manifest?.version.orEmpty()
        val packageManagerReady = status.backendReady &&
            baseVersion.isNotBlank() &&
            AgentEmbeddedRuntimeBootstrap.compareVersions(baseVersion, "1.3.3") >= 0
        return mapOf(
            "distribution" to "Debian 13",
            "execution_principal" to "root",
            "persistent" to true,
            "package_managers" to listOf("apt", "dpkg"),
            "package_manager_ready" to packageManagerReady,
            "base_version" to baseVersion
        )
    }

    private fun packOutput(pack: AgentRuntimePackStatus): Map<String, Any?> = mapOf(
        "id" to pack.id,
        "state" to pack.state.wireValue,
        "reason" to pack.reason,
        "version" to pack.manifest?.version.orEmpty(),
        "architecture" to pack.manifest?.architecture.orEmpty(),
        "capabilities" to pack.manifest?.capabilities.orEmpty(),
        "installed_size_bytes" to (pack.manifest?.installedSizeBytes ?: 0L),
        "license" to pack.manifest?.license.orEmpty()
    )

    private fun Map<String, Any?>.stringList(key: String): List<String> =
        (this[key] as? Iterable<*>)?.mapNotNull { it?.toString() }.orEmpty()
}
