package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal const val DESKTOP_SCREENSHOT_BYTE_LIMIT = 100_000
internal const val DESKTOP_SCREENSHOT_STREAM_MIN_FPS = 1
internal const val DESKTOP_SCREENSHOT_STREAM_MAX_FPS = 3

internal object DesktopScreenshotStreamPolicy {
    fun normalizeFps(fps: Int): Int? =
        fps.takeIf { it in DESKTOP_SCREENSHOT_STREAM_MIN_FPS..DESKTOP_SCREENSHOT_STREAM_MAX_FPS }

    fun intervalMillis(fps: Int): Long =
        1_000L / requireNotNull(normalizeFps(fps))
}

data class DesktopControlAuthorization(
    val authorizationId: String,
    val appInstanceId: String,
    val appName: String,
    val appPlatform: String,
    val phoneName: String,
    val phoneFingerprint: String,
    val grantSource: String,
    val accessProfile: String,
    val accessScopes: List<String>,
    val grantedAt: Long,
    val lastUsedAt: Long,
    val revokedAt: Long,
    val revokeReason: String,
    val status: String,
    val allowedTools: List<String>,
    val desktopSessionId: String,
    val desktopSessionExpiresAt: Long
)

internal fun parseDesktopControlAuthorization(json: JSONObject?): DesktopControlAuthorization? {
    val source = json ?: return null
    val status = source.optString("status")
    val id = source.optString("authorization_id")
    if (id.isBlank() && status != "pending") return null
    val tools = source.optJSONArray("allowed_tools") ?: JSONArray()
    return DesktopControlAuthorization(
        authorizationId = id,
        appInstanceId = source.optString("app_instance_id"),
        appName = source.optString("app_name", source.optString("phone_name")),
        appPlatform = source.optString("app_platform", source.optString("platform")),
        phoneName = source.optString("phone_name"),
        phoneFingerprint = source.optString(
            "app_identity_fingerprint",
            source.optString("phone_fingerprint")
        ),
        grantSource = source.optString("grant_source"),
        accessProfile = source.optString("access_profile"),
        accessScopes = source.optJSONArray("access_scopes").let { scopes ->
            buildList {
                if (scopes != null) {
                    for (index in 0 until scopes.length()) add(scopes.optString(index))
                }
            }
        },
        grantedAt = source.optLong("granted_at"),
        lastUsedAt = source.optLong("last_used_at"),
        revokedAt = source.optLong("revoked_at"),
        revokeReason = source.optString("revoke_reason"),
        status = status,
        allowedTools = buildList {
            for (index in 0 until tools.length()) add(tools.optString(index))
        },
        desktopSessionId = source.optString("desktop_session_id"),
        desktopSessionExpiresAt = source.optLong("desktop_session_expires_at")
    )
}

data class DesktopControlScreenshot(
    val jpegBytes: ByteArray,
    val width: Int,
    val height: Int,
    val originalWidth: Int,
    val originalHeight: Int,
    val capturedAt: Long
)

data class DesktopSurfaceBounds(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int
)

data class DesktopDisplaySurface(
    val displayId: String,
    val name: String,
    val bounds: DesktopSurfaceBounds,
    val primary: Boolean
)

data class DesktopWindowSurface(
    val windowId: String,
    val title: String,
    val displayId: String,
    val bounds: DesktopSurfaceBounds,
    val foreground: Boolean,
    val minimized: Boolean
)

data class DesktopSurfaceSelection(
    val displayId: String,
    val windowId: String,
    val targetKind: String
)

data class DesktopSurfaceCatalog(
    val displays: List<DesktopDisplaySurface>,
    val windows: List<DesktopWindowSurface>,
    val selection: DesktopSurfaceSelection,
    val targetTitle: String,
    val targetBounds: DesktopSurfaceBounds
)

private fun parseDesktopSurfaceBounds(source: JSONObject?): DesktopSurfaceBounds {
    val bounds = source ?: JSONObject()
    return DesktopSurfaceBounds(
        left = bounds.optInt("left"),
        top = bounds.optInt("top"),
        width = bounds.optInt("width").coerceAtLeast(0),
        height = bounds.optInt("height").coerceAtLeast(0)
    )
}

internal fun parseDesktopSurfaceCatalog(source: JSONObject?): DesktopSurfaceCatalog? {
    val root = source ?: return null
    if (root.optString("surface_contract") != "signalasi.desktop-surfaces/1.0") return null
    val displayRows = root.optJSONArray("displays") ?: JSONArray()
    val windowRows = root.optJSONArray("windows") ?: JSONArray()
    val displays = buildList {
        for (index in 0 until minOf(displayRows.length(), 16)) {
            val item = displayRows.optJSONObject(index) ?: continue
            val displayId = item.optString("display_id").take(120)
            if (displayId.isBlank()) continue
            add(DesktopDisplaySurface(
                displayId = displayId,
                name = item.optString("name").take(120),
                bounds = parseDesktopSurfaceBounds(item.optJSONObject("bounds")),
                primary = item.optBoolean("primary")
            ))
        }
    }
    if (displays.isEmpty()) return null
    val displayIds = displays.mapTo(mutableSetOf()) { it.displayId }
    val windows = buildList {
        for (index in 0 until minOf(windowRows.length(), 100)) {
            val item = windowRows.optJSONObject(index) ?: continue
            val windowId = item.optString("window_id").take(120)
            val displayId = item.optString("display_id").take(120)
            if (windowId.isBlank() || displayId !in displayIds) continue
            add(DesktopWindowSurface(
                windowId = windowId,
                title = item.optString("title").take(500),
                displayId = displayId,
                bounds = parseDesktopSurfaceBounds(item.optJSONObject("bounds")),
                foreground = item.optBoolean("foreground"),
                minimized = item.optBoolean("minimized")
            ))
        }
    }
    val selection = root.optJSONObject("selection") ?: JSONObject()
    val target = root.optJSONObject("target") ?: JSONObject()
    return DesktopSurfaceCatalog(
        displays = displays,
        windows = windows,
        selection = DesktopSurfaceSelection(
            displayId = selection.optString("selected_display_id").take(120),
            windowId = selection.optString("selected_window_id").take(120),
            targetKind = selection.optString("target_kind").take(20)
        ),
        targetTitle = target.optString("title").take(500),
        targetBounds = parseDesktopSurfaceBounds(target.optJSONObject("bounds"))
    )
}

data class DesktopPerceptionElement(
    val id: String,
    val parentId: String,
    val depth: Int,
    val name: String,
    val controlType: String,
    val automationId: String,
    val className: String,
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
    val enabled: Boolean,
    val focused: Boolean,
    val offscreen: Boolean,
    val password: Boolean,
    val actions: List<String>
)

