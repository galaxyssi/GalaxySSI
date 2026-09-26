package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

internal object DoorAccessNativeTool {
    const val SKILL_ID = "com.galaxyssi.skill.door_access"
    const val SKILL_VERSION = "1.3.0"
    const val ID = DoorAccessConfiguration.TOOL_ID
    private data class Authorization(
        val request: String,
        val command: DoorAccessCommand,
        val configuration: DoorAccessConfiguration,
        val expiresAtNanos: Long
    )
    private val authorizedTurns = ConcurrentHashMap<String, Authorization>()
    private const val AUTHORIZATION_NANOS = 30_000_000_000L

    fun configuration(context: Context, runtime: AgentSkillRuntime? = null): DoorAccessConfiguration? {
        val installed = (runtime ?: AgentSkillRuntime(EncryptedAgentSkillStore(context))).list()
            .filter { it.id == SKILL_ID }
        if (installed.isEmpty()) return null
        val latest = installed.filter { it.enabled && it.autoInvoke }
            .maxByOrNull { it.installedAtMillis } ?: return null
        return configuration(latest.manifest)
    }

    internal fun configuration(manifest: AgentSkillManifest): DoorAccessConfiguration? {
        val step = manifest.steps.singleOrNull()?.takeIf { it.toolId == ID } ?: return null
        val raw = step.input["door_config"] as? Map<*, *> ?: return null
        return DoorAccessConfiguration.fromJson(JSONObject(raw).toString())
    }

    fun authorize(
        conversationId: String,
        turnId: String,
        request: String,
        configuration: DoorAccessConfiguration,
        listOnly: Boolean = false
    ) {
        if (conversationId.isBlank() || turnId.isBlank()) return
        val parsed = configuration.parse(request) ?: return
        val now = System.nanoTime()
        authorizedTurns.entries.removeIf { it.value.expiresAtNanos <= now }
        authorizedTurns["$conversationId:$turnId"] = Authorization(
            request, if (listOnly) DoorAccessCommand.ListDoors else parsed, configuration, now + AUTHORIZATION_NANOS
        )
    }

    internal fun consumeAuthorization(conversationId: String, turnId: String, request: String): Boolean {
        return consumeAuthorizedRequest(conversationId, turnId, request) != null
    }

    private fun consumeAuthorizedRequest(conversationId: String, turnId: String, request: String): Authorization? {
        val authorization = authorizedTurns.remove("$conversationId:$turnId") ?: return null
        return authorization.takeIf { it.request == request && it.expiresAtNanos > System.nanoTime() }
    }

    fun actionFor(request: String, turnId: String, configuration: DoorAccessConfiguration, context: Context? = null): AgentAction? {
        if (configuration.parse(request) == null) return null
        return AgentAction(
            id = "door-access-$turnId",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = context?.doorAccessText("title") ?: "Door access",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Handle the door command locally",
            parameters = mapOf(
                "tool_id" to ID,
                "input_json" to AgentNativeJsonCodec.stringify(mapOf("request" to request)),
                "response_language" to "zh"
            )
        )
    }

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val descriptor = AgentNativeToolDescriptor(
            id = ID,
            version = SKILL_VERSION,
            title = context.doorAccessText("title"),
            description = context.doorAccessText("tool_description"),
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf(
                    "request" to AgentNativeJsonSchema.string(maxLength = 80),
                    "door_config" to AgentNativeJsonSchema.objectSchema(additionalProperties = true)
                ),
                additionalProperties = false
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.MEDIUM,
            capabilities = setOf("door_access.panel"),
            timeoutMillis = 60_000L,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT
        )
        return listOf(AgentNativeToolDefinition(
            descriptor = descriptor,
            executor = AgentNativeToolExecutor { invocation ->
                val request = invocation.input["request"] as? String ?: ""
                // Only a local exact-match authorization can open a door; model-supplied configuration is ignored.
                val authorized = consumeAuthorizedRequest(
                    invocation.context.conversationId, invocation.context.turnId, request
                )
                val credentials = DoorAccessCredentialStore(context).load()
                val configuration = authorized?.configuration ?: configuration(context)
                val command = authorized?.command
                if (credentials != null && command is DoorAccessCommand.Open) {
                    val outcome = try {
                        DoorAccessClient().openUnique(credentials.first, credentials.second, command,
                            System.currentTimeMillis(), requireNotNull(configuration), invocation::checkpoint)
                    } catch (_: Exception) {
                        invocation.checkpoint()
                        return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                            code = "door_service_failed",
                            message = context.doorAccessText("service_failed"),
                            retryable = false
                        )
                    }
                    return@AgentNativeToolExecutor when (outcome.status) {
                        DoorAccessOpenStatus.ACCEPTED -> AgentNativeToolExecutionResult.success(
                            mapOf("panel_opened" to false, "unlock_sent" to true),
                            context.doorAccessText("sent")
                        )
                        DoorAccessOpenStatus.NO_UNIQUE_MATCH -> AgentNativeToolExecutionResult.failure(
                            code = "door_not_unique",
                            message = context.doorAccessText("not_unique_tool"),
                            retryable = false
                        )
                        DoorAccessOpenStatus.REJECTED -> AgentNativeToolExecutionResult.failure(
                            code = "door_rejected",
                            message = context.doorAccessText("rejected_tool"),
                            retryable = false
                        )
                        DoorAccessOpenStatus.UNCONFIRMED -> AgentNativeToolExecutionResult.failure(
                            code = "door_unconfirmed",
                            message = context.doorAccessText("unconfirmed"),
                            retryable = false
                        )
                    }
                }
                context.startActivity(Intent(context, DoorAccessActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra(DoorAccessActivity.EXTRA_CONFIGURATION, configuration?.json)
                    .putExtra(DoorAccessActivity.EXTRA_COMMAND_ID, UUID.randomUUID().toString()))
                val message = when {
                    credentials == null -> context.doorAccessText("setup_opened")
                    else -> context.doorAccessText("list_opened")
                }
                AgentNativeToolExecutionResult.success(
                    mapOf("panel_opened" to true, "unlock_sent" to false),
                    message
                )
            },
            executorId = "galaxyssi.door_access.local",
            provenanceMetadata = mapOf("platform" to "android")
        ))
    }
}
