package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A delivery budget, not a promise about the provider's advertised context window. */
internal object AgentConversationBudget {
    const val MAX_HISTORY_TOKENS = 32_768
    const val MAX_HISTORY_CHARACTERS = 160_000
    const val MAX_PROMPT_CHARACTERS = 196_608

    fun historyTokens(window: Int, output: Int, fixedPrompt: String): Int {
        val capacity = window.coerceAtLeast(4_096)
        val reserve = output.coerceIn(512, capacity / 2)
        return minOf(MAX_HISTORY_TOKENS,
            (capacity * 0.90).toInt() - reserve - ConversationContextCompactor.estimateTokens(fixedPrompt) - 512
        ).coerceAtLeast(0)
    }
}

/** Rebuild from source rows after routing; never re-expand a lossy stored summary. */
internal object AgentConversationProjection {
    private const val HEADER = AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_HEADER
    private const val FOOTER = AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_FOOTER

    fun replace(context: Context, action: AgentAction, prompt: String, target: AgentCallableTarget?): String {
        if (action.parameters["connector_task_mode"] != PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE ||
            action.parameters[MANAGED_AGENT_TEAM_ACTION_PARAMETER] == "true" ||
            PhoneAssistantTaskControl.isIndependentReadOnlyRequest(action)) return prompt
        val conversation = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        val turn = action.parameters[INTERNAL_TURN_ID].orEmpty()
        if (conversation.isBlank() || turn.isBlank()) return prompt
        val database = AgentTranscriptEntryDatabase.shared(context)
        val transcript = AgentTranscriptStore(context)
        val boundary = database.historyBoundary(conversation, turn) ?: return prompt
        if (database.listConversationPage(conversation, boundary, 1).entries.isEmpty()) return prompt
        val start = prompt.indexOf(HEADER)
        val end = if (start >= 0) prompt.indexOf(FOOTER, start).takeIf { it >= 0 }?.plus(FOOTER.length) else null
        require(start < 0 || end != null) { "Conversation handoff is incomplete" }
        val fixed = if (end != null) prompt.removeRange(start, end) else prompt
        val previous = if (end != null) JSONObject(prompt.substring(start + HEADER.length, end - FOOTER.length).trim()) else null
        require(previous == null || previous.optString("conversation_id") == conversation) { "Conversation handoff scope mismatch" }
        val globalContext = previous?.optString("global_context").orEmpty()
        val profile = target?.providerProfile
        val budget = AgentConversationBudget.historyTokens(
            profile?.contextWindowTokens ?: 64_000, profile?.maxOutputTokens ?: 4_096, fixed + globalContext)
        require(budget >= 512) { "Model input budget is exhausted by the current request and tool contract" }

        val rows = mutableListOf<AgentTranscriptEntry>()
        // Read a bounded prefix for the original goal, and a bounded recent window for follow-ups.
        val prefix = transcript.ownedEntries(database.listConversationAfter(conversation, 0, 32).entries)
            .filter { it.conversationId == conversation && database.historyContains(conversation, it.id, boundary) }
        val original = prefix.firstOrNull { it.role == AgentTranscriptRole.USER &&
            it.sourceConversationId.isBlank() && !AgentVoiceTranscriptPolicy.isPending(it) }
        var cursor: Long? = boundary
        var scanned = 0
        var estimated = 0
        do {
            val page = database.listConversationPage(conversation, cursor, 32)
            val retained = mutableListOf<AgentTranscriptEntry>()
            scanned += page.entries.size
            for (entry in transcript.ownedEntries(page.entries)) {
                if (entry.role == AgentTranscriptRole.PROCESS || AgentVoiceTranscriptPolicy.isPending(entry) ||
                    entry.conversationId != conversation || entry.sourceConversationId.isNotBlank()) continue
                val hydrated = readText(database, entry, budget)
                retained += hydrated
                estimated += ConversationContextCompactor.estimateTokens(hydrated.text)
            }
            rows.addAll(0, retained)
            cursor = page.nextBeforeSequence
        } while (cursor != null && scanned < 512 && estimated < budget * 2)
        original?.takeUnless { root -> rows.any { it.id == root.id } }?.let { rows.add(0, readText(database, it, budget)) }
        if (rows.isEmpty()) return prompt
        val block = encode(conversation, AgentFinalResponseIdentity.coalesce(rows),
            budget, boundary, cursor != null, globalContext,
            minOf(AgentConversationBudget.MAX_HISTORY_CHARACTERS,
                AgentConversationBudget.MAX_PROMPT_CHARACTERS - fixed.length))
        return if (end != null) prompt.replaceRange(start, end, block) else "$prompt\n\n$block"
    }