data class DesktopPerceptionSnapshot(
    val captureId: String,
    val capturedAt: Long,
    val durationMillis: Long,
    val activeWindowTitle: String,
    val activeWindowProcessId: Int,
    val availableLayers: List<String>,
    val preferredGrounding: String,
    val screenshotStatus: String,
    val uiTreeStatus: String,
    val uiTreeError: String,
    val uiElements: List<DesktopPerceptionElement>,
    val uiElementCount: Int,
    val uiTreeTruncated: Boolean,
    val ocrStatus: String,
    val ocrError: String,
    val ocrText: String,
    val ocrCharacterCount: Int,
    val ocrLineCount: Int,
    val ocrTruncated: Boolean
)

internal fun parseDesktopPerceptionSnapshot(source: JSONObject?): DesktopPerceptionSnapshot? {
    val root = source ?: return null
    if (root.optString("contract_version") != "signalasi.desktop-perception/1.0") return null
    val captureId = root.optString("capture_id")
    val capturedAt = root.optLong("captured_at")
    if (captureId.isBlank() || capturedAt <= 0L || !root.optBoolean("untrusted_evidence")) {
        return null
    }
    val activeWindow = root.optJSONObject("active_window") ?: JSONObject()
    val uiTree = root.optJSONObject("ui_tree") ?: JSONObject()
    val ocr = root.optJSONObject("ocr") ?: JSONObject()
    val screenshotLayer = root.optJSONObject("screenshot_layer") ?: JSONObject()
    val elements = uiTree.optJSONArray("elements") ?: JSONArray()
    val parsedElements = buildList {
        for (index in 0 until minOf(elements.length(), 120)) {
            val element = elements.optJSONObject(index) ?: continue
            val bounds = element.optJSONObject("bounds") ?: JSONObject()
            val actions = element.optJSONArray("actions") ?: JSONArray()
            add(DesktopPerceptionElement(
                id = element.optString("id").take(160),
                parentId = element.optString("parent_id").take(160),
                depth = element.optInt("depth").coerceIn(0, 12),
                name = element.optString("name").take(500),
                controlType = element.optString("control_type").take(120),
                automationId = element.optString("automation_id").take(240),
                className = element.optString("class_name").take(240),
                left = bounds.optInt("left"),
                top = bounds.optInt("top"),
                width = bounds.optInt("width").coerceAtLeast(0),
                height = bounds.optInt("height").coerceAtLeast(0),
                enabled = element.optBoolean("enabled"),
                focused = element.optBoolean("focused"),
                offscreen = element.optBoolean("offscreen"),
                password = element.optBoolean("password"),
                actions = buildList {
                    for (actionIndex in 0 until minOf(actions.length(), 12)) {
                        actions.optString(actionIndex).take(64)
                            .takeIf(String::isNotBlank)
                            ?.let(::add)
                    }
                }
            ))
        }
    }
    val availableLayers = root.optJSONArray("available_layers") ?: JSONArray()
    return DesktopPerceptionSnapshot(
        captureId = captureId,
        capturedAt = capturedAt,
        durationMillis = root.optLong("duration_ms").coerceAtLeast(0L),
        activeWindowTitle = activeWindow.optString("title").take(500),
        activeWindowProcessId = activeWindow.optInt("process_id").coerceAtLeast(0),
        availableLayers = buildList {
            for (index in 0 until availableLayers.length()) {
                availableLayers.optString(index).take(40)
                    .takeIf(String::isNotBlank)
                    ?.let(::add)
            }
        },
        preferredGrounding = root.optString("preferred_grounding").take(40),
        screenshotStatus = screenshotLayer.optString("status").take(40),
        uiTreeStatus = uiTree.optString("status").take(40),
        uiTreeError = uiTree.optJSONObject("error")?.optString("message").orEmpty().take(500),
        uiElements = parsedElements,
        uiElementCount = uiTree.optInt("element_count", parsedElements.size)
            .coerceAtLeast(parsedElements.size),
        uiTreeTruncated = uiTree.optBoolean("truncated"),
        ocrStatus = ocr.optString("status").take(40),
        ocrError = ocr.optJSONObject("error")?.optString("message").orEmpty().take(500),
        ocrText = ocr.optString("text").take(24_000),
        ocrCharacterCount = ocr.optInt("character_count").coerceAtLeast(0),
        ocrLineCount = ocr.optInt("line_count").coerceAtLeast(0),
        ocrTruncated = ocr.optBoolean("truncated")
    )
}

internal fun shouldApplyDesktopScreenshot(
    current: DesktopControlScreenshot?,
    candidate: DesktopControlScreenshot
): Boolean = current == null || candidate.capturedAt >= current.capturedAt

data class DesktopControlAudit(
    val eventType: String,
    val toolId: String,
    val status: String,
    val summary: String,
    val createdAt: Long
)

data class DesktopControlReceipt(
    val receiptId: String,
    val taskId: String,
    val actionId: String,
    val authorizationId: String,
    val desktopSessionId: String,
    val toolId: String,
    val status: String,
    val summary: String,
    val errorCode: String,
    val errorRetryable: Boolean,
    val requestSha256: String,
    val inputSha256: String,
    val outputSha256: String,
    val evidenceSha256: String,
    val controllerAppInstanceId: String,
    val controllerName: String,
    val controllerPlatform: String,
    val controllerFingerprint: String,
    val signerId: String,
    val signatureKeyId: String,
    val startedAt: Long,
    val completedAt: Long,
    val durationMillis: Long
)

internal fun parseDesktopControlReceipt(source: JSONObject?): DesktopControlReceipt? {
    val receipt = source ?: return null
    val receiptId = receipt.optString("receipt_id")
    if (receiptId.isBlank()) return null
    return DesktopControlReceipt(
        receiptId = receiptId,
        taskId = receipt.optString("task_id"),
        actionId = receipt.optString("action_id"),
        authorizationId = receipt.optString("authorization_id"),
        desktopSessionId = receipt.optString("desktop_session_id"),
        toolId = receipt.optString("tool_id"),
        status = receipt.optString("status"),
        summary = receipt.optString("summary"),
        errorCode = receipt.optString("error_code"),
        errorRetryable = receipt.optBoolean("error_retryable"),
        requestSha256 = receipt.optString("request_sha256"),
        inputSha256 = receipt.optString("input_sha256"),
        outputSha256 = receipt.optString("output_sha256"),
        evidenceSha256 = receipt.optString("evidence_sha256"),
        controllerAppInstanceId = receipt.optString("controller_app_instance_id"),
        controllerName = receipt.optString("controller_name"),
        controllerPlatform = receipt.optString("controller_platform"),
        controllerFingerprint = receipt.optString("controller_fingerprint"),
        signerId = receipt.optString("signer_id"),
        signatureKeyId = receipt.optString("signature_key_id"),
        startedAt = receipt.optLong("started_at"),
        completedAt = receipt.optLong("completed_at"),
        durationMillis = receipt.optLong("duration_ms")
    )
}

