package com.galaxyssi.chat

import org.json.JSONObject

/** Saved selection is not a new routing decision, and transport task IDs are not UI Run IDs. */
internal data class LocalModelLoopContinuation(
    val scope: AgentModelLoopScope,
    val prompt: String,
    val preferredProfileId: String,
    val hasAttachments: Boolean,
    val collaborationSourceMessageId: Long?,
    val manifestSha256: String,
    val systemPrompt: String
) {
    fun request(catalog: List<AgentNativeToolDescriptor>, cancellation: AgentNativeToolCancellationToken,
        progress: AgentModelToolLoopEventSink): AgentModelToolLoopRequest = AgentModelToolLoopRequest(
        sessionId = scope.session, conversationId = scope.conversation, turnId = scope.turn,
        taskId = scope.task, workspaceId = scope.workspace, callerId = scope.caller, loopId = scope.loop,
        collaborationSourceMessageId = collaborationSourceMessageId,
        messages = listOf(AgentModelMessage.system(systemPrompt), AgentModelMessage.user(prompt)),
        recoveryInputIdentity = AgentNativeJsonCodec.sha256(listOf(prompt, preferredProfileId,
            hasAttachments, collaborationSourceMessageId, systemPrompt)),
        budget = budget(), cancellationToken = cancellation, eventSink = progress,
        grantedPermissions = catalog.flatMap { it.requiredPermissions }.filter { it.required }
            .mapTo(linkedSetOf()) { it.id },
        grantedConsents = catalog.flatMap { it.requiredConsents }.filter { it.required }
            .mapTo(linkedSetOf()) { it.id })

    companion object {
        const val CALLER = "galaxyssi.local_model_web_loop"

        fun scope(identity: AgentLocalDispatchIdentity) = AgentModelLoopScope(identity.taskId,
            identity.conversationId, identity.turnId, identity.taskId,
            LocalModelAgentToolPolicy.workspace(identity.conversationId, identity.taskId), CALLER,
            "local-dispatch-" + AgentNativeJsonCodec.sha256(listOf(identity.sourceMessageId, identity.contactId,
                identity.conversationId, identity.turnId, identity.taskId, identity.actionId)))

        fun legacyLoopId(prompt: String, profile: String, attachments: Boolean, collaborationSource: Long?) =
            "local-web-" + AgentNativeJsonCodec.sha256(buildList {
                add(prompt); add(profile); add(attachments); collaborationSource?.let { add(it) }
            })

        fun budget() = AgentModelToolLoopBudget(maxRounds = 8, maxToolCalls = 32, maxDepth = 4,
            maxTokens = 32_000, maxDurationMillis = 60L * 60_000L, maxRetriesPerCall = 1,
            maxRepeatedCallSignatures = 2, enforceCountLimits = false)
    }
}

/** Uses the existing chunked encrypted journal. No independent JSON file or plaintext request cache. */
internal class LocalModelLoopContinuationStore(private val journal: AgentModelLoopJournal) {
    suspend fun prepare(identity: AgentLocalDispatchIdentity, prompt: String, preferredProfileId: String,
        hasAttachments: Boolean, collaborationSourceMessageId: Long?, manifestSha256: String,
        systemPrompt: String): LocalModelLoopContinuation {
        val scope = LocalModelLoopContinuation.scope(identity)
        val proposed = LocalModelLoopContinuation(scope, prompt, preferredProfileId, hasAttachments,
            collaborationSourceMessageId, manifestSha256, systemPrompt)
        return journal.withLease(scope) { records ->
            val existing = records.read(OPERATION)
            if (existing != null) {
                val saved = decode(scope, existing)
                // Locale/display changes must not rewrite the original model input on recovery.
                if (saved.copy(systemPrompt = systemPrompt) != proposed)
                    throw AgentModelLoopRecoveryException("local_model_saved_request_changed")
                saved
            } else {
                val legacy = scope.copy(loop = LocalModelLoopContinuation.legacyLoopId(prompt,
                    preferredProfileId, hasAttachments, collaborationSourceMessageId))
                if (journal.hasRecords(legacy))
                    throw AgentModelLoopRecoveryException("local_model_legacy_checkpoint_requires_reconciliation")
                records.write(OPERATION, encode(proposed))
                proposed
            }
        }
    }

    suspend fun restore(identity: AgentLocalDispatchIdentity, manifestSha256: String): LocalModelLoopContinuation {
        val scope = LocalModelLoopContinuation.scope(identity)
        return journal.withLease(scope) { records ->
            val saved = decode(scope, records.read(OPERATION)
                ?: throw AgentModelLoopRecoveryException("local_model_saved_request_missing"))
            if (saved.manifestSha256 != manifestSha256)
                throw AgentModelLoopRecoveryException("local_model_saved_catalog_changed")
            saved
        }
    }

    private fun encode(saved: LocalModelLoopContinuation): String = AgentNativeJsonCodec.stringify(mapOf(
        "version" to 1, "scope" to saved.scope.value(), "prompt" to saved.prompt,
        "profile" to saved.preferredProfileId, "attachments" to saved.hasAttachments,
        "collaboration_source" to saved.collaborationSourceMessageId, "manifest" to saved.manifestSha256,
        "system" to saved.systemPrompt))

    private fun decode(scope: AgentModelLoopScope, encoded: String): LocalModelLoopContinuation = try {
        val json = JSONObject(encoded)
        check(json.getInt("version") == 1 && AgentNativeJsonCodec.sha256(scope.value()) ==
            AgentNativeJsonCodec.sha256(scope.value().keys.associateWith { json.getJSONObject("scope").getString(it) }))
        check(json.has("collaboration_source"))
        LocalModelLoopContinuation(scope, json.getString("prompt"), json.getString("profile"),
            json.getBoolean("attachments"), if (json.isNull("collaboration_source")) null
                else json.getLong("collaboration_source"), json.getString("manifest"), json.getString("system"))
    } catch (error: Exception) {
        throw AgentModelLoopRecoveryException("local_model_saved_request_invalid", error)
    }

    private companion object { const val OPERATION = "local-dispatch-request:v1" }
}
