package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

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
    val serverRouteId: String,
    val fullDesktopExecutor: Boolean,
    val enabled: Boolean,
    val requireUnlocked: Boolean,
    val currentAuthorization: DesktopControlAuthorization?,
    val authorizations: List<DesktopControlAuthorization>,
    val recentAudit: List<DesktopControlAudit>,
    val recentReceipts: List<DesktopControlReceipt>,
    val lastActionStatus: String,
    val lastActionSummary: String,
    val lastActionAt: Long,
    val screenshot: DesktopControlScreenshot?
) {
    val authorized: Boolean
        get() = fullDesktopExecutor && enabled && currentAuthorization?.status == "active"
    val pending: Boolean
        get() = fullDesktopExecutor && currentAuthorization?.status == "pending"
}

internal data class DesktopControlPendingRequest(
    val actionId: String,
    val desktopSessionId: String,
    val requestSha256: String,
    val inputSha256: String,
    val expiresAt: Long
)

internal object DesktopControlReceiptProtocol {
    const val CONTRACT_VERSION = "signalasi.desktop-control/1.2"
    const val RECEIPT_VERSION = 4

    fun pendingRequest(
        payload: JSONObject,
        clientRouteId: String,
        controllerFingerprint: String,
        controllerSignalName: String
    ): DesktopControlPendingRequest {
        val input = payload.optJSONObject("input") ?: JSONObject()
        val actionId = payload.optString("action_id")
        return DesktopControlPendingRequest(
            actionId = actionId,
            desktopSessionId = payload.optString("desktop_session_id"),
            inputSha256 = digest(input),
            expiresAt = payload.optLong("expires_at"),
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
            evidence.optString("image_base64")
                .takeIf(String::isNotBlank)
                ?.let { encoded ->
                    val actualEvidenceSha256 = runCatching {
                        Base64.getDecoder().decode(encoded)
                    }.getOrNull()?.let(::digest) ?: return false
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
    const val CLICK_XY = "desktop.click_xy"
    const val TYPE_TEXT = "desktop.type_text"
    const val HOTKEY = "desktop.hotkey"
    const val SCROLL = "desktop.scroll"

    private const val PREFS = "signalasi_desktop_control_v2"
    private const val KEY_DESKTOPS = "desktops"
    private const val ACTION_TTL_MS = 30_000L
    private const val MAX_SCREENSHOT_BYTES = 100_000
    private const val MAX_RECENT_RECEIPTS = 50

    private data class RuntimeState(
        var status: String = "",
        var summary: String = "",
        var at: Long = 0L,
        var screenshot: DesktopControlScreenshot? = null
    )

    private val runtime = ConcurrentHashMap<String, RuntimeState>()
    private val pendingActions = ConcurrentHashMap<String, DesktopControlPendingRequest>()

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
                "desktop_action_receipt"
            )
        ) return false

        val desktopId = payload.optString("desktop_id")
        if (desktopId.isBlank()) return true
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
                pendingActions.remove(actionId)
                if (!verified) {
                    state.status = "unverified"
                    state.summary = "desktop_action_receipt_unverified"
                    state.at = System.currentTimeMillis()
                    return true
                }
                state.status = payload.optString("status")
                state.summary = payload.optString("summary")
                state.at = payload.optLong("completed_at", System.currentTimeMillis())
                (
                    screenshotFrom(payload.optJSONObject("post_screenshot"))
                        ?: screenshotFrom(payload.optJSONObject("output")?.optJSONObject("screenshot"))
                    )?.let { state.screenshot = it }
                if (payload.optString("status") == "succeeded") {
                    touchAuthorization(context, desktopId, state.at)
                }
                storeVerifiedReceipt(context, desktopId, payload)
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
        return DesktopRemoteControlSnapshot(
            desktopId = desktopId,
            desktopName = item.optString("desktop_name", "SignalASI Desktop"),
            desktopFingerprint = item.optString("desktop_fingerprint").ifBlank {
                link?.desktopFingerprint.orEmpty()
            },
            serverRouteId = item.optString("server_route_id").ifBlank {
                link?.routes?.serverRouteId.orEmpty()
            },
            fullDesktopExecutor = link?.fullDesktopExecutor == true,
            enabled = item.optBoolean("enabled", false),
            requireUnlocked = item.optBoolean("require_unlocked", false),
            currentAuthorization = current,
            authorizations = authorizations,
            recentAudit = parseAudit(item.optJSONArray("recent_audit") ?: JSONArray()),
            recentReceipts = parseReceipts(item.optJSONArray("recent_receipts") ?: JSONArray()),
            lastActionStatus = live?.status.orEmpty(),
            lastActionSummary = live?.summary.orEmpty(),
            lastActionAt = live?.at ?: 0L,
            screenshot = live?.screenshot
        )
    }