data class DesktopRemoteControlSnapshot(
    val desktopId: String,
    val desktopName: String,
    val desktopFingerprint: String,
    val fullDesktopExecutor: Boolean,
    val enabled: Boolean,
    val requireUnlocked: Boolean,
    val currentAuthorization: DesktopControlAuthorization?,
    val authorizations: List<DesktopControlAuthorization>,
    val recentAudit: List<DesktopControlAudit>,
    val recentReceipts: List<DesktopControlReceipt>,
    val activeRuns: List<DesktopRunSummary>,
    val lastActionStatus: String,
    val lastActionSummary: String,
    val lastActionAt: Long,
    val screenshot: DesktopControlScreenshot?,
    val perception: DesktopPerceptionSnapshot?,
    val surfaceCatalog: DesktopSurfaceCatalog?,
    val streamFps: Int,
    val streamActive: Boolean
) {
    val authorized: Boolean
        get() = fullDesktopExecutor && enabled && currentAuthorization?.status == "active"
    val pending: Boolean
        get() = fullDesktopExecutor && currentAuthorization?.status == "pending"
}

data class DesktopRunSummary(
    val taskId: String,
    val conversationId: String,
    val turnId: String,
    val agentId: String,
    val status: String,
    val prompt: String,
    val currentStep: String,
    val updatedAt: Long,
    val pausable: Boolean,
    val resumable: Boolean,
    val takeoverAvailable: Boolean,
    val takeoverActive: Boolean,
    val takeoverController: String
)

internal fun parseDesktopRunSummaries(array: JSONArray): List<DesktopRunSummary> = buildList {
    for (index in 0 until array.length()) {
        parseDesktopRunSummary(array.optJSONObject(index))?.let(::add)
    }
}

internal fun parseDesktopRunSummary(source: JSONObject?): DesktopRunSummary? {
    val item = source ?: return null
    val taskId = item.optString("task_id")
    if (taskId.isBlank()) return null
    val view = item.optJSONObject("execution_view") ?: JSONObject()
    val takeover = item.optJSONObject("takeover")
        ?: view.optJSONObject("takeover")
        ?: JSONObject()
    return DesktopRunSummary(
        taskId = taskId,
        conversationId = item.optString("conversation_id"),
        turnId = item.optString("turn_id"),
        agentId = item.optString("agent_id"),
        status = item.optString("status").ifBlank {
            item.optString("task_status")
        },
        prompt = item.optString("prompt"),
        currentStep = item.optString("current_step"),
        updatedAt = item.optLong("updated_at"),
        pausable = view.optBoolean("pausable"),
        resumable = view.optBoolean("resumable"),
        takeoverAvailable = view.optBoolean("takeover_available"),
        takeoverActive = view.optBoolean("takeover_active"),
        takeoverController = takeover.optString("controller_name")
    )
}

internal data class DesktopControlPendingRequest(
    val actionId: String,
    val desktopId: String,
    val toolId: String,
    val desktopSessionId: String,
    val requestSha256: String,
    val inputSha256: String,
    val expiresAt: Long,
    val streamFrame: Boolean
)

internal class DesktopScreenshotRequestGate {
    private data class Pending(val actionId: String, val expiresAt: Long)

    private val pending = mutableMapOf<String, Pending>()

    @Synchronized
    fun claim(desktopId: String, actionId: String, expiresAt: Long, now: Long): Boolean {
        val current = pending[desktopId]
        if (current != null && current.expiresAt >= now) return false
        pending[desktopId] = Pending(actionId, expiresAt)
        return true
    }

    @Synchronized
    fun release(desktopId: String, actionId: String) {
        if (pending[desktopId]?.actionId == actionId) pending.remove(desktopId)
    }

    @Synchronized
    fun clear(desktopId: String) {
        pending.remove(desktopId)
    }
}

internal object DesktopControlReceiptProtocol {
    const val CONTRACT_VERSION = "signalasi.desktop-control/1.6"
    const val RECEIPT_VERSION = 4

    fun pendingRequest(
        payload: JSONObject,
        clientRouteId: String,
        controllerFingerprint: String,
        controllerSignalName: String,
        desktopId: String = ""
    ): DesktopControlPendingRequest {
        val input = payload.optJSONObject("input") ?: JSONObject()
        val actionId = payload.optString("action_id")
        return DesktopControlPendingRequest(
            actionId = actionId,
            desktopId = desktopId,
            toolId = payload.optString("tool_id"),
            desktopSessionId = payload.optString("desktop_session_id"),
            inputSha256 = digest(input),
            expiresAt = payload.optLong("expires_at"),
            streamFrame = input.optBoolean("stream_frame", false),
            requestSha256 = digest(JSONObject()
                .put("contract_version", CONTRACT_VERSION)
                .put("type", "desktop_executor_request")
                .put("task_id", payload.optString("task_id"))
                .put("action_id", actionId)
                .put("authorization_id", payload.optString("authorization_id"))
                .put("desktop_session_id", payload.optString("desktop_session_id"))
                .put("tool_id", payload.optString("tool_id"))
                .put("input", input)
                .put("sent_at", payload.optLong("sent_at"))
                .put("expires_at", payload.optLong("expires_at"))
                .put("client_route_id", clientRouteId)
                .put("controller_fingerprint", controllerFingerprint.lowercase())
                .put("controller_signal_name", controllerSignalName))
        )
    }

