package com.galaxyssi.chat

import android.content.Context
import java.io.File
import java.security.MessageDigest
import java.util.Base64
import org.json.JSONObject

/** Real browser contexts in phone Linux; static fetch sessions remain unchanged. */
internal object AgentInteractiveBrowserTools {
    const val OBSERVE = "galaxyssi.browser.observe"
    const val ACT = "galaxyssi.browser.act"
    val toolIds = setOf(OBSERVE, ACT)
    private const val TIMEOUT = 180_000L

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val manager = AgentOnDeviceRuntimeManager(context.applicationContext)
        val helpers by lazy { stageHelpers(context.applicationContext) }
        val host = AgentBrowserUserControl(context.applicationContext, manager::execute)
        return definitions(manager::execute,
            { AgentOnDeviceRuntimeTools.executionAvailability(manager.cachedStatus()) }, { helpers },
            { AgentBrowserHostAuthority.token(context.applicationContext, scope(it)) }, host::request)
    }

    internal fun definitions(
        execute: (AgentRuntimeExecutionRequest) -> AgentRuntimeExecutionResponse,
        availability: () -> AgentNativeToolAvailability = { AgentNativeToolAvailability.AVAILABLE },
        helpers: () -> List<AgentRuntimeHostInput> = { emptyList() },
        hostCapability: (AgentNativeToolInvocationContext) -> String? = { null },
        requestUserControl: ((AgentNativeToolInvocation) -> AgentNativeToolExecutionResult)? = null
    ): List<AgentNativeToolDefinition> = listOf(false, true).map { mutation ->
        val id = if (mutation) ACT else OBSERVE
        val operations = if (mutation) listOf("create", "navigate", "back", "click", "fill", "select", "dialog", "close", "request_user_control")
            else listOf("observe", "pages", "screenshot", "wait_for_user")
        AgentNativeToolDefinition(
            descriptor = AgentNativeToolDescriptor(
                id = id, version = "1.1.0", title = if (mutation) "Operate an interactive browser" else "Observe an interactive browser",
                description = "Real Playwright browser in phone Linux. create returns an isolated live session; cookies persist within it. " +
                    "Observe before acting; click/fill/select require the observed revision and node_id. Choose frame_id for iframe controls. " +
                    "Inspect results to verify login, pagination and task success. User-only authentication requires user takeover, not bypass. " +
                    "Use request_user_control with live session_id/page_id when a user must sign in or interact personally. " +
                    "It opens the same browser for the user and returns handoff_id. A supervised planner yields durably until control returns; do not poll the model. " +
                    "Other callers can use wait_for_user to subscribe without accessing credentials. " +
                    "After control returns, observe again; completion is not proof of login or business success. " +
                    "Install browser-automation if its launcher is missing; static browser.session tools do not support login.",
                location = AgentNativeToolLocation.PHONE,
                inputSchema = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf(
                        "operation" to AgentNativeJsonSchema.string(enumValues = operations),
                        "session_id" to AgentNativeJsonSchema.string(maxLength = 128),
                        "page_id" to AgentNativeJsonSchema.string(maxLength = 128),
                        "frame_id" to AgentNativeJsonSchema.string(maxLength = 128),
                        "handoff_id" to AgentNativeJsonSchema.string(maxLength = 128),
                        "reason" to AgentNativeJsonSchema.string(maxLength = 500),
                        "url" to AgentNativeJsonSchema.string(maxLength = 4096),
                        "revision" to AgentNativeJsonSchema.string(maxLength = 256),
                        "node_id" to AgentNativeJsonSchema.string(maxLength = 128),
                        "value" to AgentNativeJsonSchema.string(maxLength = 65536),
                        "accept" to AgentNativeJsonSchema.boolean(),
                        "text_offset" to AgentNativeJsonSchema.integer(minimum = 0),
                        "control_offset" to AgentNativeJsonSchema.integer(minimum = 0)
                    ), required = setOf("operation"), additionalProperties = false
                ),
                outputSchema = AgentNativeJsonSchema.objectSchema(),
                risk = if (mutation) AgentNativeToolRisk.MEDIUM else AgentNativeToolRisk.LOW,
                idempotency = if (mutation) AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED else AgentNativeToolIdempotency.IDEMPOTENT,
                concurrency = if (mutation) AgentNativeToolConcurrency.SERIAL else AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
                effect = if (mutation) AgentNativeToolEffect.MUTATION else AgentNativeToolEffect.READ_ONLY,
                timeoutMillis = TIMEOUT
            ),
            executor = AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                invocation.reportProgress("browser", "Inspecting or operating the browser on this phone")
                if (invocation.input["operation"] == "request_user_control") {
                    return@AgentNativeToolExecutor requestUserControl?.invoke(invocation)
                        ?: AgentNativeToolExecutionResult.failure("browser_user_control_unavailable", "User control is not connected in this runtime.",
                            details = mapOf("executed" to false, "goal_terminal" to false))
                }
                val request = try { runtimeRequest(invocation, helpers(), hostCapability(invocation.context)) }
                catch (error: IllegalArgumentException) {
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("browser_scope_or_input_invalid",
                        error.message ?: "Check the browser input and conversation scope.",
                        details = mapOf("executed" to false, "goal_terminal" to false))
                }
                val response = execute(request)
                if (response.exitCode == 127) return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "browser_runtime_missing", "Install or update browser-automation and node-js, then inspect readiness.",
                    details = mapOf("executed" to false, "goal_terminal" to false, "required_packs" to listOf("browser-automation", "node-js"),
                        "installation_tool" to AgentOnDeviceRuntimeTools.INSTALL_PACK)
                )
                val envelope = runCatching { JSONObject(response.stdout.trim()) }.getOrNull()
                    ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                        "browser_result_unobserved", "No structured browser outcome was observed. Inspect the live session before repeating a mutation.",
                        details = mapOf("outcome_unknown" to mutation, "goal_terminal" to false, "exit_code" to response.exitCode))
                if (envelope.optBoolean("ok", false)) {
                    AgentNativeToolExecutionResult.success(envelope.optJSONObject("result").toNativeObject(), "Browser observation received")
                } else {
                    val error = envelope.optJSONObject("error")
                    AgentNativeToolExecutionResult.failure(error?.optString("code").orEmpty().ifBlank { "browser_operation_failed" },
                        error?.optString("message").orEmpty().ifBlank { "Inspect the current browser state." },
                        details = error?.optJSONObject("details").toNativeObject() + mapOf("goal_terminal" to false))
                }
            },
            availabilityProvider = AgentNativeToolAvailabilityProvider { availability() },
            executorId = "galaxyssi.phone_interactive_browser"
        )
    }

    internal fun scope(context: AgentNativeToolInvocationContext): String {
        require(context.conversationId.isNotBlank()) { "Interactive browser requires a bound conversation" }
        return AgentNativeJsonCodec.sha256(mapOf("session" to context.sessionId, "conversation" to context.conversationId,
            "workspace" to context.attributes["workspace_id"].orEmpty(), "caller" to context.callerId))
    }

    internal fun runtimeRequest(invocation: AgentNativeToolInvocation, helpers: List<AgentRuntimeHostInput> = emptyList(),
        hostCapability: String? = null): AgentRuntimeExecutionRequest = AgentRuntimeExecutionRequest(
        language = AgentRuntimeLanguage.SHELL,
        source = "command -v galaxyssi-browser >/dev/null 2>&1 || exit 127\n" +
            "exec galaxyssi-browser .galaxyssi-inputs/browser/browser-session-cli.cjs ${shellSingleQuote(scope(invocation.context))}",
        arguments = emptyList(), timeoutMillis = TIMEOUT, networkEnabled = true, artifactPaths = emptyList(),
        workspaceId = invocation.context.attributes["workspace_id"].orEmpty().ifBlank { invocation.context.conversationId },
        requestId = invocation.context.invocationId, cancellationToken = invocation.cancellationToken,
        secretEnvironment = secretEnvironment(invocation.input, hostCapability),
        hostInputFiles = helpers,
        resourceLimits = AgentRuntimeResourceLimits(wallClockMillis = TIMEOUT, cpuMillis = TIMEOUT, maxOutputBytes = 4L * 1024 * 1024),
        workspaceMutationExpected = false, discoverBuildArtifacts = false,
        progressListener = { invocation.reportProgress(it.stage, it.message, it.percent, it.sequence, it.timestampMillis) }
    )

    internal fun secretEnvironment(input: AgentNativeJsonObject, hostCapability: String? = null): Map<String, String> {
        val encoded = Base64.getEncoder().encodeToString(AgentNativeJsonCodec.stringify(input).toByteArray(Charsets.UTF_8))
        val chunks = encoded.chunked(4096)
        require(chunks.size <= if (hostCapability == null) 31 else 30) { "Browser input exceeds the runtime's ephemeral request channel; use a smaller operation payload." }
        return buildMap {
            hostCapability?.let { put("GALAXYSSI_BROWSER_HOST_TOKEN", it) }
            put("GALAXYSSI_BROWSER_REQUEST_COUNT", chunks.size.toString())
            chunks.forEachIndexed { index, chunk -> put("GALAXYSSI_BROWSER_REQUEST_$index", chunk) }
        }
    }

    internal fun stageHelpers(context: Context): List<AgentRuntimeHostInput> {
        val payloads = listOf("browser-session-engine.cjs", "browser-session-cli.cjs", "browser-user-control.cjs",
            "browser-service-supervisor.cjs").associateWith { name ->
            context.assets.open("interactive-browser/$name").use { it.readBytes() }
        }
        val digest = MessageDigest.getInstance("SHA-256")
        payloads.values.forEach(digest::update)
        val version = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        val directory = File(context.filesDir, "runtime-helper-code/browser/$version")
        check(directory.isDirectory || directory.mkdirs()) { "Could not stage the browser helper code" }
        return payloads.map { (name, bytes) ->
            val file = File(directory, name)
            if (!file.isFile) {
                val temporary = File.createTempFile("browser-", ".tmp", directory)
                try {
                    temporary.writeBytes(bytes)
                    check(temporary.renameTo(file) || file.isFile) { "Could not commit the browser helper code" }
                } finally { temporary.delete() }
            }
            AgentRuntimeHostInput(file, "browser/$name")
        }
    }
}