    fun requestAuthorizations(desktopId: String): Boolean =
        SignalASIMqttClient.publishDesktopControlAuthorizationsRequest(desktopId)

    fun requestScreenshot(desktopId: String): Boolean = requestAction(desktopId, SCREENSHOT, JSONObject())

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

    fun revoke(desktopId: String, authorizationId: String): Boolean =
        authorizationId.isNotBlank() && SignalASIMqttClient.publishDesktopControlRevoke(
            desktopId,
            authorizationId
        )

    fun clearDesktop(context: Context, desktopId: String) {
        val root = read(context)
        root.remove(desktopId)
        write(context, root)
        runtime.remove(desktopId)
    }

    private fun requestAction(desktopId: String, toolId: String, input: JSONObject): Boolean {
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
        val actionId = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("type", "desktop_executor_request")
            .put("task_id", "desktop-control-$actionId")
            .put("action_id", actionId)
            .put("authorization_id", authorization.authorizationId)
            .put("desktop_session_id", authorization.desktopSessionId)
            .put("tool_id", toolId)
            .put("input", input)
            .put("sent_at", now)
            .put("expires_at", now + ACTION_TTL_MS)
        val pending = DesktopControlReceiptProtocol.pendingRequest(
            payload,
            link.routes.clientRouteId,
            SignalASICrypto.localIdentitySha256(),
            SignalASICrypto.localSignalasiId()
        )
        pendingActions.entries.removeIf { it.value.expiresAt < now }
        pendingActions[actionId] = pending
        runtime.computeIfAbsent(desktopId) { RuntimeState() }.apply {
            status = "sending"
            summary = toolId
            at = now
        }
        val published = SignalASIMqttClient.publishDesktopExecutorRequest(desktopId, payload)
        if (!published) pendingActions.remove(actionId)
        return published
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
            .put("server_route_id", control.optString("server_route_id", item.optString("server_route_id")))
            .put("enabled", control.optBoolean("enabled", item.optBoolean("enabled", false)))
            .put("require_unlocked", control.optBoolean("require_unlocked", item.optBoolean("require_unlocked", false)))
            .put("allowed_tools", control.optJSONArray("allowed_tools") ?: item.optJSONArray("allowed_tools") ?: JSONArray())
            .put("authorizations", items)
            .put("current_authorization", currentAuthorization ?: JSONObject.NULL)
            .put("recent_audit", control.optJSONArray("recent_audit") ?: item.optJSONArray("recent_audit") ?: JSONArray())
            .put(
                "recent_receipts",
                recentReceipts
            )
            .put("updated_at", System.currentTimeMillis())
        root.put(desktopId, item)
        write(context, root)
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
        if (bytes.isEmpty() || bytes.size > MAX_SCREENSHOT_BYTES) return null
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

    private fun read(context: Context): JSONObject {
        val raw = AgentEncryptedPreferences(context, PREFS).readString(KEY_DESKTOPS, "{}")
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    private fun write(context: Context, root: JSONObject) {
        AgentEncryptedPreferences(context, PREFS).writeString(KEY_DESKTOPS, root.toString())
    }
}