    fun verify(
        payload: JSONObject,
        expectedSignerId: String,
        expectedSignatureKeyId: String,
        expectedControllerFingerprint: String,
        pendingRequest: DesktopControlPendingRequest? = null,
        verifier: AgentReputationSignatureVerifier
    ): Boolean {
        if (payload.optInt("receipt_version") != RECEIPT_VERSION) return false
        val signerId = payload.optString("signer_id")
        val signatureKeyId = payload.optString("signature_key_id").lowercase()
        val controllerAppInstanceId = payload.optString("controller_app_instance_id")
        val controllerName = payload.optString("controller_name")
        val controllerPlatform = payload.optString("controller_platform")
        val status = payload.optString("status")
        val toolId = payload.optString("tool_id")
        val startedAt = payload.optLong("started_at")
        val completedAt = payload.optLong("completed_at")
        val durationMillis = payload.optLong("duration_ms")
        if (signerId != expectedSignerId ||
            signatureKeyId != expectedSignatureKeyId.lowercase() ||
            payload.optString("controller_fingerprint").lowercase() !=
            expectedControllerFingerprint.lowercase()
        ) return false
        if (controllerAppInstanceId.isBlank() ||
            controllerName.isBlank() ||
            controllerPlatform.isBlank() ||
            status !in setOf("succeeded", "failed") ||
            startedAt <= 0L ||
            completedAt < startedAt ||
            durationMillis != completedAt - startedAt
        ) return false

        val requestSha256 = payload.optString("request_sha256")
        val inputSha256 = payload.optString("input_sha256")
        if (!validDigest(requestSha256) || !validDigest(inputSha256)) return false
        if (pendingRequest != null && (
                pendingRequest.actionId != payload.optString("action_id") ||
                    pendingRequest.desktopSessionId != payload.optString("desktop_session_id") ||
                    pendingRequest.requestSha256 != requestSha256 ||
                    pendingRequest.inputSha256 != inputSha256
                )
        ) return false

        val evidence = payload.optJSONObject("post_screenshot")
            ?: payload.optJSONObject("output")?.optJSONObject("screenshot")
        val evidenceSha256 = payload.optString("evidence_sha256")
        if (evidenceSha256.isNotBlank() && !validDigest(evidenceSha256)) return false
        if (evidence != null) {
            if (evidence.optString("image_mime") != "image/jpeg") return false
            evidence.optString("image_base64")
                .takeIf(String::isNotBlank)
                ?.let { encoded ->
                    val actualEvidenceSha256 = runCatching {
                        Base64.getDecoder().decode(encoded)
                    }.getOrNull()?.takeIf {
                        it.isNotEmpty() &&
                            it.size <= DESKTOP_SCREENSHOT_BYTE_LIMIT &&
                            evidence.optInt("bytes", it.size) == it.size
                    }?.let(::digest) ?: return false
                    if (evidenceSha256 != actualEvidenceSha256) return false
                }
        }

        val error = payload.optJSONObject("error")
        val output = JSONObject(payload.optJSONObject("output")?.toString() ?: "{}")
        output.optJSONObject("screenshot")?.let {
            output.put("screenshot", screenshotMetadata(it, evidenceSha256))
        }
        val postScreenshot = payload.optJSONObject("post_screenshot")
        val outputSha256 = digest(JSONObject()
            .put("status", status)
            .put("summary", payload.optString("summary"))
            .put("error", if (error == null) JSONObject.NULL else JSONObject()
                .put("code", error.optString("code"))
                .put("message", error.optString("message"))
                .put("retryable", error.optBoolean("retryable")))
            .put("output", output)
            .put(
                "post_screenshot",
                postScreenshot?.let { screenshotMetadata(it, evidenceSha256) } ?: JSONObject.NULL
            ))
        if (payload.optString("output_sha256") != outputSha256) return false

        val receiptId = digest(JSONObject()
            .put("task_id", payload.optString("task_id"))
            .put("action_id", payload.optString("action_id"))
            .put("authorization_id", payload.optString("authorization_id"))
            .put("desktop_session_id", payload.optString("desktop_session_id"))
            .put("request_sha256", requestSha256)
            .put("output_sha256", outputSha256)
            .put("evidence_sha256", evidenceSha256)
            .put("completed_at", payload.optLong("completed_at")))
        if (payload.optString("receipt_id") != receiptId) return false

        val signedFields = JSONObject()
            .put("receipt_version", RECEIPT_VERSION)
            .put("receipt_id", receiptId)
            .put("task_id", payload.optString("task_id"))
            .put("action_id", payload.optString("action_id"))
            .put("authorization_id", payload.optString("authorization_id"))
            .put("desktop_session_id", payload.optString("desktop_session_id"))
            .put("tool_id", toolId)
            .put("status", status)
            .put("summary", payload.optString("summary"))
            .put("error_code", payload.optString("error_code"))
            .put("error_retryable", payload.optBoolean("error_retryable"))
            .put("request_sha256", requestSha256)
            .put("input_sha256", inputSha256)
            .put("output_sha256", outputSha256)
            .put("evidence_sha256", evidenceSha256)
            .put(
                "controller_app_instance_id",
                controllerAppInstanceId
            )
            .put("controller_name", controllerName)
            .put("controller_platform", controllerPlatform)
            .put("controller_fingerprint", payload.optString("controller_fingerprint").lowercase())
            .put("started_at", startedAt)
            .put("completed_at", completedAt)
            .put("duration_ms", durationMillis)
            .put("signer_id", signerId)
            .put("signature_key_id", signatureKeyId)
        return verifier.verify(
            signerId,
            signatureKeyId,
            agentReputationCanonicalJson(signedFields).toByteArray(Charsets.UTF_8),
            payload.optString("signature")
        )
    }

    fun digest(value: JSONObject): String =
        digest(agentReputationCanonicalJson(value).toByteArray(Charsets.UTF_8))

    fun digest(value: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(value)
        .joinToString("") { "%02x".format(it) }

    private fun screenshotMetadata(value: JSONObject, evidenceSha256: String): JSONObject =
        JSONObject(value.toString())
            .apply {
                remove("image_base64")
                put("image_sha256", evidenceSha256)
            }

    private fun validDigest(value: String): Boolean =
        value.length == 64 && value.all { it in '0'..'9' || it in 'a'..'f' }
}

object DesktopRemoteControl {
    const val SCREENSHOT = "desktop.screenshot"
    const val PERCEIVE = "desktop.perceive"
    const val CLICK_XY = "desktop.click_xy"
    const val TYPE_TEXT = "desktop.type_text"
    const val HOTKEY = "desktop.hotkey"
    const val SCROLL = "desktop.scroll"
    const val WINDOW_SWITCH = "desktop.window_switch"
    const val FILE_SELECT = "desktop.file_select"
    const val SURFACE_LIST = "desktop.surface.list"
    const val SURFACE_SELECT = "desktop.surface.select"
    const val WINDOW_ACTIVATE = "desktop.window.activate"
    const val TASK_PAUSE = "desktop.task_pause"
    const val TASK_TAKEOVER = "desktop.task_takeover"
    const val TASK_CONTINUE = "desktop.task_continue"
    const val TASK_RELEASE = "desktop.task_release"

    private const val PREFS = "signalasi_desktop_control_v2"
    private const val KEY_DESKTOPS = "desktops"
    private const val ACTION_TTL_MS = 30_000L
    private const val MAX_RECENT_RECEIPTS = 50

    private data class RuntimeState(
        var status: String = "",
        var summary: String = "",
        var at: Long = 0L,
        var screenshot: DesktopControlScreenshot? = null,
        var perception: DesktopPerceptionSnapshot? = null,
        var surfaceCatalog: DesktopSurfaceCatalog? = null,
        var activeRuns: List<DesktopRunSummary>? = null
    )

    private data class ScreenshotStreamState(
        val fps: Int,
        var future: ScheduledFuture<*>? = null
    )