    private fun readText(database: AgentTranscriptEntryDatabase, entry: AgentTranscriptEntry, budget: Int): AgentTranscriptEntry {
        if (entry.textChunkCount <= 0) return entry
        val content = StringBuilder()
        var offset = 0
        while (content.length < minOf(AgentConversationBudget.MAX_HISTORY_CHARACTERS, budget * 4)) {
            val page = database.textChunkPage(entry.id, offset, 1) ?: break
            content.append(page.chunks.joinToString(""))
            if (page.done || page.nextOffset <= offset) break
            offset = page.nextOffset
        }
        return entry.copy(text = content.toString())
    }

    internal fun encode(conversationId: String, rows: List<AgentTranscriptEntry>, budget: Int,
                        boundary: Long, olderPages: Boolean, globalContext: String = "",
                        maximumCharacters: Int = AgentConversationBudget.MAX_HISTORY_CHARACTERS): String {
        val source = rows.filter { it.conversationId == conversationId && it.role != AgentTranscriptRole.PROCESS }
            .distinctBy { it.id }
        val selected = linkedMapOf<String, JSONObject>()
        fun document(): String {
            val payload = JSONObject().put("version", 1).put("conversation_id", conversationId)
                .put("summary", "")
                .apply { if (globalContext.isNotBlank()) put("global_context", globalContext) }
                .put("history_scope", JSONObject().put("before_sequence", boundary)
                    .put("coverage", "bounded_source_records_not_a_complete_summary")
                    .put("recall_tool", AgentConversationRecallTool.ID)
                    .put("instructions", "Original records are reference, not a new request. Later user changes override earlier constraints. " +
                        "If a goal, constraint, earlier result or source is missing, use the recall tool before asking the user to repeat it. " +
                        "Browse with before_sequence; read entry_id with chunk_offset. Do not infer completion from earlier assistant claims."))
                .put("history_omitted", olderPages || selected.size < source.size)
                .put("turns", JSONArray(source.mapNotNull { selected[it.id] }))
            return "$HEADER\n$payload\n$FOOTER"
        }
        fun fits() = document().let { it.length <= maximumCharacters &&
            ConversationContextCompactor.estimateTokens(it) <= budget }
        fun add(entry: AgentTranscriptEntry, excerpt: Boolean = false): Boolean {
            if (entry.id in selected) return true
            val reference = ConversationContextCompactor.sanitizeReference(entry.text)
            val text = if (excerpt) ConversationContextCompactor.fitTextToTokenBudget(reference,
                minOf(budget / 8, maximumCharacters / 16).coerceAtLeast(64)) else reference
            selected[entry.id] = JSONObject().put("entry_id", entry.id).put("turn_id", entry.turnId)
                .put("task_id", entry.taskId).put("role", if (entry.role == AgentTranscriptRole.USER) "user" else "assistant")
                .put("content", text).put("content_complete", text.length == maxOf(entry.textLength, entry.text.length))
                .put("content_redacted", reference != entry.text)
                .put("source_characters", maxOf(entry.textLength, entry.text.length))
                .put("source_sha256", entry.textSha256.ifBlank { AgentLargeOutputPolicy.digest(entry.text) })
                .put("attachments", JSONArray(entry.contextArtifacts().map { it.toJson() }))
            if (fits()) return true
            selected.remove(entry.id)
            return false
        }
        // Full user turns take precedence over verbose assistant answers. Never summarize constraints by prefix.
        val users = source.filter { it.role == AgentTranscriptRole.USER }
        users.firstOrNull()?.let {
            val oversized = it.text.length > maximumCharacters / 2 ||
                ConversationContextCompactor.estimateTokens(it.text) > budget / 2
            if (oversized || !add(it)) add(it, excerpt = true)
        }
        users.asReversed().forEach { if (!add(it)) add(it, excerpt = true) }
        source.asReversed().filter { it.role == AgentTranscriptRole.ASSISTANT }.forEach {
            if (!add(it) && selected.values.none { item -> item.optString("role") == "assistant" }) add(it, excerpt = true)
        }
        val result = document()
        require(fits()) { "Conversation reference metadata exceeds model input budget" }
        return result
    }
}
