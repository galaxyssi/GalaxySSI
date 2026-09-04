package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

internal object GalaxySSIMqttDesktopControl {
    private val pendingArtifactDownloads = ConcurrentHashMap.newKeySet<String>()
    private val pendingArtifactFetches = ConcurrentHashMap.newKeySet<String>()

    fun consumePendingArtifactDownload(artifactUri: String): Boolean =
        pendingArtifactDownloads.remove(artifactUri)

    fun consumePendingArtifactFetch(artifactUri: String): Boolean =
        pendingArtifactFetches.remove(artifactUri)

    fun publishServerRevocation(context: android.content.Context, desktopId: String): Boolean {
        GalaxySSIMqttClient.bindApplicationContext(context)
        return GalaxySSIMqttClient.publishDesktopControlPayload(
            desktopId,
            JSONObject()
                .put("type", "client_revoked")
                .put("desktop_id", desktopId)
                .put("reason", "forgotten_by_client")
                .put("time", System.currentTimeMillis())
        )
    }

    fun verifyPcIdentityFromQr(contents: String): Boolean {
        val context = GalaxySSIMqttClient.applicationContext() ?: return false
        val qr = runCatching { JSONObject(contents) }.getOrNull() ?: return false
        if (!GalaxySSILinkProtocol.validatePairingQr(qr)) return false
        if (!GalaxySSICrypto.verifyPcIdentityFromQr(contents)) return false
        GalaxySSILinkProtocol.ensureServerLink(context, qr)
        return true
    }

    fun publishToolCall(desktopId: String, payload: JSONObject): Boolean =
        GalaxySSIMqttClient.publishDesktopControlPayload(desktopId, payload)

    fun publishRemoteWhisperPacket(desktopId: String, payload: JSONObject): Boolean =
        GalaxySSIMqttClient.publishDesktopControlPayload(desktopId, payload, durable = true)

    fun publishExecutorRequest(
        desktopId: String,
        payload: JSONObject,
        durable: Boolean
    ): Boolean = GalaxySSIMqttClient.publishDesktopControlPayload(desktopId, payload, durable)

    fun requestAuthorizations(desktopId: String): Boolean =
        GalaxySSIMqttClient.publishDesktopControlPayload(
            desktopId,
            JSONObject()
                .put("type", "desktop_control_authorizations_request")
                .put("time", System.currentTimeMillis())
        )

    fun revokeAuthorization(desktopId: String, authorizationId: String): Boolean =
        GalaxySSIMqttClient.publishDesktopControlPayload(
            desktopId,
            JSONObject()
                .put("type", "desktop_control_revoke")
                .put("authorization_id", authorizationId)
                .put("time", System.currentTimeMillis())
        )

    fun requestEvolutionTasks(desktopId: String): Boolean =
        GalaxySSIMqttClient.publishDesktopControlPayload(
            desktopId,
            JSONObject()
                .put("type", "evolution_task_list_request")
                .put("time", System.currentTimeMillis())
        )

    fun createEvolutionTask(
        desktopId: String,
        problem: String,
        scope: List<String>,
        acceptance: List<String>,
        reproductionSteps: List<String>,
        riskLevel: String,
        maxAttempts: Int,
        agentId: String
    ): Boolean = GalaxySSIMqttClient.publishDesktopControlPayload(
        desktopId,
        JSONObject()
            .put("type", "evolution_task_create")
            .put("problem", problem)
            .put("scope", JSONArray(scope))
            .put("acceptance", JSONArray(acceptance))
            .put("reproduction_steps", JSONArray(reproductionSteps))
            .put("risk_level", riskLevel)
            .put("max_attempts", maxAttempts.coerceIn(1, 5))
            .put("agent_id", agentId)
            .put("start", true)
            .put("time", System.currentTimeMillis())
    )

    fun controlEvolutionTask(
        desktopId: String,
        taskId: String,
        action: String,
        approvalHash: String
    ): Boolean {
        val type = when (action) {
            "cancel" -> "evolution_task_cancel"
            "rollback" -> "evolution_candidate_rollback"
            "publish" -> "evolution_candidate_publish"
            else -> return false
        }
        return GalaxySSIMqttClient.publishDesktopControlPayload(
            desktopId,
            JSONObject()
                .put("type", type)
                .put("task_id", taskId)
                .put("approval_hash", approvalHash)
                .put("base_branch", "main")
                .put("time", System.currentTimeMillis())
        )
    }