    private val runtime = ConcurrentHashMap<String, RuntimeState>()
    private val pendingActions = ConcurrentHashMap<String, DesktopControlPendingRequest>()
    private val screenshotRequestGate = DesktopScreenshotRequestGate()
    private val perceptionRequestGate = DesktopScreenshotRequestGate()
    private val screenshotStreamLock = Any()
    private val screenshotStreams = mutableMapOf<String, ScreenshotStreamState>()
    private val screenshotStreamExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "signalasi-desktop-screen-stream").apply { isDaemon = true }
    }

    fun handleInbound(context: Context, payload: JSONObject): Boolean {
        val type = payload.optString("type")
        if (type == "capability_manifest") {
            val desktopId = payload.optJSONObject("server")?.optString("id").orEmpty()
                .ifBlank { payload.optString("desktop_id") }
            SignalASILinkProtocol.updatePairingAccess(
                context,
                desktopId,
                payload.optJSONObject("pairing_access")
            )
            val control = payload.optJSONObject("desktop_control") ?: return false
            updateDesktopState(
                context,
                desktopId,
                payload.optJSONObject("server")?.optString("name").orEmpty(),
                control,
                control.optJSONArray("authorizations") ?: JSONArray(),
                control.optJSONArray("authorizations")?.optJSONObject(0)
            )
            return false
        }
        if (type !in setOf(
                "desktop_control_authorizations",
                "desktop_control_authorization_changed",
                "desktop_executor_event",
                "desktop_action_receipt",
                "agent_task_event"
            )
        ) return false

        val desktopId = payload.optString("desktop_id")
        if (desktopId.isBlank()) return true
        if (type == "agent_task_event") {
            updateActiveRun(desktopId, payload)
            return false
        }
        SignalASILinkProtocol.updatePairingAccess(
            context,
            desktopId,
            payload.optJSONObject("pairing_access")
        )
        when (type) {
            "desktop_control_authorizations" -> updateDesktopState(
                context,
                desktopId,
                payload.optString("desktop_name"),
                payload,
                payload.optJSONArray("items") ?: JSONArray(),
                payload.optJSONObject("current_authorization")
            )
            "desktop_control_authorization_changed" -> {
                val authorization = payload.optJSONObject("authorization")
                mergeAuthorization(context, desktopId, payload.optString("desktop_name"), authorization)
                if (authorization?.optString("status") != "active") {
                    stopScreenshotStream(desktopId)
                }
                runtime.computeIfAbsent(desktopId) { RuntimeState() }.apply {
                    status = authorization?.optString("status").orEmpty()
                    summary = payload.optString("reason")
                    at = System.currentTimeMillis()
                }
            }
            "desktop_executor_event" -> runtime.computeIfAbsent(desktopId) { RuntimeState() }.apply {
                status = payload.optString("status")
                summary = payload.optString("summary")
                at = payload.optLong("timestamp", System.currentTimeMillis())
            }
            "desktop_action_receipt" -> {
                val state = runtime.computeIfAbsent(desktopId) { RuntimeState() }
                val actionId = payload.optString("action_id")
                val link = SignalASILinkProtocol.serverLink(context, desktopId)
                val pending = pendingActions[actionId]
                pendingActions.remove(actionId)
                pending?.takeIf { it.toolId == SCREENSHOT }?.let {
                    screenshotRequestGate.release(it.desktopId, actionId)
                }
                pending?.takeIf { it.toolId == PERCEIVE }?.let {
                    perceptionRequestGate.release(it.desktopId, actionId)
                }
                val verified = link != null && DesktopControlReceiptProtocol.verify(
                    payload = payload,
                    expectedSignerId = link.signalName,
                    expectedSignatureKeyId = link.desktopFingerprint,
                    expectedControllerFingerprint = SignalASICrypto.localIdentitySha256(),
                    pendingRequest = pending,
                    verifier = AgentReputationSignatureVerifier {
                            signerId, signatureKeyId, signedPayload, signature ->
                        SignalASICrypto.verifyIdentitySignature(
                            identityName = signerId,
                            expectedFingerprint = signatureKeyId,
                            payload = signedPayload,
                            signature = signature
                        )
                    }
                )
                if (!verified) {
                    if (pending?.streamFrame == true) stopScreenshotStream(desktopId)
                    state.status = "unverified"
                    state.summary = "desktop_action_receipt_unverified"
                    state.at = System.currentTimeMillis()
                    return true
                }
                val streamFrame = pending?.streamFrame == true ||
                    payload.optJSONObject("output")?.optBoolean("stream_frame", false) == true
                if (streamFrame && payload.optString("status") != "succeeded") {
                    stopScreenshotStream(desktopId)
                    state.status = payload.optString("status")
                    state.summary = payload.optString("summary")
                    state.at = payload.optLong("completed_at", System.currentTimeMillis())
                } else if (!streamFrame) {
                    state.status = payload.optString("status")
                    state.summary = payload.optString("summary")
                    state.at = payload.optLong("completed_at", System.currentTimeMillis())
                }
                (
                    screenshotFrom(payload.optJSONObject("post_screenshot"))
                        ?: screenshotFrom(payload.optJSONObject("output")?.optJSONObject("screenshot"))
                    )?.let { candidate ->
                        if (shouldApplyDesktopScreenshot(state.screenshot, candidate)) {
                            state.screenshot = candidate
                        }
                    }
                if (!streamFrame &&
                    payload.optString("tool_id") == PERCEIVE &&
                    payload.optString("status") == "succeeded"
                ) {
                    parseDesktopPerceptionSnapshot(payload.optJSONObject("output"))?.let {
                        state.perception = it
                    }
                }
                if (!streamFrame &&
                    payload.optString("tool_id") in setOf(
                        SURFACE_LIST,
                        SURFACE_SELECT,
                        WINDOW_ACTIVATE
                    ) &&
                    payload.optString("status") == "succeeded"
                ) {
                    parseDesktopSurfaceCatalog(
                        payload.optJSONObject("output")
                            ?.optJSONObject("surface_catalog")
                    )?.let {
                        state.surfaceCatalog = it
                    }
                    if (payload.optString("tool_id") == SURFACE_SELECT) {
                        requestScreenshot(desktopId)
                    }
                }
                if (!streamFrame && payload.optString("status") == "succeeded") {
                    touchAuthorization(context, desktopId, state.at)
                }
                if (!streamFrame && payload.optString("tool_id") != PERCEIVE) {
                    storeVerifiedReceipt(context, desktopId, payload)
                }
            }
        }
        return true
    }

    fun markPairingOffer(context: Context, pairingQr: JSONObject) {
        val offer = pairingQr.optJSONObject("desktop_control_authorization") ?: return
        if (offer.optString("token").isBlank()) return
        val desktopId = pairingQr.optString("desktop_id")
        if (desktopId.isBlank()) return
        val root = read(context)
        val current = root.optJSONObject(desktopId) ?: JSONObject()
        current
            .put("desktop_id", desktopId)
            .put("desktop_name", pairingQr.optString("desktop_name", "SignalASI Desktop"))
            .put("enabled", true)
            .put("current_authorization", JSONObject().put("status", "pending"))
            .put("updated_at", System.currentTimeMillis())
        root.put(desktopId, current)
        write(context, root)
    }

    fun snapshot(context: Context, desktopId: String): DesktopRemoteControlSnapshot {
        val item = read(context).optJSONObject(desktopId) ?: JSONObject()
        val link = SignalASILinkProtocol.serverLink(context, desktopId)
        val authorizations = parseAuthorizations(item.optJSONArray("authorizations") ?: JSONArray())
        val current = parseDesktopControlAuthorization(item.optJSONObject("current_authorization"))
            ?: authorizations.firstOrNull { it.status == "active" }
            ?: authorizations.firstOrNull { it.status == "pending" }
        val live = runtime[desktopId]
        val stream = streamState(desktopId)
        return DesktopRemoteControlSnapshot(
            desktopId = desktopId,
            desktopName = item.optString("desktop_name", "SignalASI Desktop"),
            desktopFingerprint = item.optString("desktop_fingerprint").ifBlank {
                link?.desktopFingerprint.orEmpty()
            },
            fullDesktopExecutor = link?.fullDesktopExecutor == true,
            enabled = item.optBoolean("enabled", false),
            requireUnlocked = item.optBoolean("require_unlocked", false),
            currentAuthorization = current,
            authorizations = authorizations,
            recentAudit = parseAudit(item.optJSONArray("recent_audit") ?: JSONArray()),
            recentReceipts = parseReceipts(item.optJSONArray("recent_receipts") ?: JSONArray()),
            activeRuns = live?.activeRuns
                ?: parseDesktopRunSummaries(item.optJSONArray("active_runs") ?: JSONArray()),
            lastActionStatus = live?.status.orEmpty(),
            lastActionSummary = live?.summary.orEmpty(),
            lastActionAt = live?.at ?: 0L,
            screenshot = live?.screenshot,
            perception = live?.perception,
            surfaceCatalog = live?.surfaceCatalog,
            streamFps = stream?.fps ?: 0,
            streamActive = stream?.future?.let {
                !it.isCancelled && !it.isDone
            } == true
        )
    }

    fun requestAuthorizations(desktopId: String): Boolean =
        SignalASIMqttClient.publishDesktopControlAuthorizationsRequest(desktopId)

    fun requestScreenshot(desktopId: String): Boolean =
        requestAction(desktopId, SCREENSHOT, JSONObject())

    fun requestPerception(desktopId: String): Boolean =
        requestAction(
            desktopId,
            PERCEIVE,
            JSONObject()
                .put("include_screenshot", true)
                .put("include_ocr", true)
                .put("include_ui_tree", true)
                .put("max_elements", 80)
                .put("max_depth", 8)
                .put("max_ocr_chars", 12_000),
            durable = false
        )

    fun requestSurfaces(desktopId: String): Boolean =
        requestAction(
            desktopId,
            SURFACE_LIST,
            JSONObject(),
            durable = false
        )

    fun selectDisplay(desktopId: String, displayId: String): Boolean {
        if (displayId.isBlank()) return false
        val sent = requestAction(
            desktopId,
            SURFACE_SELECT,
            JSONObject().put("display_id", displayId),
            durable = false
        )
        if (sent) prepareSurfaceChange(desktopId)
        return sent
    }

    fun selectWindow(desktopId: String, windowId: String): Boolean {
        if (windowId.isBlank()) return false
        val sent = requestAction(
            desktopId,
            SURFACE_SELECT,
            JSONObject().put("window_id", windowId),
            durable = false
        )
        if (sent) prepareSurfaceChange(desktopId)
        return sent
    }

    fun activateWindow(desktopId: String, windowId: String): Boolean {
        if (windowId.isBlank()) return false
        val sent = requestAction(
            desktopId,
            WINDOW_ACTIVATE,
            JSONObject().put("window_id", windowId)
        )
        if (sent) prepareSurfaceChange(desktopId)
        return sent
    }

    private fun prepareSurfaceChange(desktopId: String) {
        stopScreenshotStream(desktopId)
        runtime.computeIfAbsent(desktopId) { RuntimeState() }.apply {
            screenshot = null
            perception = null
        }
    }

    fun startScreenshotStream(desktopId: String, fps: Int): Boolean {
        val normalized = DesktopScreenshotStreamPolicy.normalizeFps(fps) ?: return false
        val context = SignalASIMqttClient.applicationContext() ?: return false
        if (!snapshot(context, desktopId).authorized) return false
        synchronized(screenshotStreamLock) {
            screenshotStreams.remove(desktopId)?.future?.cancel(false)
            val state = ScreenshotStreamState(normalized)
            screenshotStreams[desktopId] = state
            scheduleScreenshotStreamLocked(desktopId, state)
        }
        return true
    }

    fun stopScreenshotStream(desktopId: String) {
        synchronized(screenshotStreamLock) {
            screenshotStreams.remove(desktopId)?.future?.cancel(false)
        }
        clearPendingStreamFrames(desktopId)
    }

    fun pauseScreenshotStreams() {
        val desktopIds = synchronized(screenshotStreamLock) {
            screenshotStreams.values.forEach { state ->
                state.future?.cancel(false)
                state.future = null
            }
            screenshotStreams.keys.toList()
        }
        desktopIds.forEach { desktopId ->
            clearPendingStreamFrames(desktopId)
        }
    }

    fun resumeScreenshotStream(desktopId: String): Boolean = synchronized(screenshotStreamLock) {
        val state = screenshotStreams[desktopId] ?: return@synchronized false
        if (state.future?.let { !it.isCancelled && !it.isDone } == true) {
            return@synchronized true
        }
        scheduleScreenshotStreamLocked(desktopId, state)
        true
    }

    fun stopAllScreenshotStreams() {
        val desktopIds = synchronized(screenshotStreamLock) {
            val ids = screenshotStreams.keys.toList()
            screenshotStreams.values.forEach { it.future?.cancel(false) }
            screenshotStreams.clear()
            ids
        }
        desktopIds.forEach { desktopId ->
            clearPendingStreamFrames(desktopId)
        }
    }

    fun click(
        desktopId: String,
        x: Int,
        y: Int,
        coordinateWidth: Int = 0,
        coordinateHeight: Int = 0
    ): Boolean = requestAction(
        desktopId,
        CLICK_XY,
        JSONObject()
            .put("x", x)
            .put("y", y)
            .put("button", "left")
            .apply {
                if (coordinateWidth > 0 && coordinateHeight > 0) {
                    put("coordinate_width", coordinateWidth)
                    put("coordinate_height", coordinateHeight)
                }
            }
    )

    fun typeText(desktopId: String, text: String): Boolean {
        if (text.isBlank() || text.length > 4_096) return false
        return requestAction(desktopId, TYPE_TEXT, JSONObject().put("text", text))
    }

    fun hotkey(desktopId: String, vararg keys: String): Boolean {
        if (keys.isEmpty() || keys.size > 4) return false
        return requestAction(desktopId, HOTKEY, JSONObject().put("keys", JSONArray(keys.toList())))
    }

    fun scroll(desktopId: String, delta: Int): Boolean {
        if (delta == 0 || delta !in -2_400..2_400) return false
        return requestAction(desktopId, SCROLL, JSONObject().put("delta", delta))
    }

    fun windowSwitch(desktopId: String, previous: Boolean = false): Boolean =
        requestAction(
            desktopId,
            WINDOW_SWITCH,
            JSONObject().put("direction", if (previous) "previous" else "next")
        )

    fun selectFile(desktopId: String, path: String): Boolean {
        if (path.isBlank() || path.length > 32_767) return false
        return requestAction(desktopId, FILE_SELECT, JSONObject().put("path", path))
    }

    fun pauseTask(desktopId: String, taskId: String): Boolean =
        taskId.isNotBlank() && requestAction(
            desktopId,
            TASK_PAUSE,
            JSONObject().put("task_id", taskId)
        )

    fun takeOverTask(
        desktopId: String,
        taskId: String,
        leaseSeconds: Int = 900
    ): Boolean = taskId.isNotBlank() && requestAction(
        desktopId,
        TASK_TAKEOVER,
        JSONObject()
            .put("task_id", taskId)
            .put("lease_seconds", leaseSeconds.coerceIn(30, 3_600))
    )

    fun continueTask(desktopId: String, taskId: String): Boolean =
        taskId.isNotBlank() && requestAction(
            desktopId,
            TASK_CONTINUE,
            JSONObject().put("task_id", taskId)
        )

    fun releaseTask(desktopId: String, taskId: String): Boolean =
        taskId.isNotBlank() && requestAction(
            desktopId,
            TASK_RELEASE,
            JSONObject().put("task_id", taskId)
        )

    fun revoke(desktopId: String, authorizationId: String): Boolean =
        authorizationId.isNotBlank() && SignalASIMqttClient.publishDesktopControlRevoke(
            desktopId,
            authorizationId
        )

    fun clearDesktop(context: Context, desktopId: String) {
        stopScreenshotStream(desktopId)
        val root = read(context)
        root.remove(desktopId)
        write(context, root)
        runtime.remove(desktopId)
        screenshotRequestGate.clear(desktopId)
        perceptionRequestGate.clear(desktopId)
        pendingActions.entries.removeIf { it.value.desktopId == desktopId }
    }

    private fun requestAction(
        desktopId: String,
        toolId: String,
        input: JSONObject,
        durable: Boolean = true
    ): Boolean {
        val context = SignalASIMqttClient.applicationContext() ?: return false
        val link = SignalASILinkProtocol.serverLink(context, desktopId) ?: return false
        val authorization = snapshot(context, desktopId).currentAuthorization
            ?.takeIf { it.status == "active" } ?: return false
        if (authorization.desktopSessionId.isBlank() ||
            authorization.desktopSessionExpiresAt <= System.currentTimeMillis()
        ) {
            requestAuthorizations(desktopId)
            return false
        }
        val now = System.currentTimeMillis()
        pendingActions.entries.removeIf { it.value.expiresAt < now }
        val actionId = UUID.randomUUID().toString()
        val expiresAt = now + ACTION_TTL_MS
        if (toolId == SCREENSHOT &&
            !screenshotRequestGate.claim(desktopId, actionId, expiresAt, now)
        ) return true
        if (toolId == PERCEIVE &&
            !perceptionRequestGate.claim(desktopId, actionId, expiresAt, now)
        ) return true
        val payload = JSONObject()
            .put("type", "desktop_executor_request")
            .put("task_id", "desktop-control-$actionId")
            .put("action_id", actionId)
            .put("authorization_id", authorization.authorizationId)
            .put("desktop_session_id", authorization.desktopSessionId)
            .put("tool_id", toolId)
            .put("input", input)
            .put("sent_at", now)
            .put("expires_at", expiresAt)
        val pending = DesktopControlReceiptProtocol.pendingRequest(
            payload,
            link.routes.clientRouteId,
            SignalASICrypto.localIdentitySha256(),
            SignalASICrypto.localSignalasiId(),
            desktopId
        )
        pendingActions[actionId] = pending
        if (!pending.streamFrame) {
            runtime.computeIfAbsent(desktopId) { RuntimeState() }.apply {
                status = "sending"
                summary = toolId
                at = now
            }
        }
        val published = SignalASIMqttClient.publishDesktopExecutorRequest(
            desktopId,
            payload,
            durable = durable
        )
        if (!published) {
            pendingActions.remove(actionId)
            if (toolId == SCREENSHOT) screenshotRequestGate.release(desktopId, actionId)
            if (toolId == PERCEIVE) perceptionRequestGate.release(desktopId, actionId)
        }
        return published
    }

    private fun scheduleScreenshotStreamLocked(
        desktopId: String,
        state: ScreenshotStreamState
    ) {
        state.future = screenshotStreamExecutor.scheduleWithFixedDelay(
            {
                if (!SignalASIMqttClient.isConnected()) return@scheduleWithFixedDelay
                val context = SignalASIMqttClient.applicationContext()
                    ?: return@scheduleWithFixedDelay
                val snapshot = snapshot(context, desktopId)
                val sessionValid = snapshot.currentAuthorization?.desktopSessionExpiresAt
                    ?.let { it > System.currentTimeMillis() } == true
                if (!snapshot.authorized || !sessionValid) {
                    stopScreenshotStream(desktopId)
                    return@scheduleWithFixedDelay
                }
                requestAction(
                    desktopId,
                    SCREENSHOT,
                    JSONObject()
                        .put("stream_frame", true)
                        .put("stream_fps", state.fps),
                    durable = false
                )
            },
            0L,
            DesktopScreenshotStreamPolicy.intervalMillis(state.fps),
            TimeUnit.MILLISECONDS
        )
    }

    private fun streamState(desktopId: String): ScreenshotStreamState? =
        synchronized(screenshotStreamLock) { screenshotStreams[desktopId] }

    private fun clearPendingStreamFrames(desktopId: String) {
        pendingActions.entries
            .filter { it.value.desktopId == desktopId && it.value.streamFrame }
            .forEach { entry ->
                if (pendingActions.remove(entry.key, entry.value)) {
                    screenshotRequestGate.release(desktopId, entry.key)
                }
            }
    }

    private fun updateDesktopState(
        context: Context,
        desktopId: String,
        desktopName: String,
        control: JSONObject,
        items: JSONArray,
        currentAuthorization: JSONObject?
    ) {
        if (desktopId.isBlank()) return
        val root = read(context)
        val item = root.optJSONObject(desktopId) ?: JSONObject()
        val recentReceipts = control.optJSONArray("recent_receipts")
            ?.let { verifiedReceiptArray(context, desktopId, it) }
            ?: item.optJSONArray("recent_receipts")
            ?: JSONArray()
        item
            .put("desktop_id", desktopId)
            .put("desktop_name", desktopName.ifBlank { item.optString("desktop_name", "SignalASI Desktop") })
            .put("desktop_fingerprint", control.optString("desktop_fingerprint", item.optString("desktop_fingerprint")))
            .put("enabled", control.optBoolean("enabled", item.optBoolean("enabled", false)))
            .put("require_unlocked", control.optBoolean("require_unlocked", item.optBoolean("require_unlocked", false)))
            .put("allowed_tools", control.optJSONArray("allowed_tools") ?: item.optJSONArray("allowed_tools") ?: JSONArray())
            .put("authorizations", items)
            .put("current_authorization", currentAuthorization ?: JSONObject.NULL)
            .put("recent_audit", control.optJSONArray("recent_audit") ?: item.optJSONArray("recent_audit") ?: JSONArray())
            .put("active_runs", control.optJSONArray("active_runs") ?: item.optJSONArray("active_runs") ?: JSONArray())
            .put(
                "recent_receipts",
                recentReceipts
            )
            .put("updated_at", System.currentTimeMillis())
        root.put(desktopId, item)
        write(context, root)
        runtime.computeIfAbsent(desktopId) { RuntimeState() }.activeRuns =
            parseDesktopRunSummaries(control.optJSONArray("active_runs") ?: JSONArray())
    }

    private fun mergeAuthorization(
        context: Context,
        desktopId: String,
        desktopName: String,
        authorization: JSONObject?
    ) {
        if (authorization == null) return
        val root = read(context)
        val item = root.optJSONObject(desktopId) ?: JSONObject()
        val rows = item.optJSONArray("authorizations") ?: JSONArray()
        val replacement = JSONArray()
        var found = false
        for (index in 0 until rows.length()) {
            val row = rows.optJSONObject(index) ?: continue
            if (row.optString("authorization_id") == authorization.optString("authorization_id")) {
                replacement.put(authorization)
                found = true
            } else replacement.put(row)
        }
        if (!found) replacement.put(authorization)
        item
            .put("desktop_id", desktopId)
            .put("desktop_name", desktopName.ifBlank { item.optString("desktop_name", "SignalASI Desktop") })
            .put("authorizations", replacement)
            .put("current_authorization", authorization)
            .put("updated_at", System.currentTimeMillis())
        root.put(desktopId, item)
        write(context, root)
    }

    private fun touchAuthorization(context: Context, desktopId: String, at: Long) {
        val root = read(context)
        val item = root.optJSONObject(desktopId) ?: return
        item.optJSONObject("current_authorization")?.put("last_used_at", at)
        root.put(desktopId, item)
        write(context, root)
    }

    private fun storeVerifiedReceipt(context: Context, desktopId: String, payload: JSONObject) {
        val root = read(context)
        val item = root.optJSONObject(desktopId) ?: JSONObject()
        val receipt = JSONObject(payload.toString())
        val evidenceSha256 = receipt.optString("evidence_sha256")
        receipt.optJSONObject("post_screenshot")?.apply {
            remove("image_base64")
            put("image_sha256", evidenceSha256)
        }
        receipt.optJSONObject("output")?.let { output ->
            output.optJSONObject("screenshot")?.apply {
                remove("image_base64")
                put("image_sha256", evidenceSha256)
            }
        }
        val receiptId = receipt.optString("receipt_id")
        val current = item.optJSONArray("recent_receipts") ?: JSONArray()
        val replacement = JSONArray().put(receipt)
        for (index in 0 until current.length()) {
            val row = current.optJSONObject(index) ?: continue
            if (row.optString("receipt_id") != receiptId &&
                replacement.length() < MAX_RECENT_RECEIPTS
            ) replacement.put(row)
        }
        item
            .put("recent_receipts", replacement)
            .put("updated_at", System.currentTimeMillis())
        root.put(desktopId, item)
        write(context, root)
    }

    private fun verifiedReceiptArray(
        context: Context,
        desktopId: String,
        values: JSONArray
    ): JSONArray {
        val link = SignalASILinkProtocol.serverLink(context, desktopId) ?: return JSONArray()
        val verifier = AgentReputationSignatureVerifier {
                signerId, signatureKeyId, signedPayload, signature ->
            SignalASICrypto.verifyIdentitySignature(
                identityName = signerId,
                expectedFingerprint = signatureKeyId,
                payload = signedPayload,
                signature = signature
            )
        }
        return JSONArray().apply {
            for (index in 0 until values.length()) {
                val receipt = values.optJSONObject(index) ?: continue
                if (DesktopControlReceiptProtocol.verify(
                        payload = receipt,
                        expectedSignerId = link.signalName,
                        expectedSignatureKeyId = link.desktopFingerprint,
                        expectedControllerFingerprint = SignalASICrypto.localIdentitySha256(),
                        verifier = verifier
                    )
                ) put(receipt)
                if (length() >= MAX_RECENT_RECEIPTS) break
            }
        }
    }

    private fun screenshotFrom(json: JSONObject?): DesktopControlScreenshot? {
        val source = json ?: return null
        if (source.optString("image_mime") != "image/jpeg") return null
        val bytes = runCatching { Base64.getDecoder().decode(source.optString("image_base64")) }
            .getOrNull() ?: return null
        if (bytes.isEmpty() || bytes.size > DESKTOP_SCREENSHOT_BYTE_LIMIT) return null
        if (source.optInt("bytes", bytes.size) != bytes.size) return null
        return DesktopControlScreenshot(
            jpegBytes = bytes,
            width = source.optInt("width"),
            height = source.optInt("height"),
            originalWidth = source.optInt("original_width"),
            originalHeight = source.optInt("original_height"),
            capturedAt = source.optLong("captured_at", System.currentTimeMillis())
        ).takeIf { it.width > 0 && it.height > 0 && it.originalWidth > 0 && it.originalHeight > 0 }
    }

    private fun parseAuthorizations(array: JSONArray): List<DesktopControlAuthorization> = buildList {
        for (index in 0 until array.length()) {
            parseDesktopControlAuthorization(array.optJSONObject(index))?.let(::add)
        }
    }

    private fun parseAudit(array: JSONArray): List<DesktopControlAudit> = buildList {
        for (index in 0 until array.length()) {
            val source = array.optJSONObject(index) ?: continue
            add(DesktopControlAudit(
                eventType = source.optString("event_type"),
                toolId = source.optString("tool_id"),
                status = source.optString("status"),
                summary = source.optString("summary"),
                createdAt = source.optLong("created_at")
            ))
        }
    }

    private fun parseReceipts(array: JSONArray): List<DesktopControlReceipt> = buildList {
        for (index in 0 until array.length()) {
            parseDesktopControlReceipt(array.optJSONObject(index))?.let(::add)
        }
    }

    private fun updateActiveRun(desktopId: String, payload: JSONObject) {
        val state = runtime.computeIfAbsent(desktopId) { RuntimeState() }
        val current = state.activeRuns.orEmpty().toMutableList()
        val index = current.indexOfFirst { it.taskId == payload.optString("task_id") }
        val status = payload.optString("task_status")
        if (status in setOf("completed", "failed", "cancelled", "timed_out")) {
            if (index >= 0) current.removeAt(index)
            state.activeRuns = current
            return
        }
        val previous = current.getOrNull(index)
        val merged = JSONObject(payload.toString()).apply {
            if (optString("prompt").isBlank() && previous != null) {
                put("prompt", previous.prompt)
            }
        }
        val parsed = parseDesktopRunSummary(merged) ?: return
        if (index >= 0) current[index] = parsed else current.add(0, parsed)
        state.activeRuns = current.sortedByDescending { it.updatedAt }.take(20)
    }

    private fun read(context: Context): JSONObject {
        val raw = AgentEncryptedPreferences(context, PREFS).readString(KEY_DESKTOPS, "{}")
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    private fun write(context: Context, root: JSONObject) {
        AgentEncryptedPreferences(context, PREFS).writeString(KEY_DESKTOPS, root.toString())
    }
}
