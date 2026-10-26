package com.galaxyssi.chat

/** Semantic actions, not speech commands. All providers use the same phone-side contracts. */
internal fun interface AgentAppControlPlatform {
    fun execute(operation: String, input: AgentNativeJsonObject, invocation: AgentNativeToolInvocation): AgentNativeJsonObject
}

internal object AgentAppControlTools {
    const val PREFIX = "galaxyssi.app."
    val toolIds = setOf("context", "reminders", "contacts", "send_message", "news", "read_article", "navigate", "playback")
        .mapTo(linkedSetOf()) { PREFIX + it }

    fun definitions(platform: AgentAppControlPlatform): List<AgentNativeToolDefinition> {
        fun string(max: Int = 256) = AgentNativeJsonSchema.string(maxLength = max)
        fun define(operation: String, description: String, properties: Map<String, AgentNativeJsonSchema> = emptyMap(),
            required: Set<String> = emptySet(), readOnly: Boolean = true): AgentNativeToolDefinition {
            val descriptor = AgentNativeToolDescriptor(
                id = PREFIX + operation, version = "1.0.0", title = "GalaxySSI $operation",
                description = description, location = AgentNativeToolLocation.PHONE,
                inputSchema = AgentNativeJsonSchema.objectSchema(properties, required, additionalProperties = false),
                outputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = true),
                risk = if (readOnly) AgentNativeToolRisk.LOW else AgentNativeToolRisk.MEDIUM,
                capabilities = setOf("app_control", "voice_interaction"), timeoutMillis = 15_000,
                idempotency = if (readOnly) AgentNativeToolIdempotency.IDEMPOTENT
                    else AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED,
                concurrency = if (readOnly) AgentNativeToolConcurrency.PARALLEL_READ_ONLY else AgentNativeToolConcurrency.SERIAL,
                effect = if (readOnly) AgentNativeToolEffect.READ_ONLY else AgentNativeToolEffect.MUTATION)
            return AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                try { AgentNativeToolExecutionResult.success(platform.execute(operation, invocation.input, invocation)) }
                catch (error: AppControlFailure) { AgentNativeToolExecutionResult.failure(error.code, error.message.orEmpty()) }
            }, executorId = "galaxyssi.android_app_control")
        }
        return listOf(
            define("reminders", "Read real delivered, unread proactive reminders. An empty list means no available reminder. " +
                "Never invent weather forecasts, appointments or task recovery status to fill the screen."),
            define("context", "Read active voice context: original Agent conversation, visible contact/article and playback. " +
                "Top-level IDs are frozen at the utterance; playback.state/article_id is current playback. " +
                "Bind follow-ups to observed IDs, not whichever page happens to be visible. Missing context requires clarification. No SIM audio access is implied."),
            define("contacts", "Find paired people/devices by display name. Zero or multiple matches require clarification. " +
                "Never choose an arbitrary contact or substitute an Agent for a person.",
                mapOf("query" to string(), "limit" to AgentNativeJsonSchema.integer(1, 20))),
            define("send_message", "Send exact text to an observed peer contact_id. Returns durable message_id and " +
                "queued/published/failed, NOT delivered. Do not send a voice-control instruction as message content.",
                mapOf("contact_id" to string(), "text" to string(10_000)), setOf("contact_id", "text"), false),
            define("news", "List readable local news by topic/title and optional earliest timestamp. Returns article IDs and sources. " +
                "Empty means no matching downloaded articles, not permission to invent news.",
                mapOf("query" to string(), "since_epoch_ms" to AgentNativeJsonSchema.integer(0),
                    "limit" to AgentNativeJsonSchema.integer(1, 20))),
            define("read_article", "Read the original article by ID, including the current news for a follow-up question.",
                mapOf("article_id" to string()), setOf("article_id")),
            define("navigate", "Open an App page or create a new conversation on this phone. Use an observed contact_id for contact chat. " +
                "No simulated clicks or Desktop execution. With new_conversation, optional message submits the user's remaining question " +
                "to the new conversation using its selected model. Never repeat that question in the old conversation.",
                mapOf("destination" to AgentNativeJsonSchema.string(enumValues = setOf("agent", "new_conversation", "contact", "news", "phone")),
                    "contact_id" to string(), "message" to string(10_000)), setOf("destination"), false),
            define("playback", "Control news playback without cancelling the Agent task. play_news takes ordered article_ids from news. " +
                "Pause preserves position; stop clears the queue. The utterance's article context remains unchanged. " +
                "Requires an active foreground voice session; never silently open the mic.",
                mapOf("operation" to AgentNativeJsonSchema.string(enumValues = setOf("play_news", "pause", "resume", "next", "stop")),
                    "article_ids" to AgentNativeJsonSchema.array(string(), maxItems = 20)), setOf("operation"), false))
    }
}

internal class AppControlFailure(val code: String, message: String) : RuntimeException(message)