    fun publishToolCancel(
        desktopId: String,
        callId: String,
        taskId: String,
        conversationId: String
    ): Boolean = GalaxySSIMqttClient.publishDesktopControlPayload(
        desktopId,
        JSONObject()
            .put("type", "desktop_tool_call_cancel")
            .put("call_id", callId)
            .put("invocation_id", callId)
            .put("task_id", taskId)
            .put("conversation_id", conversationId)
            .put("time", System.currentTimeMillis())
    )

    fun publishArtifactReceipt(
        desktopId: String,
        clientRouteId: String,
        result: AgentDesktopArtifactIngestResult
    ): Boolean = GalaxySSIMqttClient.publishDesktopControlPayload(
        desktopId,
        JSONObject()
            .put("type", "artifact_receipt")
            .put("artifact_id", result.artifactId)
            .put("artifact_uri", result.artifactUri)
            .put("task_id", result.taskId)
            .put("sha256", result.sha256)
            .put("status", "stored")
            .put("time", System.currentTimeMillis()),
        clientRouteId = clientRouteId
    )

    fun requestArtifactDownload(block: AgentRichBlock): Boolean {
        val context = GalaxySSIMqttClient.applicationContext() ?: return false
        val artifactUri = block.metadata["artifact_source_uri"].orEmpty().ifBlank { block.uri }
        val digest = block.metadata["sha256"].orEmpty().trim().lowercase()
        if (artifactUri.isBlank() || digest.length != 64) return false
        val pairedLinks = GalaxySSILinkProtocol.allServerLinks(context).filter { it.paired }
        val desktopId = block.metadata["desktop_id"].orEmpty()
        val clientRouteId = block.metadata["client_route_id"].orEmpty()
        val link = when {
            desktopId.isNotBlank() && clientRouteId.isNotBlank() ->
                GalaxySSILinkProtocol.serverLink(context, desktopId, clientRouteId)
            desktopId.isNotBlank() -> GalaxySSILinkProtocol.serverLink(context, desktopId)
            pairedLinks.size == 1 -> pairedLinks.single()
            else -> null
        } ?: return false
        val artifactId = block.metadata["artifact_id"].orEmpty().ifBlank {
            MessageDigest.getInstance("SHA-256")
                .digest("$artifactUri\u0000$digest".toByteArray(StandardCharsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
        }
        if (!pendingArtifactDownloads.add(artifactUri)) return true
        val accepted = GalaxySSIMqttClient.publishDesktopControlPayload(
            link.desktopId,
            JSONObject()
                .put("type", "artifact_redelivery_request")
                .put("artifact_id", artifactId)
                .put("artifact_uri", artifactUri)
                .put("task_id", block.metadata["task_id"].orEmpty())
                .put("sha256", digest)
                .put("time", System.currentTimeMillis()),
            clientRouteId = link.routes.clientRouteId
        )
        if (!accepted) pendingArtifactDownloads.remove(artifactUri)
        return accepted
    }

    fun requestPeerArtifactFetch(attachment: PeerChatAttachment, desktopId: String): Boolean {
        val context = GalaxySSIMqttClient.applicationContext() ?: return false
        val artifactUri = attachment.artifactUri.trim()
        val digest = attachment.sha256.trim().lowercase()
        if (artifactUri.isBlank() || digest.length != 64) return false
        val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return false
        val artifactId = MessageDigest.getInstance("SHA-256")
            .digest("$artifactUri\u0000$digest".toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (!pendingArtifactFetches.add(artifactUri)) return true
        val accepted = GalaxySSIMqttClient.publishDesktopControlPayload(
            link.desktopId,
            JSONObject()
                .put("type", "artifact_redelivery_request")
                .put("artifact_id", artifactId)
                .put("artifact_uri", artifactUri)
                .put("sha256", digest)
                .put("time", System.currentTimeMillis()),
            clientRouteId = link.routes.clientRouteId
        )
        if (!accepted) pendingArtifactFetches.remove(artifactUri)
        return accepted
    }
}
